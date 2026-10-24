import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../models/safety_settings.dart';

/// 心理安全设置的状态（规划书 §6.9 / §13）。
///
/// 设置项在 `app_settings` 里早已播种（`safety.*` 三个键），这里只是把它们
/// 变成可读写的状态——之前它们躺在库里没人用。
class SafetyController extends Notifier<SafetySettings> {
  static const String guardKey = 'safety.addictionGuard';
  static const String coolDownKey = 'safety.coolDownMode';
  static const String thresholdKey = 'safety.feedbackViewThreshold';

  /// 未成年人保护（规划书 §6.10）。默认关——开它的动作该由人来做，
  /// 而不是替所有人默认打开。
  static const String minorKey = 'safety.minorProtection';

  /// 清醒模式每日使用上限（分钟）；0 = 关闭。
  static const String dailyLimitKey = 'safety.clearDailyLimitMinutes';

  /// 阈值的合理区间：1 次太烦，50 次等于没有。
  static const int minThreshold = 3;
  static const int maxThreshold = 30;

  /// 每日上限的合理区间：15 分钟以下是折磨，8 小时以上等于没设。
  static const int minDailyLimit = 15;
  static const int maxDailyLimit = 480;

  @override
  SafetySettings build() {
    _restore();
    return const SafetySettings();
  }

  Future<void> _restore() async {
    final db = ref.read(databaseProvider);
    final rows = await (db.select(db.appSettings)
          ..where(
            (t) =>
                t.key.isIn([
                  guardKey,
                  coolDownKey,
                  thresholdKey,
                  minorKey,
                  dailyLimitKey,
                ]),
          ))
        .get();
    final map = {for (final row in rows) row.key: row.value};

    state = SafetySettings(
      addictionGuard: _readBool(map[guardKey], fallback: true),
      coolDownMode: _readBool(map[coolDownKey], fallback: false),
      feedbackViewThreshold:
          int.tryParse(map[thresholdKey] ?? '') ??
          const SafetySettings().feedbackViewThreshold,
      minorProtection: _readBool(map[minorKey], fallback: false),
      dailyLimitMinutes:
          int.tryParse(map[dailyLimitKey] ?? '') ?? 0,
    );
  }

  Future<void> setAddictionGuard(bool enabled) async {
    state = state.copyWith(addictionGuard: enabled);
    await _write(guardKey, enabled ? 'true' : 'false');
  }

  Future<void> setCoolDownMode(bool enabled) async {
    state = state.copyWith(coolDownMode: enabled);
    await _write(coolDownKey, enabled ? 'true' : 'false');
  }

  Future<void> setMinorProtection(bool enabled) async {
    state = state.copyWith(minorProtection: enabled);
    await _write(minorKey, enabled ? 'true' : 'false');
  }

  /// 设为 0 表示关闭；其余值夹在 15—480 分钟之间。
  Future<void> setDailyLimitMinutes(int value) async {
    final next = value <= 0 ? 0 : value.clamp(minDailyLimit, maxDailyLimit);
    state = state.copyWith(dailyLimitMinutes: next);
    await _write(dailyLimitKey, '$next');
  }

  Future<void> setFeedbackViewThreshold(int value) async {
    final clamped = value.clamp(minThreshold, maxThreshold);
    state = state.copyWith(feedbackViewThreshold: clamped);
    await _write(thresholdKey, '$clamped');
  }

  Future<void> _write(String key, String value) async {
    final db = ref.read(databaseProvider);
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  /// 存的是字符串，坏值一律当"没设置过"处理，回落到默认。
  static bool _readBool(String? raw, {required bool fallback}) =>
      raw == null ? fallback : raw == 'true';
}

final safetyControllerProvider =
    NotifierProvider<SafetyController, SafetySettings>(
      SafetyController.new,
    );
