import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dart ↔ Android 桌宠服务的薄桥（v4.0）。
///
/// 悬浮窗、截屏、拖拽都在原生侧；这里只转发指令和事件。
/// 桌面预览 / 测试里没有这个 plugin，所有调用都安静地返回 false，
/// 不会因为“桌宠在 Windows 上不存在”把主流程弄崩。
class PetNative {
  PetNative() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const MethodChannel _channel = MethodChannel('echo/pet');
  final StreamController<Map<String, Object?>> _events =
      StreamController<Map<String, Object?>>.broadcast();

  Stream<Map<String, Object?>> get events => _events.stream;

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'petEvent') return;
    final args = call.arguments;
    if (args is Map) {
      _events.add({
        for (final entry in args.entries)
          if (entry.key is String) entry.key as String: entry.value,
      });
    }
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      debugPrint('[桌宠] $method 失败：${error.message}');
      return null;
    }
  }

  Future<bool> hasOverlayPermission() async =>
      await _invoke<bool>('hasOverlayPermission') ?? false;

  Future<void> requestOverlayPermission() =>
      _invoke<bool>('requestOverlayPermission');

  Future<bool> startPet() async => await _invoke<bool>('startPet') ?? false;

  Future<void> stopPet() => _invoke<bool>('stopPet');

  Future<bool> isPetRunning() async =>
      await _invoke<bool>('isPetRunning') ?? false;

  /// 说一句气泡，并等原生确认窗口真的搭上了。
  ///
  /// 以前 `say` 只是把 Intent 丢给服务，服务失败时 Dart 仍以为成功，
  /// 日志里就出现“冒气泡成功、屏幕上什么都没有”。现在服务显示成功后
  /// 会带 requestId 回一个 bubble 事件，3 秒内没等到就算失败。
  Future<bool> say(String text) async {
    final requestId = 'say_${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<bool>();
    late StreamSubscription<Map<String, Object?>> subscription;
    subscription = events.listen((event) {
      if (event['event'] != 'bubble') return;
      if (event['requestId'] != requestId) return;
      if (!completer.isCompleted) completer.complete(event['ok'] == true);
    });
    final canShow = await _invoke<bool>('say', {
          'text': text,
          'requestId': requestId,
        }) ??
        false;
    if (!canShow && !completer.isCompleted) completer.complete(false);
    try {
      return await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> react(String action) =>
      _invoke<bool>('react', {'action': action});

  Future<void> mood(String mood) =>
      _invoke<bool>('mood', {'mood': mood});

  /// 拉起系统截屏授权框。每次 MediaProjection 会话都要用户点一次。
  Future<bool> requestScreenCapture() async =>
      await _invoke<bool>('requestScreenCapture') ?? false;

  Future<void> startWatch({
    required int intervalMs,
    required bool continuous,
  }) => _invoke<bool>('startWatch', {
    'interval': intervalMs,
    'continuous': continuous,
  });

  Future<void> stopWatch() => _invoke<bool>('stopWatch');

  Future<void> captureOnce() => _invoke<bool>('captureOnce');

  Future<void> setWatchInterval(int intervalMs) =>
      _invoke<bool>('setWatchInterval', {'interval': intervalMs});

  Future<void> setContinuous(bool continuous) =>
      _invoke<bool>('setContinuous', {'continuous': continuous});

  Future<bool> isWatchRunning() async =>
      await _invoke<bool>('isWatchRunning') ?? false;

  void dispose() {
    _channel.setMethodCallHandler(null);
    _events.close();
  }
}

final petNativeProvider = Provider<PetNative>((ref) {
  final native = PetNative();
  ref.onDispose(native.dispose);
  return native;
});
