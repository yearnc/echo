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
import android.content.res.Configuration
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.AnimationDrawable
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import org.json.JSONObject
import java.util.Locale
import kotlin.math.abs
import kotlin.random.Random

/**
 * 桌宠本体的悬浮窗（v4.0）。
 *
 * 只做“站在屏幕上”这一件事：透明动画、拖拽、点一下有反应、冒一句气泡。
 * 观察与唤醒都不在这里——那是 Dart 的事；这个服务只负责显示和把“被戳了”
 * 送回主 isolate。
 *
 * v4.1 起是**两个窗口**：
 * - 舞台窗：整帧 197×111dp，**不接收触摸**，特效（烟花、动物环绕…）不会
 *   被裁掉，空白处也不会挡着下面的应用；
 * - 命中窗：只盖住角色本体（约 92×97dp），拖拽/点击只在这块里生效。
 * 气泡还是单独一层，不可触摸。
 *
 * 用 specialUse 前台服务类型：它不采集屏幕，只维持窗口常驻。
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

    /** 一个动作的规格，来自 `assets/pet_frames/manifest.json`。 */
    private data class PetAction(
        val key: String,
        val name: String,
        val kind: String,
        val frames: Int,
        val expose: String?,
        val category: String?,
        val move: MoveSpec?,
    )

    private data class MoveSpec(
        val minDp: Int,
        val maxDp: Int,
        val lead: Float,
        val tail: Float,
    )

    private lateinit var windowManager: WindowManager
    private lateinit var displayManager: DisplayManager

    /// 舞台窗：整帧，不接收触摸。
    private lateinit var root: FrameLayout
    private lateinit var pet: ImageView

    /// 命中窗：只盖住本体。
    private lateinit var hit: View

    private lateinit var bubble: TextView

    private var params: WindowManager.LayoutParams? = null
    private var hitParams: WindowManager.LayoutParams? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var hitAdded = false
    private var bubbleAdded = false
    private var bubbleVisible = false
    private var breathAnimator: ObjectAnimator? = null

    private var currentDrawable: Drawable? = null
    private var currentAction: PetAction? = null
    private var facingRight = false

    /// 每次换动作都 +1：同一种动作连着播两次时，旧的定时器不能把新的顶回待机。
    private var actionToken = 0

    /// 帧序列解码后缓存最近几个动作。320×180×4B ≈ 225KB/帧，48 帧约 10.8MB；
    /// 只留 3 个，避免帧数翻倍后把堆内存顶穿。
    private val animationCache = LinkedHashMap<String, AnimationDrawable>()

    private val handler = Handler(Looper.getMainLooper())
    private var lastTapAt = 0L
    private var bubbleFullText = ""
    private var bubbleChars = 0

    private var idleTimer: Runnable? = null

    // ---- 动作清单（manifest.json） ----
    private var loadedActions = false
    private var actions: List<PetAction> = emptyList()
    private val byExpose = mutableMapOf<String, PetAction>()
    private val actionsByName = mutableMapOf<String, PetAction>()
    private val actionsByKey = mutableMapOf<String, PetAction>()
    private var idlePool: List<PetAction> = emptyList()
    private var clickPool: List<PetAction> = emptyList()
    private var movePool: List<PetAction> = emptyList()
    private var turnPool: List<PetAction> = emptyList()
    private var dragAction: PetAction? = null
    private var categoryWeights: Map<String, Int> = emptyMap()
    private var kindWeights: Map<String, Int> = emptyMap()

    private var frameMs = 150L
    private var imageWidth = 320
    private var imageHeight = 180
    private var stageWidthDp = 197
    private var stageHeightDp = 111
    private var hitRect = Rect(85, 9, 235, 166)

    /// 气泡宽度上限：280dp 时要二十多个字才折行，看着像“不换行”。
    private val bubbleMaxWidthDp = 190

    /// 横竖屏切换、分屏尺寸变化都要重新夹位置：x/y 是按像素存的，
    /// 竖屏里宽 1080，横屏里挪到 2000 之后再转回来就整只在屏幕外了。
    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = Unit
        override fun onDisplayRemoved(displayId: Int) = Unit
        override fun onDisplayChanged(displayId: Int) {
            recoverAfterDisplayChange()
        }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private fun randInt(from: Int, to: Int): Int {
        if (to <= from) return from
        return Random.nextInt(from, to + 1)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        try {
            displayManager.registerDisplayListener(displayListener, handler)
        } catch (_: Throwable) {
            // 拿不到 DisplayManager 也不致命：onConfigurationChanged 还会兜一层。
        }
        createChannel()
    }

    /// 有些 ROM 不会给 Service 派发屏幕变化，DisplayListener 是主路，
    /// 这个回调是兜底——两条路都只做同一件“夹回来”。
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        recoverAfterDisplayChange()
    }

    /// 旋转后立刻收一次；有的 ROM 尺寸报告慢半拍，再补一次。
    private fun recoverAfterDisplayChange() {
        handler.post {
            clampPetPosition(keepBodyVisible = true)
            if (bubbleVisible) syncBubblePosition()
        }
        handler.postDelayed({
            clampPetPosition(keepBodyVisible = true)
            updateHitPosition()
            if (bubbleVisible) syncBubblePosition()
        }, 350L)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelfSafely()
                return START_NOT_STICKY
            }
            // 服务可能被系统重建过：说/换动作/改表情之前先把窗口搭回来，
            // 否则主 isolate 拿到的是“bubble 还没初始化”，气泡就永远不出现。
            ACTION_SAY -> {
                ensureOverlay()
                showBubble(
                    intent.getStringExtra(EXTRA_TEXT).orEmpty(),
                    intent.getStringExtra(EXTRA_REQUEST_ID).orEmpty(),
                )
            }
            ACTION_REACT -> {
                ensureOverlay()
                playNamedAction(intent.getStringExtra(EXTRA_ACTION).orEmpty())
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

    // ---------------------------------------------------------------- manifest

    private fun ensureManifest(): Boolean {
        if (loadedActions) return actions.isNotEmpty()
        loadedActions = true
        try {
            val text = assets
                .open("flutter_assets/assets/pet_frames/manifest.json")
                .bufferedReader().use { it.readText() }
            val json = JSONObject(text)
            frameMs = json.optLong("frameMs", 150L)
            json.optJSONObject("imageSize")?.let {
                imageWidth = it.optInt("width", 320)
                imageHeight = it.optInt("height", 180)
            }
            json.optJSONObject("stageDp")?.let {
                stageWidthDp = it.optInt("width", 197)
                stageHeightDp = it.optInt("height", 111)
            }
            json.optJSONObject("hitRect")?.let {
                hitRect = Rect(
                    it.optInt("left", 85),
                    it.optInt("top", 9),
                    it.optInt("right", 235),
                    it.optInt("bottom", 166),
                )
            }
            json.optJSONObject("categoryWeights")?.let { obj ->
                categoryWeights = obj.keys().asSequence().associateWith { key ->
                    obj.optInt(key, 0)
                }
            }
            json.optJSONObject("weights")?.let { obj ->
                kindWeights = obj.keys().asSequence().associateWith { key ->
                    obj.optInt(key, 0)
                }
            }

            val arr = json.getJSONArray("actions")
            val list = ArrayList<PetAction>(arr.length())
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val moveObj = o.optJSONObject("move")
                val action = PetAction(
                    key = o.getString("key"),
                    name = o.optString("name"),
                    kind = o.optString("kind"),
                    frames = o.optInt("frames", 48),
                    expose = o.optString("expose").takeIf { it.isNotBlank() },
                    category = o.optString("category").takeIf { it.isNotBlank() },
                    move = moveObj?.let {
                        MoveSpec(
                            minDp = it.optInt("minDp", 60),
                            maxDp = it.optInt("maxDp", 160),
                            lead = it.optDouble("lead", 0.18).toFloat(),
                            tail = it.optDouble("tail", 0.18).toFloat(),
                        )
                    },
                )
                list.add(action)
                actionsByKey[action.key] = action
                if (action.name.isNotBlank()) actionsByName[action.name] = action
                action.expose?.let { byExpose[it] = action }
            }
            actions = list
            idlePool = list.filter { it.kind == "idle" }
            clickPool = list.filter { it.kind == "click" }
            movePool = list.filter { it.kind == "move" }
            turnPool = list.filter { it.kind == "turn" }
            dragAction = list.firstOrNull { it.kind == "drag" }
            if (kindWeights.isEmpty()) {
                kindWeights = mapOf(
                    "idle" to 10,
                    "turn" to 5,
                    "move" to 15,
                    "click" to 10,
                    "category" to 60,
                )
            }
            return actions.isNotEmpty()
        } catch (error: Throwable) {
            PetBridge.emit("error", mapOf("message" to "桌宠动作清单读不出来：${error.message}"))
            return false
        }
    }

    // ---------------------------------------------------------------- overlay

    private fun buildOverlay() {
        ensureManifest()
        // v4.2.8：窗口只包住角色本体（整帧 197×111dp → 约 100×105dp），
        // 用 CENTER_CROP 把周围的透明边裁掉。触摸范围不再比桌宠大两三倍。
        // 代价：烟花、动物环绕这类超出本体的特效会被窗口裁掉。
        val bodyWidthDp =
            hitRect.width() * stageWidthDp / imageWidth.coerceAtLeast(1)
        val bodyHeightDp =
            hitRect.height() * stageHeightDp / imageHeight.coerceAtLeast(1)
        val stageWidth = dp((bodyWidthDp + 8).coerceAtLeast(48))
        val stageHeight = dp((bodyHeightDp + 8).coerceAtLeast(48))

        // 舞台：只显示本体，背景显式透明。
        root = FrameLayout(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            alpha = 1f
        }
        pet = ImageView(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            scaleType = ImageView.ScaleType.CENTER_CROP
            // 帧本身是不透明的（alpha 255）；显式锁一遍，避免任何继承下来的透明度。
            alpha = 1f
        }
        root.addView(
            pet,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        bubble = TextView(this).apply {
            // TextView 在 attach 之前收到 setText 会走 checkForRelayout，
            // 那里直接读 layoutParams.width；null 会 NPE。先塞一个占位。
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            )
            setTextColor(Color.parseColor("#333333"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
            typeface = Typeface.DEFAULT
            setPadding(dp(10), dp(6), dp(10), dp(6))
            maxWidth = dp(bubbleMaxWidthDp)
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            setSingleLine(false)
            gravity = Gravity.CENTER
            background = android.graphics.drawable.GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                setColor(Color.parseColor("#FFFFFFFF"))
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

        // **不能**再带 FLAG_NOT_TOUCHABLE：Android 12+/部分 ROM 会把“允许点击穿透”
        // 的悬浮窗最大不透明度压到 0.8，窗口 alpha 设 1.0 也没用——桌宠看起来永远发虚。
        // v4.0.0 是单窗口、可触摸的，所以它一直是不透明的；v4.1 拆双窗口后才开始透。
        // 代价：舞台窗的空白区会吞触摸（拖拽/点击仍由上层命中窗处理）。
        val lp = WindowManager.LayoutParams(
            stageWidth,
            stageHeight,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            // 窗口 alpha 保持默认 1.0：不设它，免得部分 ROM 把值粘在 surface 上。
            val prefs = getSharedPreferences("echo_pet", MODE_PRIVATE)
            val (screenW, screenH) = displaySize()
            x = prefs.getInt("x", screenW - stageWidth - dp(8))
            y = prefs.getInt("y", screenH / 2)
        }
        params = lp
        windowManager.addView(root, lp)

        // 命中窗：和舞台完全重合——舞台已经裁到本体了，触摸范围就是本体。
        hit = FrameLayout(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            alpha = 1f
        }
        attachDrag()
        val hp = WindowManager.LayoutParams(
            stageWidth,
            stageHeight,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }
        hitParams = hp
        windowManager.addView(hit, hp)
        hitAdded = true

        // 上次可能是横屏存下的坐标，也可能换了窗口尺寸：先把本体收进屏幕。
        clampPetPosition(keepBodyVisible = true)
        updateHitPosition()
        startIdle()
        // 待机先解好，别等第一次互动时在主线程里一口气解 48 帧。
        idlePool.firstOrNull()?.let {
            try {
                loadAnimated(it)
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

    /// 当前屏幕尺寸（像素）。
    ///
    /// **不能问 `currentWindowMetrics`**：Service 不是 UI 上下文，API 30+ 对它
    /// 返回的是「最大边界」（横竖屏合成后的 16:16），横屏里把宠物挪到右边、
    /// 转回竖屏时它仍觉得没越界，于是宠物就留在屏幕外了。`getRealMetrics`
    /// 给的是当前旋转后的真实尺寸。
    private fun displaySize(): Pair<Int, Int> {
        try {
            val display = displayManager.getDisplay(android.view.Display.DEFAULT_DISPLAY)
            if (display != null) {
                val metrics = android.util.DisplayMetrics()
                @Suppress("DEPRECATION")
                display.getRealMetrics(metrics)
                if (metrics.widthPixels > 0 && metrics.heightPixels > 0) {
                    return metrics.widthPixels to metrics.heightPixels
                }
            }
        } catch (_: Throwable) {
        }
        val dm = resources.displayMetrics
        return dm.widthPixels to dm.heightPixels
    }

    /// 把舞台夹回可见范围，并带着命中窗与气泡一起动。
    ///
    /// - [keepBodyVisible] = true：**角色本体**必须整个留在屏幕里（旋转、冷启动）。
    ///   窗口里本体两侧是透明的，只按窗口算的话，本体可能整只都在屏幕外。
    /// - false：拖拽松手时允许半贴边，只要窗口还剩四分之一可见。
    private fun clampPetPosition(keepBodyVisible: Boolean = false) {
        val p = params ?: return
        if (!::root.isInitialized) return
        val (screenW, screenH) = displaySize()
        val margin = dp(8)
        val minX: Int
        val maxX: Int
        val minY: Int
        val maxY: Int
        if (keepBodyVisible) {
            // v4.2.8 起窗口本身就只含角色本体，不用再从整帧里推算本体偏移。
            minX = margin
            maxX = (screenW - p.width - margin).coerceAtLeast(minX)
            minY = margin
            maxY = (screenH - p.height - margin).coerceAtLeast(minY)
        } else {
            val visibleX = (p.width * 0.25f).toInt().coerceAtLeast(dp(24))
            val visibleY = (p.height * 0.25f).toInt().coerceAtLeast(dp(18))
            minX = -p.width + visibleX
            maxX = (screenW - visibleX).coerceAtLeast(minX)
            minY = -p.height + visibleY
            maxY = (screenH - visibleY).coerceAtLeast(minY)
        }
        p.x = p.x.coerceIn(minX, maxX)
        p.y = p.y.coerceIn(minY, maxY)
        try {
            windowManager.updateViewLayout(root, p)
        } catch (_: Throwable) {
        }
        updateHitPosition()
        getSharedPreferences("echo_pet", MODE_PRIVATE)
            .edit().putInt("x", p.x).putInt("y", p.y).apply()
    }

    /// 让命中窗贴在舞台里角色本体那一块。
    private fun updateHitPosition() {
        if (!hitAdded) return
        val p = params ?: return
        val hp = hitParams ?: return
        // 命中窗与舞台完全重合。
        hp.x = p.x
        hp.y = p.y
        hp.width = p.width
        hp.height = p.height
        try {
            windowManager.updateViewLayout(hit, hp)
        } catch (_: Throwable) {
        }
    }

    private fun attachDrag() {
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var dragging = false

        hit.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = params?.x ?: 0
                    startY = params?.y ?: 0
                    dragging = false
                    // 先别换成“被抓起”的姿势：轻点一下不该闪一下抓取动画。
                    // 只是把待机轮盘停住，免得按着的这几秒里自己换动作。
                    stopRoaming()
                    stopIdleTimer()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (!dragging && (abs(dx) > 12 || abs(dy) > 12)) {
                        dragging = true
                        dragAction?.let {
                            playAction(it, loop = true, autoIdle = false)
                        }
                    }
                    if (dragging) {
                        params?.let {
                            it.x = startX + dx.toInt()
                            it.y = startY + dy.toInt()
                            if (::root.isInitialized) windowManager.updateViewLayout(root, it)
                            updateHitPosition()
                            syncBubblePosition()
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (dragging) {
                        // 允许半贴边/探出屏幕，只要还留着四分之一可见。
                        clampPetPosition()
                        syncBubblePosition()
                        PetBridge.emit("dropped", mapOf("x" to params?.x, "y" to params?.y))
                        startIdle()
                    } else {
                        val w = hit.width.toFloat()
                        val h = hit.height.toFloat()
                        val inCenter =
                            abs(event.x - w / 2) < w * 0.46f &&
                                abs(event.y - h / 2) < h * 0.46f
                        // 点到了就让点击回应自己播完再回待机；别在这里把动作顶掉。
                        if (inCenter) performClick() else startIdle()
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
        val pick = clickPool.randomOrNull() ?: byExpose["happy"]
        if (pick != null) {
            playAction(pick, loop = false, autoIdle = true)
        } else {
            startIdle()
        }
        PetBridge.emit("tap")
    }

    // ---------------------------------------------------------------- actions

    private fun resolveAction(raw: String): PetAction? {
        val value = raw.trim()
        if (value.isEmpty()) return null
        val lower = value.lowercase(Locale.ROOT)
        val alias = when (lower) {
            "sleepy" -> "sleep"
            "love" -> "shy"
            "talking" -> "thinking"
            else -> lower
        }
        if (alias == "idle") return idlePool.firstOrNull()
        return byExpose[alias]
            ?: byExpose[lower]
            ?: actionsByName[value]
            ?: actionsByKey[value]
    }

    /// 来自工具/桥的“点播”：走路类动作真的走起来，其余播一遍回待机。
    private fun playNamedAction(raw: String) {
        val action = resolveAction(raw)
        if (action == null) {
            PetBridge.emit("error", mapOf("message" to "没有这个动作：$raw"))
            return
        }
        if (action.kind == "idle") {
            startIdle()
        } else if (action.kind == "move") {
            startRoaming(action)
        } else {
            stopRoaming()
            playAction(action, loop = false, autoIdle = true)
        }
    }

    private fun setMood(value: String) {
        if (value.isBlank()) return
        playNamedAction(value)
    }

    private fun startIdle() {
        stopRoaming()
        stopIdleTimer()
        val idle = idlePool.firstOrNull() ?: run {
            PetBridge.emit("error", mapOf("message" to "没有待机动画"))
            return
        }
        playAction(idle, loop = true, autoIdle = false)
        scheduleIdleAction()
    }

    private fun scheduleIdleAction() {
        stopIdleTimer()
        val runnable = Runnable { playRandomAction() }
        idleTimer = runnable
        handler.postDelayed(runnable, Random.nextLong(8000L, 18001L))
    }

    private fun stopIdleTimer() {
        idleTimer?.let { handler.removeCallbacks(it) }
        idleTimer = null
    }

    /// 待机时按权重掷一个：待机 / 转向 / 走路 / 点击回应 / 随机小动作。
    private fun playRandomAction() {
        if (!::root.isInitialized) return
        if (roamRunnable != null) return
        val kind = rollKind()
        when (kind) {
            "idle" -> {
                startIdle()
                return
            }
            "turn" -> {
                val action = turnPool.randomOrNull()
                if (action == null) {
                    pickCategoryAction()
                    return
                }
                playAction(action, loop = false, autoIdle = false) {
                    facingRight = !facingRight
                    applyFacing()
                    startIdle()
                }
            }
            "move" -> {
                val action = movePool.randomOrNull()
                if (action == null || !startRoaming(action)) pickCategoryAction()
            }
            "click" -> {
                val action = clickPool.randomOrNull()
                if (action == null) pickCategoryAction() else {
                    playAction(action, loop = false, autoIdle = true)
                }
            }
            else -> {
                // 分类动作 60 / 余额 5 / 工作状态 5 / 碎碎念 5
                when (randInt(0, 74)) {
                    in 0..59 -> pickCategoryAction()
                    in 60..64 -> pickEventAction("balance")
                    in 65..69 -> pickEventAction("workstatus")
                    else -> pickEventAction("whisper")
                }
            }
        }
    }

    private fun rollKind(): String {
        val weights = kindWeights
        val total = weights.values.sum().coerceAtLeast(1)
        var roll = Random.nextInt(total)
        for (key in listOf("idle", "turn", "move", "click", "category")) {
            roll -= (weights[key] ?: 0)
            if (roll < 0) return key
        }
        return "category"
    }

    /// 余额 / 碎碎念 / 工作状态这三类原本是事件动画。这里没有余额概念，
    /// 也不做工作状态监听，就让它们以低权重混进随机链——106 个动作
    /// 每一个都有机会出现，而不是有十几个永远抽不到。
    private fun pickEventAction(kind: String) {
        val pool = actions.filter { it.kind == kind }
        val action = pool.randomOrNull()
        if (action == null) {
            pickCategoryAction()
            return
        }
        if (facingRight) {
            facingRight = false
            applyFacing()
        }
        playAction(action, loop = false, autoIdle = true)
    }

    private fun pickCategoryAction() {
        val pool = actions.filter { it.kind == "category" }
        if (pool.isEmpty()) {
            startIdle()
            return
        }
        val grouped = pool.groupBy { it.category.orEmpty() }
        val candidates = grouped.keys.filter { (categoryWeights[it] ?: 0) > 0 }
        val category = if (candidates.isEmpty()) {
            grouped.keys.random()
        } else {
            val total = candidates.sumOf { categoryWeights[it] ?: 0 }
            var roll = Random.nextInt(total)
            var chosen = candidates.last()
            for (key in candidates) {
                roll -= (categoryWeights[key] ?: 0)
                if (roll < 0) {
                    chosen = key
                    break
                }
            }
            chosen
        }
        val direct = grouped[category].orEmpty()
        val options = direct.filter { it.key != currentAction?.key }.ifEmpty { direct }
        val action = options.randomOrNull() ?: pool.random()
        // 带文字的动作镜像会反字：朝右时先转回来（和原项目同一处理）。
        if (action.category == "文字" && facingRight) {
            facingRight = false
            applyFacing()
        }
        playAction(action, loop = false, autoIdle = true)
    }

    private fun playAction(
        action: PetAction,
        loop: Boolean,
        autoIdle: Boolean,
        after: (() -> Unit)? = null,
    ) {
        val drawable = loadAnimated(action) ?: return
        stopIdleTimer()
        currentAction = action
        val old = currentDrawable
        currentDrawable = drawable
        pet.setImageDrawable(drawable)
        if (old !== drawable) (old as? AnimationDrawable)?.stop()
        breathAnimator?.cancel()
        breathAnimator = null
        if (drawable is AnimationDrawable) {
            // 缓存的动图上次可能停在最后一帧，重新播要从头开始。
            drawable.selectDrawable(0)
            drawable.isOneShot = !loop
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
        applyFacing()
        PetBridge.emit("mood", mapOf("mood" to action.key))
        val token = ++actionToken
        if (!loop) {
            val duration = action.frames * frameMs + 80
            handler.postDelayed({
                if (actionToken != token) return@postDelayed
                if (after != null) after() else if (autoIdle) startIdle()
            }, duration)
        }
    }

    private fun applyFacing() {
        if (!::pet.isInitialized) return
        pet.scaleX = if (facingRight) -1f else 1f
    }

    private fun loadAnimated(action: PetAction): AnimationDrawable? {
        animationCache[action.key]?.let { return it }
        val animation = AnimationDrawable()
        for (index in 0 until action.frames) {
            val name = String.format(Locale.US, "%s_%02d.webp", action.key, index)
            try {
                assets.open("flutter_assets/assets/pet_frames/$name").use { stream ->
                    val bitmap = BitmapFactory.decodeStream(stream)
                    if (bitmap != null) {
                        animation.addFrame(BitmapDrawable(resources, bitmap), frameMs.toInt())
                    }
                }
            } catch (_: Throwable) {
            }
        }
        if (animation.numberOfFrames == 0) {
            PetBridge.emit("error", mapOf("message" to "桌宠素材没找到：${action.key}"))
            return null
        }
        animationCache[action.key] = animation
        while (animationCache.size > 3) {
            val oldest = animationCache.keys.first()
            animationCache.remove(oldest)?.stop()
        }
        return animation
    }

    // ---------------------------------------------------------------- 漫游

    private var roamRunnable: Runnable? = null
    private var roamToken = 0

    /// 播一个走行动画并真的把窗口挪过去。算不出落点（贴边/取消）返回 false。
    private fun startRoaming(action: PetAction): Boolean {
        val spec = action.move ?: return false
        val p = params ?: return false
        if (!::root.isInitialized) return false
        stopRoaming()
        val (screenW, _) = displaySize()
        val dist = dp(randInt(spec.minDp, spec.maxDp))
        // 朝哪边就走哪边——和原项目一样，方向由朝向决定（转向动画才翻朝向）。
        val dir = if (facingRight) 1 else -1
        // 走路时要求整只桌宠留在屏幕里（v4.2.8 起窗口就是本体）。
        // 拖拽仍然允许半贴边。
        val margin = dp(8)
        val minX = margin
        val maxX = (screenW - p.width - margin).coerceAtLeast(minX)
        val target = (p.x + dir * dist).coerceIn(minX, maxX)
        val startX = p.x
        if (abs(target - startX) < dp(12)) return false

        playAction(action, loop = false, autoIdle = false)

        val token = ++roamToken
        val total = (action.frames * frameMs).coerceAtLeast(1L)
        val lead = (total * spec.lead).toLong()
        val tail = (total * spec.tail).toLong()
        val travel = (total - lead - tail).coerceAtLeast(1L)
        val startAt = SystemClock.uptimeMillis()

        val runnable = object : Runnable {
            override fun run() {
                if (roamToken != token) return
                val elapsed = SystemClock.uptimeMillis() - startAt
                val progress = when {
                    elapsed <= lead -> 0f
                    elapsed >= lead + travel -> 1f
                    else -> (elapsed - lead).toFloat() / travel
                }
                p.x = (startX + (target - startX) * progress).toInt()
                try {
                    windowManager.updateViewLayout(root, p)
                } catch (_: Throwable) {
                }
                updateHitPosition()
                syncBubblePosition()
                if (elapsed < total) {
                    handler.postDelayed(this, 16)
                } else {
                    p.x = target
                    try {
                        windowManager.updateViewLayout(root, p)
                    } catch (_: Throwable) {
                    }
                    updateHitPosition()
                    getSharedPreferences("echo_pet", MODE_PRIVATE)
                        .edit().putInt("x", p.x).putInt("y", p.y).apply()
                    PetBridge.emit("dropped", mapOf("x" to p.x, "y" to p.y))
                    roamRunnable = null
                    startIdle()
                }
            }
        }
        roamRunnable = runnable
        handler.postDelayed(runnable, 16)
        return true
    }

    private fun stopRoaming() {
        roamToken++
        roamRunnable?.let { handler.removeCallbacks(it) }
        roamRunnable = null
    }

    // ---------------------------------------------------------------- 气泡

    private fun showBubble(text: String, requestId: String = "") {
        val clean = text.trim()
        if (clean.isEmpty() || !::bubble.isInitialized) return
        val lp = bubbleParams ?: return

        try {
            bubbleFullText = clean.take(120)
            bubble.text = bubbleFullText
            bubble.measure(
                View.MeasureSpec.makeMeasureSpec(
                    dp(bubbleMaxWidthDp),
                    View.MeasureSpec.AT_MOST,
                ),
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
            if (currentAction != null && currentAction == byExpose["sleep"]) {
                // 睡着时被气泡叫醒：换成开心的点击回应。
                byExpose["happy"]?.let { playAction(it, loop = false, autoIdle = true) }
            }
            PetBridge.emit(
                "bubble",
                mapOf(
                    "ok" to true,
                    "text" to clean,
                    "requestId" to requestId,
                ),
            )
        } catch (error: Throwable) {
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
    /// 叠在舞台里角色身上，垂直对齐裙子上的小鲸鱼那一块。
    private fun syncBubblePosition() {
        if (!::bubble.isInitialized) return
        val p = params ?: return
        val lp = bubbleParams ?: return
        val dm = resources.displayMetrics
        val w = lp.width.takeIf { it > 0 } ?: dp(160)
        val h = lp.height.takeIf { it > 0 } ?: dp(36)
        lp.x = p.x + (p.width - w) / 2
        lp.y = p.y + (p.height * 0.70f).toInt() - h / 2
        lp.x = lp.x.coerceIn(0, (dm.widthPixels - w).coerceAtLeast(0))
        lp.y = lp.y.coerceIn(0, (dm.heightPixels - h).coerceAtLeast(0))
        if (bubbleAdded) {
            try {
                windowManager.updateViewLayout(bubble, lp)
            } catch (_: Throwable) {
            }
        }
    }

    private val hideBubble = Runnable {
        bubbleVisible = false
        handler.removeCallbacks(bubbleTyper)
        if (::bubble.isInitialized) bubble.visibility = View.GONE
    }

    // ---------------------------------------------------------------- 前台服务

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
        stopRoaming()
        stopIdleTimer()
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
        if (hitAdded && ::hit.isInitialized) {
            try {
                windowManager.removeView(hit)
            } catch (_: Throwable) {
            }
            hitAdded = false
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
        stopRoaming()
        stopIdleTimer()
        handler.removeCallbacksAndMessages(null)
        if (::displayManager.isInitialized) {
            try {
                displayManager.unregisterDisplayListener(displayListener)
            } catch (_: Throwable) {
            }
        }
        if (bubbleAdded && ::bubble.isInitialized) {
            try {
                windowManager.removeView(bubble)
            } catch (_: Throwable) {
            }
        }
        if (hitAdded && ::hit.isInitialized) {
            try {
                windowManager.removeView(hit)
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
