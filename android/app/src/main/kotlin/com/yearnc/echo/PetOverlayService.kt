package com.yearnc.echo

import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.AnimationDrawable
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.graphics.BitmapFactory
import android.text.TextUtils
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView

/**
 * 桌宠本体的悬浮窗（v4.0）。
 *
 * 只做“站在屏幕上”这一件事：透明动图、拖拽、点一下有反应、冒一句气泡。
 * 观察与唤醒都不在这里——那是 Dart 的事；这个服务只负责显示和把“被戳了”
 * 送回主 isolate。
 *
 * 用 specialUse 前台服务类型：它不采集屏幕，只维持一个小窗口常驻。
 * 真正截屏的是 ScreenWatchService，那边才需要 mediaProjection 类型。
 */
class PetOverlayService : Service() {
    companion object {
        const val ACTION_START = "com.yearnc.echo.pet.START"
        const val ACTION_STOP = "com.yearnc.echo.pet.STOP"
        const val ACTION_SAY = "com.yearnc.echo.pet.SAY"
        const val ACTION_REACT = "com.yearnc.echo.pet.REACT"
        const val ACTION_MOOD = "com.yearnc.echo.pet.MOOD"
        const val EXTRA_TEXT = "text"
        const val EXTRA_ACTION = "action"
        const val EXTRA_MOOD = "mood"
        const val EXTRA_REQUEST_ID = "requestId"

        private const val CHANNEL_ID = "echo_pet"
        private const val NOTIFICATION_ID = 4401

        @Volatile
        var running: Boolean = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, PetOverlayService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, PetOverlayService::class.java).setAction(ACTION_STOP)
            )
        }

        fun say(context: Context, text: String, requestId: String = "") {
            context.startService(
                Intent(context, PetOverlayService::class.java)
                    .setAction(ACTION_SAY)
                    .putExtra(EXTRA_TEXT, text)
                    .putExtra(EXTRA_REQUEST_ID, requestId)
            )
        }

        fun react(context: Context, action: String) {
            context.startService(
                Intent(context, PetOverlayService::class.java)
                    .setAction(ACTION_REACT)
                    .putExtra(EXTRA_ACTION, action)
            )
        }

        fun setMood(context: Context, mood: String) {
            context.startService(
                Intent(context, PetOverlayService::class.java)
                    .setAction(ACTION_MOOD)
                    .putExtra(EXTRA_MOOD, mood)
            )
        }
    }

    private lateinit var windowManager: WindowManager
    private lateinit var root: FrameLayout
    private lateinit var pet: ImageView
    private lateinit var bubble: TextView
    private var params: WindowManager.LayoutParams? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var bubbleAdded = false
    private var bubbleVisible = false
    private var breathAnimator: ObjectAnimator? = null
    private var mood = "idle"
    private var currentDrawable: Drawable? = null

    /// 桌宠帧序列解码后缓存最近几个动作，来回切换不用每次都解 24 张 PNG。
    private val animationCache = LinkedHashMap<String, AnimationDrawable>()

    private val handler = Handler(Looper.getMainLooper())
    private var lastTapAt = 0L
    private var bubbleFullText = ""
    private var bubbleChars = 0

    /// 待机时偶尔自己玩一下的动作。只放原本只能通过 pet_react 点播的那几个，
    /// 点击/拖拽/说话等现有反应保持不变。
    private val idleActions = listOf(
        "look", "sleep", "shy", "angry", "thinking",
        "cheer", "walk", "yawn", "stretch", "dance",
    )
    private var idleTimer: Runnable? = null
    private var idleActionRunning = false

    /// 桌宠本体比最初大 1.5 倍：132×74 → 198×111dp。
    private val petWidthDp = 198
    private val petHeightDp = 111

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelfSafely()
                return START_NOT_STICKY
            }
            // 服务可能被系统重建过：说/换动作/改表情之前先把窗口搭回来，
            // 否则 AVOID 拿到的是“bubble 还没初始化”，气泡就永远不出现。
            ACTION_SAY -> {
                ensureOverlay()
                showBubble(
                    intent.getStringExtra(EXTRA_TEXT).orEmpty(),
                    intent.getStringExtra(EXTRA_REQUEST_ID).orEmpty(),
                )
            }
            ACTION_REACT -> {
                ensureOverlay()
                playAction(intent.getStringExtra(EXTRA_ACTION).orEmpty())
            }
            ACTION_MOOD -> {
                ensureOverlay()
                setMood(intent.getStringExtra(EXTRA_MOOD).orEmpty())
            }
            else -> ensureOverlay()
        }
        return START_STICKY
    }

    private fun ensureOverlay() {
        if (::root.isInitialized) {
            startForegroundNow()
            return
        }
        startForegroundNow()
        buildOverlay()
    }

    private fun startForegroundNow() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        running = true
    }

    private fun buildOverlay() {
        // 窗口就是桌宠本体那么大：不再拿一块 320×190 的矩形去盖住桌面。
        // 背景必须显式透明，否则某些系统会给悬浮窗套一层黑色主题底。
        root = FrameLayout(this).apply { setBackgroundColor(Color.TRANSPARENT) }
        pet = ImageView(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        root.addView(
            pet,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        root.setOnClickListener { onPetTapped() }
        attachDrag()

        bubble = TextView(this).apply {
            // TextView 在 attach 之前收到 setText 会走 checkForRelayout，
            // 那里直接读 layoutParams.width；null 会 NPE。先塞一个占位，
            // 真正 addView 时 WindowManager 会换成自己的 LayoutParams。
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            )
            setTextColor(Color.parseColor("#333333"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
            typeface = Typeface.DEFAULT
            setPadding(dp(10), dp(6), dp(10), dp(6))
            maxWidth = dp(280)
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            setSingleLine(false)
            gravity = Gravity.CENTER
            background = android.graphics.drawable.GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                setColor(Color.parseColor("#F2FFFFFF"))
                setStroke(dp(1), Color.parseColor("#22000000"))
            }
            visibility = View.GONE
        }
        bubbleParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }

        val width = dp(petWidthDp)
        val height = dp(petHeightDp)
        val lp = WindowManager.LayoutParams(
            width,
            height,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            val prefs = getSharedPreferences("echo_pet", MODE_PRIVATE)
            x = prefs.getInt("x", resources.displayMetrics.widthPixels - width - dp(8))
            y = prefs.getInt("y", resources.displayMetrics.heightPixels / 2)
        }
        params = lp
        windowManager.addView(root, lp)
        applyMood("idle")
        // 常用动作先解好，别等第一次互动时在主线程里一口气解 24 张 PNG。
        for (key in listOf("happy", "shy", "sleep", "thinking")) {
            try {
                loadAnimated(key)
            } catch (_: Throwable) {
            }
        }
    }

    private fun overlayType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

    private fun attachDrag() {
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var dragging = false

        pet.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = params?.x ?: 0
                    startY = params?.y ?: 0
                    dragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (!dragging && (kotlin.math.abs(dx) > 12 || kotlin.math.abs(dy) > 12)) {
                        dragging = true
                        applyMood("drag")
                    }
                    if (dragging) {
                        params?.let {
                            it.x = startX + dx.toInt()
                            it.y = startY + dy.toInt()
                            if (::root.isInitialized) windowManager.updateViewLayout(root, it)
                            syncBubblePosition()
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (dragging) {
                        params?.let {
                            val dm = resources.displayMetrics
                            // 允许半贴边/探出屏幕，只要还留着四分之一可见；
                            // 以前松手就被夹回屏幕内，像“弹回来”一样。
                            val visibleX = (it.width * 0.25f).toInt().coerceAtLeast(dp(24))
                            val visibleY = (it.height * 0.25f).toInt().coerceAtLeast(dp(18))
                            it.x = it.x.coerceIn(
                                -it.width + visibleX,
                                dm.widthPixels - visibleX,
                            )
                            it.y = it.y.coerceIn(
                                -it.height + visibleY,
                                dm.heightPixels - visibleY,
                            )
                            if (::root.isInitialized) windowManager.updateViewLayout(root, it)
                            syncBubblePosition()
                            getSharedPreferences("echo_pet", MODE_PRIVATE)
                                .edit().putInt("x", it.x).putInt("y", it.y).apply()
                        }
                        applyMood("idle")
                        PetBridge.emit("dropped", mapOf("x" to params?.x, "y" to params?.y))
                    } else {
                        // 只有按在宠物中间那一片才算互动；边缘透明的地方
                        // 不该把点击抢走。
                        val w = pet.width.toFloat()
                        val h = pet.height.toFloat()
                        val inCenter =
                            kotlin.math.abs(event.x - w / 2) < w * 0.38f &&
                                kotlin.math.abs(event.y - h / 2) < h * 0.42f
                        if (inCenter) performClick()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun performClick() {
        val now = System.currentTimeMillis()
        if (now - lastTapAt < 600) return
        lastTapAt = now
        onPetTapped()
    }

    private fun onPetTapped() {
        applyMood("happy")
        handler.postDelayed({ if (mood == "happy") applyMood("idle") }, 5000)
        PetBridge.emit("tap")
    }

    private fun setMood(value: String) {
        if (value.isBlank()) return
        applyMood(value)
        if (value != "happy" && value != "drag") {
            handler.postDelayed({ if (mood == value) applyMood("idle") }, 6000)
        }
    }

    private fun playAction(action: String) {
        val key = when (action) {
            "happy", "开心" -> "happy"
            "shy", "害羞" -> "shy"
            "angry", "生气" -> "angry"
            "think", "thinking", "思考" -> "thinking"
            "cheer", "庆祝" -> "cheer"
            "sleep", "睡" -> "sleep"
            "yawn", "打哈欠" -> "yawn"
            "stretch", "伸懒腰" -> "stretch"
            "dance", "跳舞" -> "dance"
            "walk", "走路" -> "walk"
            "look", "张望" -> "look"
            else -> "idle"
        }
        applyMood(key)
        if (key != "sleep" && key != "idle") {
            handler.postDelayed({ if (mood == key) applyMood("idle") }, 5000)
        }
    }

    /// 在待机时排一个随机小动作；回到 idle 时重新计时。
    private fun scheduleIdleAction() {
        idleTimer?.let { handler.removeCallbacks(it) }
        idleTimer = Runnable { playIdleAction() }
        handler.postDelayed(idleTimer!!, (8000..18000L).random())
    }

    private fun playIdleAction() {
        if (mood != "idle" || idleActionRunning) {
            scheduleIdleAction()
            return
        }
        idleActionRunning = true
        val key = idleActions.random()
        applyMood(key)
        // 24 帧 × 200ms = 4.8 秒，留一点余量。
        handler.postDelayed({
            idleActionRunning = false
            if (mood == key) applyMood("idle")
        }, 5000)
    }

    private fun applyMood(key: String) {
        // 任何主动动作/互动都会重置待机轮盘；只有回到 idle 才重新排。
        idleTimer?.let { handler.removeCallbacks(it) }
        idleTimer = null
        mood = key
        val drawable = loadAnimated(key) ?: loadAnimated("idle")
        if (drawable == null) {
            PetBridge.emit("error", mapOf("message" to "桌宠素材没找到：$key"))
            return
        }
        val old = currentDrawable
        currentDrawable = drawable
        pet.setImageDrawable(drawable)
        // 先换上新帧，再停旧的：反过来的话中间会闪一帧空白。
        if (old !== drawable) (old as? AnimationDrawable)?.stop()
        breathAnimator?.cancel()
        breathAnimator = null
        if (drawable is AnimationDrawable) {
            drawable.isOneShot = false
            drawable.start()
        } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            breathAnimator = ObjectAnimator.ofPropertyValuesHolder(
                pet,
                PropertyValuesHolder.ofFloat(View.SCALE_X, 1f, 1.03f, 1f),
                PropertyValuesHolder.ofFloat(View.SCALE_Y, 1f, 0.97f, 1f),
            ).apply {
                duration = 2200
                repeatCount = ObjectAnimator.INFINITE
                start()
            }
        }
        if (key == "idle") scheduleIdleAction()
        PetBridge.emit("mood", mapOf("mood" to key))
    }

    /// 从透明 PNG 序列装出一个 AnimationDrawable。
    ///
    /// 之前用动画 WebP + ImageDecoder，在部分 ROM 上透明区域会被画成黑框；
    /// PNG 序列的 alpha 是所有版本都认的。每帧 150ms：比原来的 10fps
    /// 慢一些，但不会慢到像卡住。
    private fun loadAnimated(key: String): Drawable? {
        animationCache[key]?.let { return it }
        val dir = "flutter_assets/assets/pet_frames"
        val names = try {
            assets.list(dir)
                ?.filter { it.startsWith("${key}_") && it.endsWith(".png") }
                ?.sorted()
        } catch (_: Throwable) {
            null
        } ?: return null
        if (names.isEmpty()) return null

        val animation = AnimationDrawable()
        for (name in names) {
            try {
                assets.open("$dir/$name").use { stream ->
                    val bitmap = BitmapFactory.decodeStream(stream)
                    if (bitmap != null) {
                        animation.addFrame(BitmapDrawable(resources, bitmap), 150)
                    }
                }
            } catch (_: Throwable) {
            }
        }
        if (animation.numberOfFrames == 0) return null
        animationCache[key] = animation
        while (animationCache.size > 5) {
            val oldest = animationCache.keys.first()
            animationCache.remove(oldest)?.stop()
        }
        return animation
    }

    private fun showBubble(text: String, requestId: String = "") {
        val clean = text.trim()
        if (clean.isEmpty() || !::bubble.isInitialized) return
        val lp = bubbleParams ?: return

        try {
            // 先用完整文本量出“最多两行”需要多大，窗口固定成这个尺寸，
            // 逐字出现时就不会一边打字一边把气泡撑大。
            bubbleFullText = clean.take(120)
            bubble.text = bubbleFullText
            bubble.measure(
                View.MeasureSpec.makeMeasureSpec(dp(280), View.MeasureSpec.AT_MOST),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
            )
            lp.width = bubble.measuredWidth.coerceAtLeast(dp(60))
            lp.height = bubble.measuredHeight.coerceAtLeast(dp(30))
            bubble.text = ""
            bubbleChars = 0
            bubble.visibility = View.VISIBLE
            bubbleVisible = true
            syncBubblePosition()
            if (!bubbleAdded) {
                windowManager.addView(bubble, lp)
                bubbleAdded = true
            } else {
                windowManager.updateViewLayout(bubble, lp)
            }

            handler.removeCallbacks(bubbleTyper)
            handler.removeCallbacks(hideBubble)
            handler.post(bubbleTyper)
            handler.postDelayed(
                hideBubble,
                (6000L + bubbleFullText.length * 35L).coerceAtMost(20000L),
            )
            // 气泡不该重置待机轮盘：只有睡着时被气泡叫醒才需要换动作。
            if (mood == "sleep") applyMood("happy")
            PetBridge.emit(
                "bubble",
                mapOf(
                    "ok" to true,
                    "text" to clean,
                    "requestId" to requestId,
                ),
            )
        } catch (error: Throwable) {
            // 气泡失败不该把服务带崩；留下一条事件方便排查。
            PetBridge.emit(
                "bubble",
                mapOf(
                    "ok" to false,
                    "message" to "气泡没显示：${error.message}",
                    "requestId" to requestId,
                ),
            )
        }
    }

    /// 逐字出现。模型仍然是一次把整句交过来，这里只负责让它“说”出来。
    private val bubbleTyper = object : Runnable {
        override fun run() {
            if (bubbleFullText.isEmpty() || !::bubble.isInitialized) return
            bubbleChars = (bubbleChars + 2).coerceAtMost(bubbleFullText.length)
            bubble.text = bubbleFullText.substring(0, bubbleChars)
            if (bubbleChars < bubbleFullText.length) {
                handler.postDelayed(this, 70)
            }
        }
    }

    /// 气泡单独一个窗口：它不接收触摸，所以不会扩大桌宠的点击范围。
    /// 垂直位置对齐到裙子上的小鲸鱼那一块，而不是压在头顶。
    private fun syncBubblePosition() {
        if (!::bubble.isInitialized) return
        val p = params ?: return
        val lp = bubbleParams ?: return
        val dm = resources.displayMetrics
        val w = lp.width.takeIf { it > 0 } ?: dp(160)
        val h = lp.height.takeIf { it > 0 } ?: dp(36)
        // 气泡叠在桌宠身上，而不是浮在旁边：水平对着宠物居中，
        // 垂直中心落在裙摆小鲸鱼那一带（约 70% 高度）。
        lp.x = p.x + (p.width - w) / 2
        val targetY = p.y + (p.height * 0.70f).toInt() - h / 2
        lp.y = targetY
        lp.x = lp.x.coerceIn(0, (dm.widthPixels - w).coerceAtLeast(0))
        lp.y = lp.y.coerceIn(0, (dm.heightPixels - h).coerceAtLeast(0))
        if (bubbleAdded) {
            windowManager.updateViewLayout(bubble, lp)
        }
    }

    private val hideBubble = Runnable {
        bubbleVisible = false
        handler.removeCallbacks(bubbleTyper)
        if (::bubble.isInitialized) bubble.visibility = View.GONE
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "桌宠",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "桌宠在屏幕上时保持常驻"
                setShowBadge(false)
            }
        )
    }

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("桌宠正在陪你")
            .setContentText("点一下可以打开回响 Echo")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    private fun stopSelfSafely() {
        handler.removeCallbacks(hideBubble)
        (currentDrawable as? AnimationDrawable)?.stop()
        breathAnimator?.cancel()
        if (bubbleAdded && ::bubble.isInitialized) {
            try {
                windowManager.removeView(bubble)
            } catch (_: Throwable) {
            }
            bubbleAdded = false
        }
        if (::root.isInitialized) {
            try {
                windowManager.removeView(root)
            } catch (_: Throwable) {
            }
            root.removeAllViews()
        }
        handler.removeCallbacksAndMessages(null)
        running = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        PetBridge.emit("stopped")
    }

    override fun onDestroy() {
        if (bubbleAdded && ::bubble.isInitialized) {
            try {
                windowManager.removeView(bubble)
            } catch (_: Throwable) {
            }
        }
        if (::root.isInitialized) {
            try {
                windowManager.removeView(root)
            } catch (_: Throwable) {
            }
        }
        running = false
        super.onDestroy()
    }
}
