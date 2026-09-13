import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/plan_event_repository.dart';
import '../models/app_mode.dart';
import 'mode_controller.dart';

/// 模式切换规则（规划书 §2.4）。
///
/// 这里管两件事：
/// 1. **归档**：切到清醒模式时停掉待发队列、把已有的虚拟反馈归档
/// 2. **留痕**：每次切换写一条 `mode_switch_logs`
///
/// 二次确认和年龄门不在这里：那是要弹窗的，属于 UI 层。
/// 冷却期也去掉了——用户想什么时候切就什么时候切，不该被拦。
class ModeSwitchService {
  ModeSwitchService({
    required this.db,
    required this.readMode,
    required this.persistMode,
    required this.interactions,
    required this.planEvents,
  });

  final AppDatabase db;

  /// 读当前模式 / 写回模式。用回调注入而不是直接持有 Notifier，
  /// 是为了不去碰它的受保护成员（state 只能由 Notifier 自己改）。
  final AppMode Function() readMode;
  final Future<void> Function(AppMode target) persistMode;

  final InteractionRepository interactions;
  final PlanEventRepository planEvents;

  static const String rebuildGuideKey = 'clear.rebuildGuideShown';

  /// 执行切换。调用方必须先过二次确认 / 年龄门。
  Future<void> switchTo(AppMode target) async {
    final from = readMode();
    if (from == target) return;

    var archiveAction = 'kept';

    if (target.isClear) {
      // 停止待发队列 + 归档已有虚拟反馈（规划书 §2.4.1）
      await interactions.cancelAllPending();
      await planEvents.cancelAllPending();
      final archived = await interactions.archiveExecuted();
      archiveAction = archived > 0 ? 'archived' : 'kept';

      // 切过去之后提示一次"重建引导"
      await _write(rebuildGuideKey, 'false');
    }

    await db
        .into(db.modeSwitchLogs)
        .insert(
          ModeSwitchLogsCompanion.insert(
            id: 'switch_${DateTime.now().microsecondsSinceEpoch}',
            fromMode: from.scope,
            toMode: target.scope,
            switchedAt: DateTime.now().millisecondsSinceEpoch,
            archiveAction: Value(archiveAction),
          ),
        );

    await persistMode(target);
  }

  /// 重建引导是否还该显示（切到清醒后显示一次）。
  Future<bool> shouldShowRebuildGuide() async =>
      (await _read(rebuildGuideKey)) == 'false';

  Future<void> markRebuildGuideShown() => _write(rebuildGuideKey, 'true');

  Future<String?> _read(String key) async {
    final query = db.select(db.appSettings)..where((t) => t.key.equals(key));
    final row = await query.getSingleOrNull();
    return row?.value;
  }

  Future<void> _write(String key, String value) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }
}

final modeSwitchServiceProvider = Provider<ModeSwitchService>(
  (ref) => ModeSwitchService(
    db: ref.watch(databaseProvider),
    readMode: () => ref.read(modeControllerProvider),
    persistMode: (target) =>
        ref.read(modeControllerProvider.notifier).persist(target),
    interactions: ref.watch(interactionRepositoryProvider),
    planEvents: ref.watch(planEventRepositoryProvider),
  ),
);
