import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_mode.dart';

/// 当前模式。
///
/// M1 阶段先放在内存里，页面骨架可以立刻按模式切换渲染；
/// M4 会把它接到 `mode_switch_logs` 与 `app_settings` 上，
/// 并在切换时执行「停止调度 → 归档 AI 互动 → 显示永久提示」这一整套动作。
class ModeController extends Notifier<AppMode> {
  @override
  AppMode build() => AppMode.echo;

  /// 切到清醒模式：M4 会补齐归档与重建引导。
  void toClear() => state = AppMode.clear;

  /// 切到回响模式：M4 会补齐二次确认、年龄门与冷却期校验。
  void toEcho() => state = AppMode.echo;

  void toggle() => state = state.opposite;
}

final modeControllerProvider =
    NotifierProvider<ModeController, AppMode>(ModeController.new);

/// 便捷读取：`ref.watch(isEchoModeProvider)`。
final isEchoModeProvider = Provider<bool>(
  (ref) => ref.watch(modeControllerProvider).isEcho,
);
