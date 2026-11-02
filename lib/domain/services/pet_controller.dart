import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/pet_settings_repository.dart';
import '../../data/repositories/resident_wake_log_repository.dart';
import 'call_registry.dart';
import 'pet_native.dart';
import 'pet_observe_service.dart';
import 'resident_sleep_service.dart';
import 'resident_wake_service.dart';

class PetRuntimeState {
  const PetRuntimeState({
    this.busy = false,
    this.enabled = false,
    this.overlayGranted = false,
    this.captureRunning = false,
    this.realtime = false,
    this.realtimeFrames = 3,
    this.realtimeGapSeconds = 20,
    this.intervalMs = 1000,
    this.defaultResidentId = '',
    this.controllerId,
    this.error = '',
  });

  final bool busy;
  final bool enabled;
  final bool overlayGranted;
  final bool captureRunning;
  final bool realtime;
  final int realtimeFrames;
  final int realtimeGapSeconds;
  final int intervalMs;
  final String defaultResidentId;
  final String? controllerId;
  final String error;

  PetRuntimeState copyWith({
    bool? busy,
    bool? enabled,
    bool? overlayGranted,
    bool? captureRunning,
    bool? realtime,
    int? realtimeFrames,
    int? realtimeGapSeconds,
    int? intervalMs,
    String? defaultResidentId,
    String? controllerId,
    bool clearController = false,
    String? error,
  }) => PetRuntimeState(
    busy: busy ?? this.busy,
    enabled: enabled ?? this.enabled,
    overlayGranted: overlayGranted ?? this.overlayGranted,
    captureRunning: captureRunning ?? this.captureRunning,
    realtime: realtime ?? this.realtime,
    realtimeFrames: realtimeFrames ?? this.realtimeFrames,
    realtimeGapSeconds: realtimeGapSeconds ?? this.realtimeGapSeconds,
    intervalMs: intervalMs ?? this.intervalMs,
    defaultResidentId: defaultResidentId ?? this.defaultResidentId,
    controllerId: clearController ? null : (controllerId ?? this.controllerId),
    error: error ?? this.error,
  );
}

class PetActionResult {
  const PetActionResult(this.ok, this.message);

  final bool ok;
  final String message;
}

/// 桌宠的开关与实时模式（v4.0）。
///
/// 权限、前台服务、授权框都在这里串起来；观察循环交给
/// [PetObserveService]。UI 只需要调 [enable] / [disable] / [setRealtime]。
class PetController extends Notifier<PetRuntimeState> {
  @override
  PetRuntimeState build() => const PetRuntimeState();

  PetNative get _native => ref.read(petNativeProvider);
  PetSettingsRepository get _settings =>
      ref.read(petSettingsRepositoryProvider);
  PetObserveService get _observe => ref.read(petObserveServiceProvider);

  Future<void> refresh() async {
    final value = await _settings.load();
    final overlay = await _native.hasOverlayPermission();
    final running = await _native.isPetRunning();
    final watching = await _native.isWatchRunning();
    // 桌宠服务已经不在（系统回收 / 崩过）时，实时观察不可能还在跑：
    // 把落盘的开关收回 false，别让页面显示“实时开启、实际没人看”。
    if (!running) {
      if (value.realtime) {
        await _settings.setRealtime(false);
      }
      await ref.read(residentWakeLogRepositoryProvider).finishAllPetLogs();
    }
    final effectiveRealtime = value.realtime && running;
    final controller = await _settings.controllerAt(
      DateTime.now(),
      fallbackResidentId: value.defaultResidentId,
    );
    // 正在通话的住民暂时不接管桌宠：这里也跟着显示“没人”，
    // 免得页面上说“由 TA 控制”，实际观察却让给了通话。
    final delayed = controller != null && CallRegistry.isActive(controller);
    state = PetRuntimeState(
      enabled: value.enabled && running,
      overlayGranted: overlay,
      captureRunning: watching,
      realtime: effectiveRealtime,
      realtimeFrames: value.realtimeFrames,
      realtimeGapSeconds: value.realtimeGapSeconds,
      intervalMs: value.intervalMs,
      defaultResidentId: value.defaultResidentId,
      controllerId: delayed ? null : controller,
    );
    if (value.enabled && running) {
      _observe.attach();
      await _observe.sync(value.copyWith(realtime: effectiveRealtime));
    }
  }

