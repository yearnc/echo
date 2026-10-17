import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../models/voice_settings.dart';

/// 语音设置的读写（2026-10-17）。
///
/// 存 `app_settings` 两个键，和外观、心理安全一样：
/// 这类"一行设置"不值得为它加表、加迁移。
class VoiceSettingsController extends Notifier<VoiceSettings> {
  static const String enabledKey = 'voice.enabled';
  static const String sourceKey = 'voice.source';

  @override
  VoiceSettings build() {
    _restore();
    return const VoiceSettings();
  }

  Future<void> _restore() async {
    final db = ref.read(databaseProvider);
    final rows = await (db.select(
      db.appSettings,
    )..where((t) => t.key.isIn([enabledKey, sourceKey]))).get();
    final map = {for (final row in rows) row.key: row.value};

    state = VoiceSettings(
      enabled: _readBool(map[enabledKey], fallback: true),
      source: VoiceSource.fromKey(map[sourceKey]),
    );
  }

  Future<void> setEnabled(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    await _write(enabledKey, enabled ? 'true' : 'false');
  }

  Future<void> setSource(VoiceSource source) async {
    state = state.copyWith(source: source);
    await _write(sourceKey, source.key);
  }

  Future<void> _write(String key, String value) async {
    final db = ref.read(databaseProvider);
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  static bool _readBool(String? raw, {required bool fallback}) =>
      raw == null ? fallback : raw == 'true';
}

final voiceSettingsControllerProvider =
    NotifierProvider<VoiceSettingsController, VoiceSettings>(
      VoiceSettingsController.new,
    );
