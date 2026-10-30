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

  /// 立刻截一张，并等它真的落盘。
  ///
  /// `captureOnce` 只负责把 Intent 丢给服务，截没截到、什么时候截到都不知道。
  /// 实时观察要“通信前 0.5 秒补一张”，住民要“自己现在看一眼”，
  /// 都必须在拿到这张图之后才能继续，所以这里等原生回一个带 requestId 的帧。
  Future<CapturedFrame?> captureNow({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final requestId = 'cap_${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<CapturedFrame?>();
    late StreamSubscription<Map<String, Object?>> subscription;
    subscription = events.listen((event) {
      if (event['requestId'] != requestId) return;
      if (event['event'] == 'captureError') {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      if (event['event'] != 'frame') return;
      final path = event['path'];
      if (path is! String || path.isEmpty) return;
      final at = event['at'] is int
          ? DateTime.fromMillisecondsSinceEpoch(event['at'] as int)
          : DateTime.now();
      if (!completer.isCompleted) {
        completer.complete(CapturedFrame(path: path, at: at));
      }
    });
    final accepted = await _invoke<bool>('captureOnce', {'requestId': requestId});
    if (accepted != true && !completer.isCompleted) completer.complete(null);
    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
    } finally {
      await subscription.cancel();
    }
  }

  /// 系统有没有把本应用放进“电池优化白名单”。
  ///
  /// 国产 ROM 还会另有自己的自启动/后台管理，那个系统没有统一接口，
  /// 只能在页面上给一个跳应用详情的入口。
  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _invoke<bool>('isIgnoringBatteryOptimizations') ?? false;

  Future<void> requestIgnoreBatteryOptimizations() =>
      _invoke<bool>('requestIgnoreBatteryOptimizations');

  Future<void> openAppSettings() => _invoke<bool>('openAppSettings');

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

/// 一张已经落盘的屏幕截图。
class CapturedFrame {
  const CapturedFrame({required this.path, required this.at});

  final String path;
  final DateTime at;
}

final petNativeProvider = Provider<PetNative>((ref) {
  final native = PetNative();
  ref.onDispose(native.dispose);
  return native;
});
