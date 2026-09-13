import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/ai_persona.dart';
import '../../domain/models/app_mode.dart';
import '../repositories/plan_script_repository.dart';
import '../seed/builtin_plan_scripts.dart';
import 'app_database.dart';

/// 首次启动时的播种。
///
/// 只播两样东西：**AI 住民**（内容资产，社区不能没人）和
/// **三个内置策划脚本**（三幕转来的默认剧本）。
///
/// 帖子与记录刻意不播种：空信息流才是新用户的真实起点，
/// 也让"第一次发帖"不被一堆预置内容稀释。
class SeedService {
  const SeedService(this._db);

  final AppDatabase _db;

  Future<void> seedIfNeeded() async {
    await _seedSettings();
    await _seedProfile();
    await _seedPersonas();
    await _seedPlanScripts();
  }

  Future<void> _seedSettings() async {
    final existing = await _db.select(_db.appSettings).get();
    final keys = existing.map((row) => row.key).toSet();

    final defaults = <String, String>{
      'app.mode': AppMode.echo.scope,
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
      toInsert.add(
        AppSettingsCompanion.insert(
          key: entry.key,
          value: entry.value,
          scope: Value(
            entry.key.startsWith('echo')
                ? 'echo'
                : entry.key.startsWith('clear')
                ? 'clear'
                : 'shared',
          ),
        ),
      );
    }
    if (toInsert.isNotEmpty) {
      await _db.batch((batch) => batch.insertAll(_db.appSettings, toInsert));
    }
  }

  Future<void> _seedProfile() async {
    final count = await _db.userProfile.count().getSingle();
    if (count > 0) return;

    await _db
        .into(_db.userProfile)
        .insert(
          UserProfileCompanion.insert(
            id: 'me',
            nickname: const Value(''),
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

    final companions = list
        .map((item) {
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
            followers: Value(persona.followers),
            following: Value(persona.following),
            personalityType: Value(persona.personalityType),
            memoryEnabled: Value(persona.memoryEnabled),
            relationshipLevel: Value(persona.relationshipLevel),
          );
        })
        .toList(growable: false);

    if (companions.isEmpty) return;
    await _db.batch((batch) => batch.insertAll(_db.aiPersonas, companions));
  }

  /// 三个内置策划脚本：由三幕演示脚本转换而来，可改可复制。
  Future<void> _seedPlanScripts() async {
    final scripts = await BuiltinPlanScripts.load();
    await PlanScriptRepository(_db).seedIfEmpty(scripts);
  }
}
