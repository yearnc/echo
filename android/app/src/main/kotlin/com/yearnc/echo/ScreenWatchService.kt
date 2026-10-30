package com.yearnc.echo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max

/**
 * 屏幕观察（v4.0）。
 *
 * 只有用户明确点过系统授权框之后才会启动。两种节奏：
 * - 实时模式：每 0.5 / 1 秒抓一帧，交给 Dart 侧最近窗口；
 * - 普通模式：Dart 每次 `captureOnce` 才抓一张。
 *
 * 图片落在 cacheDir/pet/，由 Dart 决定什么时候删。锁屏时不抓——
 * 那时候屏幕上是通知和密码键盘，不该被“看见”。
 */
class ScreenWatchService : Service() {
    companion object {
        const val ACTION_START = "com.yearnc.echo.watch.START"
        const val ACTION_STOP = "com.yearnc.echo.watch.STOP"
        const val ACTION_CAPTURE = "com.yearnc.echo.watch.CAPTURE"
        const val ACTION_INTERVAL = "com.yearnc.echo.watch.INTERVAL"
        const val ACTION_CONTINUOUS = "com.yearnc.echo.watch.CONTINUOUS"

        const val EXTRA_CODE = "code"
        const val EXTRA_DATA = "data"
        const val EXTRA_INTERVAL = "interval"
        const val EXTRA_CONTINUOUS = "continuous"
        const val EXTRA_REQUEST_ID = "requestId"

        private const val CHANNEL_ID = "echo_screen_watch"
        private const val NOTIFICATION_ID = 4402
        private var pendingCode = 0
        private var pendingData: Intent? = null

        @Volatile
        var running: Boolean = false
            private set

        fun rememberPermission(code: Int, data: Intent) {
            pendingCode = code
            pendingData = data
        }

        fun start(context: Context, intervalMs: Int, continuous: Boolean) {
            val intent = Intent(context, ScreenWatchService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_CODE, pendingCode)
                .putExtra(EXTRA_INTERVAL, intervalMs)
                .putExtra(EXTRA_CONTINUOUS, continuous)
            pendingData?.let { intent.putExtra(EXTRA_DATA, it) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, ScreenWatchService::class.java).setAction(ACTION_STOP)
            )
        }

        fun captureOnce(context: Context, requestId: String = "") {
            context.startService(
                Intent(context, ScreenWatchService::class.java)
                    .setAction(ACTION_CAPTURE)
                    .putExtra(EXTRA_REQUEST_ID, requestId)
            )
        }

        fun setInterval(context: Context, intervalMs: Int) {
            context.startService(
                Intent(context, ScreenWatchService::class.java)
                    .setAction(ACTION_INTERVAL)
                    .putExtra(EXTRA_INTERVAL, intervalMs)
            )
        }