  /// 打开桌宠。悬浮窗权限要先有；屏幕授权用户拒绝时仍然显示，
  /// 但普通/实时观察都不会有画面——UI 会把这一点说清楚。
  Future<PetActionResult> enable() async {
    if (state.busy) return const PetActionResult(false, '正在处理');
    state = state.copyWith(busy: true, error: '');
    try {
      if (!await _native.hasOverlayPermission()) {
        await _native.requestOverlayPermission();
        state = state.copyWith(busy: false);
        return const PetActionResult(false, '先去系统设置里允许“显示在其他应用上层”，回来再点开启');
      }

      final value = await _settings.load();
      final captured = await _native.requestScreenCapture();
      await _native.startPet();
      if (captured) {
        await _native.startWatch(
          intervalMs: value.captureIntervalMs,
          continuous: value.realtime,
        );
      }
      await _settings.setEnabled(true);
      _observe.attach();
      await _observe.sync(value.copyWith(enabled: true));
      await refresh();
      unawaited(_wakeControllerIfSleeping());
      return PetActionResult(true, captured ? '桌宠出来啦' : '桌宠已经显示；但没有屏幕授权，看不到画面');
    } catch (error) {
      debugPrint('[桌宠] 开启失败：$error');
      state = state.copyWith(busy: false, error: '$error');
      return PetActionResult(false, '没开起来：$error');
    }
  }

  /// 小游戏专用：只把桌宠显示出来，不申请屏幕录制、不启动观察。
  ///
  /// 对局里住民只借它冒气泡，不需要看屏幕；退出对局时页面会调 [disable]。
  /// 没有悬浮窗权限就安静地返回失败，不把系统授权框硬塞给用户。
  Future<PetActionResult> enableForGame() async {
    if (state.busy) return const PetActionResult(false, '正在处理');
    try {
      if (!await _native.hasOverlayPermission()) {
        return const PetActionResult(false, '还没有悬浮窗权限');
      }
      final started = await _native.startPet();
      if (!started) return const PetActionResult(false, '桌宠没起来');
      await _settings.setEnabled(true);
      state = state.copyWith(enabled: true);
      return const PetActionResult(true, '桌宠出来啦');
    } catch (error) {
      debugPrint('[桌宠] 对局里开启失败：$error');
      return PetActionResult(false, '没开起来：$error');
    }
  }

  /// 用户亲手打开桌宠 = 主动找控制者。
  ///
  /// 如果 TA 正在睡，结束睡眠并叫醒它；自动对局开的桌宠不走这里。
  Future<void> _wakeControllerIfSleeping() async {
    final id = state.controllerId;
    if (id == null || id.isEmpty) return;
    try {
      final notice = await ref
          .read(residentSleepServiceProvider)
          .prepareInteraction(id);
      if (notice == null) return;
      unawaited(
        ref
            .read(residentWakeServiceProvider)
            .wake(id, trigger: WakeTrigger.userAction, sleepNotice: notice),
      );
    } catch (error) {
      debugPrint('[桌宠] 唤醒控制者失败：$error');
    }
  }

  /// 关掉桌宠。实时模式先总结、写记忆成功后才清截图。
  Future<PetActionResult> disable() async {
    if (state.busy) return const PetActionResult(false, '正在处理');
    state = state.copyWith(busy: true, error: '');
    try {
      if (state.realtime) {
        final result = await _observe.finishRealtime();
        if (!result.ok) {
          state = state.copyWith(busy: false);
          return PetActionResult(false, result.error);
        }
        await _settings.setRealtime(false);
      }
      // 先把原生窗口/截屏停掉，再清本地日志；清理失败也不能把桌宠
      // 留在屏幕上。
      await _native.stopWatch();
      await _native.stopPet();
      await _settings.setEnabled(false);
      try {
        await _observe.purge();
      } catch (error) {
        debugPrint('[桌宠] 关闭时清理日志失败：$error');
      }
      await refresh();
      return const PetActionResult(true, '桌宠回去休息了');
    } catch (error) {
      debugPrint('[桌宠] 关闭失败：$error');
      state = state.copyWith(busy: false, error: '$error');
      return PetActionResult(false, '没停下来：$error');
    }
  }

