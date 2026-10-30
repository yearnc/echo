package com.yearnc.echo

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 桌宠与屏幕观察的原生入口（v4.0）。
 *
 * 悬浮窗本身住在两个前台服务里；Activity 只负责三件事：
 * 1. 检查 / 跳转“显示在其他应用上层”授权；
 * 2. 拉起系统屏幕截取授权框（MediaProjection 每次会话都必须用户点一次）；
 * 3. 把 Dart 的指令转给服务，并把服务的事件经 PetBridge 送回 Dart。
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "echo/pet"
        private const val REQUEST_CAPTURE = 4403
    }

    private var pendingCapture: MethodChannel.Result? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        PetBridge.channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasOverlayPermission" ->
                    result.success(Settings.canDrawOverlays(this))
                "requestOverlayPermission" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"),
                        )
                    )
                    result.success(true)
                }
                "startPet" -> {
                    PetOverlayService.start(this)
                    result.success(true)
                }
                "stopPet" -> {
                    PetOverlayService.stop(this)
                    ScreenWatchService.stop(this)
                    result.success(true)
                }
                "isPetRunning" -> result.success(PetOverlayService.running)
                "say" -> {
                    // 没有悬浮窗权限时气泡一定显示不了；把结果说清楚，
                    // 别让日志里出现“冒气泡”但屏幕上一片空白。
                    val canShow = Settings.canDrawOverlays(this)
                    PetOverlayService.say(
                        this,
                        call.argument<String>("text").orEmpty(),
                        call.argument<String>("requestId").orEmpty(),
                    )
                    result.success(canShow)
                }
                "react" -> {
                    PetOverlayService.react(
                        this,
                        call.argument<String>("action").orEmpty(),
                    )
                    result.success(true)
                }
                "mood" -> {
                    PetOverlayService.setMood(
                        this,
                        call.argument<String>("mood").orEmpty(),
                    )
                    result.success(true)
                }
                "requestScreenCapture" -> requestCapture(result)
                "startWatch" -> {
                    val interval = call.argument<Int>("interval") ?: 1000
                    val continuous = call.argument<Boolean>("continuous") ?: false
                    ScreenWatchService.start(this, interval, continuous)
                    result.success(true)
                }
                "stopWatch" -> {
                    ScreenWatchService.stop(this)
                    result.success(true)
                }
                "captureOnce" -> {
                    ScreenWatchService.captureOnce(
                        this,
                        call.argument<String>("requestId").orEmpty(),
                    )
                    result.success(true)
                }
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }
                "openAppSettings" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"),
                        )
                    )
                    result.success(true)
                }
                "setWatchInterval" -> {
                    ScreenWatchService.setInterval(
                        this,
                        call.argument<Int>("interval") ?: 1000,
                    )
                    result.success(true)
                }
                "setContinuous" -> {
                    ScreenWatchService.setContinuous(
                        this,
                        call.argument<Boolean>("continuous") ?: false,
                    )
                    result.success(true)
                }
                "isWatchRunning" -> result.success(ScreenWatchService.running)
                else -> result.notImplemented()
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val power = getSystemService(POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    /**
     * 申请“不受电池优化限制”。
     *
     * 原生接口在国产 ROM 上不一定弹得出来（有的会跳自家的后台管理）；
     * 跳不过去就退到“电池优化设置列表”，让用户自己找一下本应用。
     */
    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (isIgnoringBatteryOptimizations()) return
        val direct = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName"),
        )
        try {
            startActivity(direct)
            return
        } catch (_: Throwable) {
            // 继续试下面的系统列表。
        }
        try {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        } catch (_: Throwable) {
            // 最后退到应用详情页：至少让用户能看到“耗电管理”。
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                )
            )
        }
    }

    private fun requestCapture(result: MethodChannel.Result) {
        if (pendingCapture != null) {
            result.error("busy", "上一次屏幕授权还没结束", null)
            return
        }
        pendingCapture = result
        val manager = getSystemService(
            MEDIA_PROJECTION_SERVICE
        ) as MediaProjectionManager
        startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_CAPTURE)
    }

    override fun onDestroy() {
        // engine 要没了：把桥清掉，截屏服务下一拍就会自己停，
        // 不会继续往一个已经销毁的 channel 里发帧。
        if (PetBridge.channel === channel) {
            PetBridge.channel = null
        }
        channel = null
        super.onDestroy()
    }

    @Deprecated("FlutterActivity 仍走 onActivityResult")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CAPTURE) return
        val result = pendingCapture
        pendingCapture = null
        if (resultCode == Activity.RESULT_OK && data != null) {
            ScreenWatchService.rememberPermission(resultCode, data)
            result?.success(true)
        } else {
            result?.success(false)
        }
    }
}
