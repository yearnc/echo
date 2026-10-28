package com.yearnc.echo

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * 原生桌宠 → Dart 的单向事件桥。
 *
 * 桌宠住在 WindowManager 里，不在 Flutter 页面里；它被戳、被拖动、
 * 或者截到一帧画面时，只能靠这条 channel 把消息送回 Dart 主 isolate。
 * 主 isolate 不在（进程已退）时静默丢弃——桌宠服务活着但没人处理，
 * 比抛异常把服务带崩要好。
 */
object PetBridge {
    private val main = Handler(Looper.getMainLooper())
    @Volatile
    var channel: MethodChannel? = null

    fun emit(event: String, payload: Map<String, Any?> = emptyMap()) {
        main.post {
            val ch = channel ?: return@post
            try {
                ch.invokeMethod(
                    "petEvent",
                    mapOf("event" to event) + payload,
                )
            } catch (_: Throwable) {
                // Dart 主 isolate 已经没了（Activity 销毁/进程切换）：
                // 丢掉这一帧，别把服务或主线程带崩。
            }
        }
    }
}