  /// 对局页专用的强制收尾：不管 busy/实时总结，先把原生桌宠停掉。
  ///
  /// 自动开出来的桌宠必须在离开棋盘时消失；清理记忆/日志失败可以晚点补，
  /// 但不能因为 `purge()` 抛错或 `finishRealtime()` 失败就把它留在屏幕上。
  Future<PetActionResult> forceDisableForGame() async {
    state = state.copyWith(busy: true, error: '');
    try {
      await _native.stopWatch();
      await _native.stopPet();
      await _settings.setEnabled(false);
      await _settings.setRealtime(false);
      try {
        await _observe.purge();
      } catch (error) {
        debugPrint('[桌宠] 对局收尾清理没做完：$error');
      }
      state = state.copyWith(
        busy: false,
        enabled: false,
        realtime: false,
        captureRunning: false,
        clearController: true,
      );
      return const PetActionResult(true, '桌宠回去休息了');
    } catch (error) {
      debugPrint('[桌宠] 对局收尾失败：$error');
      state = state.copyWith(busy: false, error: '$error');
      return PetActionResult(false, '没停下来：$error');
    }
  }

  /// 开 / 关实时模式。开启前 UI 必须已经得到用户对 token 成本的确认。
  Future<PetActionResult> setRealtime(bool value) async {
    if (state.busy) return const PetActionResult(false, '正在处理');
    state = state.copyWith(busy: true, error: '');
    try {
      if (!value) {
        // 关闭：先总结，写成功才真的停连续抓图并清图。
        final result = await _observe.finishRealtime();
        if (!result.ok) {
          state = state.copyWith(busy: false);
          return PetActionResult(false, result.error);
        }
        await _native.setContinuous(false);
        await _settings.setRealtime(false);
        await refresh();
        return const PetActionResult(true, '实时观察已停，这段时间的观察写成记忆了');
      }

      if (!state.enabled) {
        state = state.copyWith(busy: false);
        return const PetActionResult(false, '先把桌宠打开');
      }
      if (!state.captureRunning) {
        final ok = await _native.requestScreenCapture();
        if (!ok) {
          state = state.copyWith(busy: false);
          return const PetActionResult(false, '没有屏幕授权，开不了实时观察');
        }
        await _native.startWatch(
          intervalMs: (await _settings.load()).captureIntervalMs,
          continuous: true,
        );
      } else {
        await _native.setContinuous(true);
      }
      await _settings.setRealtime(true);
      await _observe.sync((await _settings.load()).copyWith(realtime: true));
      await refresh();
      return const PetActionResult(true, '实时观察开了。它会持续看屏幕并反复醒来，token 消耗会比平时高很多');
    } catch (error) {
      debugPrint('[桌宠] 切换实时模式失败：$error');
      state = state.copyWith(busy: false, error: '$error');
      return PetActionResult(false, '$error');
    }
  }

  Future<void> setDefaultResident(String residentId) async {
    await _settings.setDefaultResident(residentId);
    await refresh();
  }

  Future<void> setInterval(int intervalMs) async {
    await _settings.setInterval(intervalMs);
    if (state.captureRunning) {
      await _native.setWatchInterval(intervalMs);
    }
    await refresh();
  }

  /// 实时模式每次唤醒附几张（1—6）。
  Future<void> setRealtimeFrames(int frames) async {
    await _settings.setRealtimeFrames(frames);
    await refresh();
  }

  /// 实时模式多久唤醒一次（秒）。
  Future<void> setRealtimeGap(int seconds) async {
    await _settings.setRealtimeGap(seconds);
    await refresh();
  }
}

final petControllerProvider = NotifierProvider<PetController, PetRuntimeState>(
  PetController.new,
);
