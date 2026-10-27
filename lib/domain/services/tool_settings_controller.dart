import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../models/tool_settings.dart';

/// 工具调用限额的读写。
///
/// 和其他“一行设置”一样存 `app_settings`，不为它加表。
class ToolSettingsController extends Notifier<ToolSettings> {
  static const String roundsKey = 'tools.maxRounds';
  static const String timeoutKey = 'tools.timeoutSeconds';

  @override
  ToolSettings build() {
    _restore();
    return ToolSettings.defaults;
  }

  Future<void> _restore() async {
    final db = ref.read(databaseProvider);
    final rows = await (db.select(
      db.appSettings,
    )..where((t) => t.key.isIn([roundsKey, timeoutKey]))).get();
    final map = {for (final row in rows) row.key: row.value};
    state = ToolSettings(
      maxRounds:
          int.tryParse(map[roundsKey] ?? '') ?? ToolSettings.defaults.maxRounds,
      timeoutSeconds:
          int.tryParse(map[timeoutKey] ?? '') ??
          ToolSettings.defaults.timeoutSeconds,
    );
  }

  Future<void> setMaxRounds(int rounds) async {
    final next = state.copyWith(maxRounds: rounds);
    state = next;
    await _write(roundsKey, '${next.maxRounds}');
  }

  Future<void> setTimeoutSeconds(int seconds) async {
    final next = state.copyWith(timeoutSeconds: seconds);
    state = next;
    await _write(timeoutKey, '${next.timeoutSeconds}');
  }

  Future<void> _write(String key, String value) async {
    final db = ref.read(databaseProvider);
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }
}

final toolSettingsProvider =
    NotifierProvider<ToolSettingsController, ToolSettings>(
      ToolSettingsController.new,
    );