        fun setContinuous(context: Context, continuous: Boolean) {
            context.startService(
                Intent(context, ScreenWatchService::class.java)
                    .setAction(ACTION_CONTINUOUS)
                    .putExtra(EXTRA_CONTINUOUS, continuous)
            )
        }
    }

    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var intervalMs = 1000L
    private var continuous = false
    private var started = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                shutdown()
                return START_NOT_STICKY
            }
            ACTION_CAPTURE -> {
                val requestId = intent.getStringExtra(EXTRA_REQUEST_ID).orEmpty()
                if (!started) {
                    // 服务可能被系统回收过：没有授权不能自己重建投影，
                    // 只能让 Dart 侧提示用户重新开一次桌宠。
                    PetBridge.emit(
                        "captureError",
                        mapOf(
                            "message" to "没有屏幕授权，重新打开桌宠试一次",
                            "requestId" to requestId,
                        ),
                    )
                    return START_STICKY
                }
                grabOnce(requestId)
            }
            ACTION_INTERVAL -> {
                intervalMs = (intent.getIntExtra(EXTRA_INTERVAL, 1000)).toLong()
                    .coerceIn(400L, 60000L)
                if (continuous) scheduleNext()
            }
            ACTION_CONTINUOUS -> {
                continuous = intent.getBooleanExtra(EXTRA_CONTINUOUS, false)
                if (continuous) scheduleNext() else handler?.removeCallbacks(loop)
            }
            else -> {
                intervalMs = (intent?.getIntExtra(EXTRA_INTERVAL, 1000) ?: 1000).toLong()
                    .coerceIn(400L, 60000L)
                continuous = intent?.getBooleanExtra(EXTRA_CONTINUOUS, false) ?: false
                // startForegroundService 起跑后必须在几秒内 startForeground，
                // 否则系统会直接判 ANR。先挂通知，再去看授权在不在。
                startForegroundNow()
                startProjection(intent)
            }
        }
        return START_STICKY
    }

    private fun startProjection(intent: Intent?) {
        if (started) {
            // 服务已经在跑：普通模式切实时（或反过来）时，这里必须
            // 真的应用新的 interval/continuous，不能直接 return。
            if (continuous) scheduleNext() else handler?.removeCallbacks(loop)
            return
        }
        val code = intent?.getIntExtra(EXTRA_CODE, 0) ?: 0
        val data = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra(EXTRA_DATA) as? Intent
        }
        if (code == 0 || data == null) {
            PetBridge.emit("captureError", mapOf("message" to "还没有拿到屏幕授权"))
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        val manager = getSystemService(
            Context.MEDIA_PROJECTION_SERVICE
        ) as MediaProjectionManager
        val mediaProjection = manager.getMediaProjection(code, data)
        if (mediaProjection == null) {
            PetBridge.emit("captureError", mapOf("message" to "系统没有给出屏幕授权"))
            return
        }
        projection = mediaProjection
        mediaProjection.registerCallback(
            object : MediaProjection.Callback() {
                override fun onStop() {
                    shutdown()
                }
            },
            Handler(mainLooper),
        )

        val metrics = resources.displayMetrics
        val width = metrics.widthPixels
        val height = metrics.heightPixels
        imageReader = ImageReader.newInstance(
            width,
            height,
            PixelFormat.RGBA_8888,
            2,
        )
        thread = HandlerThread("echo-screen-watch").also { it.start() }
        handler = Handler(thread!!.looper)
        virtualDisplay = mediaProjection.createVirtualDisplay(
            "echo-screen-watch",
            width,
            height,
            metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface,
            null,
            handler,
        )
        started = true
        running = true
        PetBridge.emit("captureStarted", mapOf("width" to width, "height" to height))
        if (continuous) scheduleNext()
    }

    private val loop = object : Runnable {
        override fun run() {
            // 主 isolate 没了（进程被换掉 / Activity 销毁）就别再默默截屏了：
            // 没有人接收的截图既没有意义，也不该继续留在磁盘上。
            if (PetBridge.channel == null) {
                shutdown()
                return
            }
            grabOnce()
            if (continuous) handler?.postDelayed(this, intervalMs)
        }
    }

    private fun scheduleNext() {
        handler?.removeCallbacks(loop)
        handler?.postDelayed(loop, intervalMs)
    }

    private fun grabOnce(requestId: String = "") {
        val reader = imageReader ?: return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!power.isInteractive) {
            if (requestId.isNotEmpty()) {
                PetBridge.emit(
                    "captureError",
                    mapOf("message" to "锁屏时不截取屏幕", "requestId" to requestId),
                )
            }
            return
        }

        val image = try {
            reader.acquireLatestImage()
        } catch (_: Throwable) {
            null
        }
        if (image == null) {
            if (requestId.isNotEmpty()) {
                PetBridge.emit(
                    "captureError",
                    mapOf("message" to "这一拍没有画面，稍后再试", "requestId" to requestId),
                )
            }
            return
        }
        try {
            val plane = image.planes[0]
            val pixelStride = plane.pixelStride
            val rowStride = plane.rowStride
            val width = image.width
            val height = image.height
            val rowPadding = rowStride - pixelStride * width
            val raw = Bitmap.createBitmap(
                width + rowPadding / pixelStride,
                height,
                Bitmap.Config.ARGB_8888,
            )
            raw.copyPixelsFromBuffer(plane.buffer)
            val cropped = Bitmap.createBitmap(raw, 0, 0, width, height)
            raw.recycle()

            // 截图给模型看，最长边 720 足够：再大只是多花 token。
            val scale = 720f / max(cropped.width, cropped.height)
            val scaled = if (scale < 1f) {
                Bitmap.createScaledBitmap(
                    cropped,
                    (cropped.width * scale).toInt(),
                    (cropped.height * scale).toInt(),
                    true,
                )
            } else {
                cropped
            }
            if (scaled !== cropped) cropped.recycle()

            val folder = File(cacheDir, "pet").apply { mkdirs() }
            val stamp = System.currentTimeMillis()
            val file = File(folder, "frame_$stamp.jpg")
            FileOutputStream(file).use {
                scaled.compress(Bitmap.CompressFormat.JPEG, 72, it)
            }
            scaled.recycle()
            PetBridge.emit(
                "frame",
                mapOf(
                    "path" to file.absolutePath,
                    "at" to stamp,
                    "width" to image.width,
                    "height" to image.height,
                    "requestId" to requestId,
                ),
            )
        } catch (error: Throwable) {
            PetBridge.emit(
                "captureError",
                mapOf(
                    "message" to (error.message ?: "截图失败"),
                    "requestId" to requestId,
                ),
            )
        } finally {
            image.close()
        }
    }

    private fun startForegroundNow() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun shutdown() {
        handler?.removeCallbacksAndMessages(null)
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        projection?.stop()
        projection = null
        thread?.quitSafely()
        thread = null
        handler = null
        started = false
        running = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        PetBridge.emit("captureStopped")
    }

    override fun onDestroy() {
        handler?.removeCallbacksAndMessages(null)
        try {
            virtualDisplay?.release()
            imageReader?.close()
            thread?.quitSafely()
        } catch (_: Throwable) {
        }
        running = false
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "屏幕观察",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "桌宠开启实时观察时，屏幕截取会在这里常驻提示"
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
            .setContentTitle("正在观察屏幕")
            .setContentText("只在你允许的这段时间内截取，随时可以停")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }
}
