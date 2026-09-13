import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../models/app_mode.dart';

/// 当前模式。
///
/// 模式是**持久状态**：它记在 `app_settings` 里，冷启动要读回来——
/// 不然用户切到清醒模式、关掉 APP 再打开，又回到了虚拟社区。
///
/// 这里只管"现在是什么模式"；"能不能切、切的时候要归档什么"属于切换规则，
/// 在 [ModeSwitchService] 里。
class ModeController extends Notifier<AppMode> {
  static const String settingKey = 'app.mode';

  @override
  AppMode build() {
    _restore();
    return AppMode.echo;
  }

  Future<void> _restore() async {
    final db = ref.read(databaseProvider);
    final query = db.select(db.appSettings)
      ..where((t) => t.key.equals(settingKey));
    final row = await query.getSingleOrNull();
    if (row == null) return;
    state = AppMode.fromScope(row.value);
  }

  /// 写回配置并更新内存状态（只应由 ModeSwitchService 调用）。
  Future<void> persist(AppMode target) async {
    state = target;

    final db = ref.read(databaseProvider);
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: settingKey, value: target.scope),
        );
  }
}

final modeControllerProvider = NotifierProvider<ModeController, AppMode>(
  ModeController.new,
);

/// 便捷读取：`ref.watch(isEchoModeProvider)`。
final isEchoModeProvider = Provider<bool>(
  (ref) => ref.watch(modeControllerProvider).isEcho,
);
