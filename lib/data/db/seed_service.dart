import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/constants/app_texts.dart';
import '../../domain/models/ai_persona.dart';
import '../../domain/models/app_mode.dart';
import 'app_database.dart';

/// 首次启动时的内容播种。
///
/// 播种的是"内容资产"而不是假数据：12 位 AI 住民、默认设置、
/// 以及用户自己的资料行。演示模式与真实模式共用同一份住民表，
/// 所以演示彩排时看到的人格，和真实调度时用的是同一批。
class SeedService {
  const SeedService(this._db);

  final AppDatabase _db;

  Future<void> seedIfNeeded() async {
    await _seedSettings();
    await _seedProfile();
    await _seedPersonas();
  }

  Future<void> _seedSettings() async {
    final existing = await _db.select(_db.appSettings).get();
    final keys = existing.map((row) => row.key).toSet();

    final defaults = <String, String>{
      'app.mode': AppMode.echo.scope,
      'app.mode.switchCooldownHours': '24',
      'echo.replyDensity': '中',
      'echo.likeLevel': '中',
      'echo.humanLevel': '3',
      'echo.voiceEnabled': 'true',
      'echo.stickerEnabled': 'true',
      'echo.immersive': 'true',
      'clear.permanentNoticeShown': 'true',
      'safety.addictionGuard': 'true',
      'safety.coolDownMode': 'false',
      'safety.feedbackViewThreshold': '8',
      'safety.minorBlocked': 'true',
      'schema.version': '1',
    };

    final toInsert = <AppSettingsCompanion>[];
    for (final entry in defaults.entries) {
      if (keys.contains(entry.key)) continue;
      toInsert.add(AppSettingsCompanion.insert(
        key: entry.key,
        value: entry.value,
        scope: Value(entry.key.startsWith('echo')
            ? 'echo'
            : entry.key.startsWith('clear')
                ? 'clear'
                : 'shared'),
      ));
    }
    if (toInsert.isNotEmpty) {
      await _db.batch((batch) => batch.insertAll(_db.appSettings, toInsert));
    }
  }

  Future<void> _seedProfile() async {
    final count = await _db.userProfile.count().getSingle();
    if (count > 0) return;

    await _db.into(_db.userProfile).insert(
          UserProfileCompanion.insert(
            id: 'me',
            nickname: const Value(AppTexts.defaultNickname),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> _seedPersonas() async {
    final count = await _db.aiPersonas.count().getSingle();
    if (count > 0) return;

    final raw = await rootBundle.loadString('assets/personas/personas.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = decoded['personas'] as List<dynamic>? ?? const [];

    final companions = list.map((item) {
      final persona = AiPersona.fromJson(item as Map<String, dynamic>);
      return AiPersonasCompanion.insert(
        id: persona.id,
        name: persona.name,
        avatar: Value(persona.avatar),
        bio: Value(persona.bio),
        languageStyle: Value(persona.languageStyle),
        tone: Value(persona.tone),
        activeHours: Value(jsonEncode(persona.activeHours)),
        likeProbability: Value(persona.likeProbability),
        commentProbability: Value(persona.commentProbability),
        replyLength: Value(persona.replyLength),
        voiceModel: Value(persona.voiceModel),
        level: Value(persona.level),
        badges: Value(jsonEncode(persona.badges)),
        ipLocation: Value(persona.ipLocation),
        followers: Value(persona.followers),
        following: Value(persona.following),
        personalityType: Value(persona.personalityType),
        memoryEnabled: Value(persona.memoryEnabled),
        relationshipLevel: Value(persona.relationshipLevel),
      );
    }).toList(growable: false);

    if (companions.isEmpty) return;
    await _db.batch((batch) => batch.insertAll(_db.aiPersonas, companions));
  }
}
