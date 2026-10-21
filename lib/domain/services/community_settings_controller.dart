import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../models/community_settings.dart';

/// 社区全局开关的读写。
///
/// 存 `app_settings` 一个键，和语音、外观一样：一行设置不值得为它加表。
class CommunitySettingsController extends Notifier<CommunitySettings> {
  static const String allowResidentPostsKey =
      'community.allowResidentPosts';
  static const String allowLurkKey = 'community.allowLurk';
  static const String aiPeerLimitKey = 'community.aiPeerInteractionLimit';
  static const String sendImagesDirectlyKey =
      'community.sendPostImagesDirectly';

  @override
  CommunitySettings build() {
    _restore();
    return CommunitySettings.defaults;
  }

  Future<void> _restore() async {
    final db = ref.read(databaseProvider);
    final rows =
        await (db.select(db.appSettings)..where(
              (t) => t.key.isIn([
                allowResidentPostsKey,
                allowLurkKey,
                aiPeerLimitKey,
                sendImagesDirectlyKey,
              ]),
            ))
            .get();
    final map = {for (final row in rows) row.key: row.value};
    state = CommunitySettings(
      allowResidentPosts: map[allowResidentPostsKey] == 'true',
      // 没写过就是默认开
      allowLurk: map[allowLurkKey] != 'false',
      aiPeerInteractionLimit:
          int.tryParse(map[aiPeerLimitKey] ?? '') ?? 2,
      sendPostImagesDirectly: map[sendImagesDirectlyKey] == 'true',
    );
  }

  Future<void> setAllowResidentPosts(bool allowed) async {
    state = state.copyWith(allowResidentPosts: allowed);
    await _write(allowResidentPostsKey, allowed ? 'true' : 'false');
  }

  Future<void> setAllowLurk(bool allowed) async {
    state = state.copyWith(allowLurk: allowed);
    await _write(allowLurkKey, allowed ? 'true' : 'false');
  }

  Future<void> setAiPeerInteractionLimit(int limit) async {
    final clamped = limit.clamp(0, 10);
    state = state.copyWith(aiPeerInteractionLimit: clamped);
    await _write(aiPeerLimitKey, '$clamped');
  }

  Future<void> setSendPostImagesDirectly(bool direct) async {
    state = state.copyWith(sendPostImagesDirectly: direct);
    await _write(sendImagesDirectlyKey, direct ? 'true' : 'false');
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

final communitySettingsProvider =
    NotifierProvider<CommunitySettingsController, CommunitySettings>(
      CommunitySettingsController.new,
    );
