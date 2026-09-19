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

  /// 住民是**内容资产**（真身在 `assets/personas/personas.json`），
  /// 所以这里只做一件事：把 assets 里新加的补进库。
  ///
  /// 早先的写法是"一个住民都没有才播种"，于是住民从 12 个扩到 24 个之后，
  /// 老库永远拿不到新的那批——它卡在 `count > 0` 那道判断外面。改成按 id
  /// 补齐之后，每次启动都会把缺的补上，而已经存在的那些**不动**：
  /// 住民在 B3 之后会挂上关系与记忆，覆盖会把它们一并抹掉。
  Future<void> _seedPersonas() async {
    final raw = await rootBundle.loadString('assets/personas/personas.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final personas = (decoded['personas'] as List<dynamic>? ?? const [])
        .map((item) => AiPersona.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    if (personas.isEmpty) return;

    await _insertMissingPersonas(personas);
    await _insertMissingRoutines(personas);
  }

  Future<void> _insertMissingPersonas(List<AiPersona> personas) async {
    final existing = await _db.select(_db.aiPersonas).get();
    final known = existing.map((row) => row.id).toSet();

    final companions = <AiPersonasCompanion>[];
    for (final persona in personas) {
      if (known.contains(persona.id)) continue;
      companions.add(
        AiPersonasCompanion.insert(
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
          circle: Value(persona.circle),
          memoryEnabled: Value(persona.memoryEnabled),
          relationshipLevel: Value(persona.relationshipLevel),
        ),
      );
    }
    if (companions.isEmpty) return;

    await _db.batch((batch) => batch.insertAll(_db.aiPersonas, companions));
  }

  /// 作息跟住民同一个策略：只补不覆盖。判断单位是"这个住民有没有作息"，
  /// 所以给某个住民加几条新作息不会碰到其他住民。
  Future<void> _insertMissingRoutines(List<AiPersona> personas) async {
    final existing = await _db.select(_db.personaRoutines).get();
    final filled = existing.map((row) => row.personaId).toSet();

    final companions = <PersonaRoutinesCompanion>[];
    for (final persona in personas) {
      if (filled.contains(persona.id)) continue;
      for (final routine in persona.routines) {
        companions.add(
          PersonaRoutinesCompanion.insert(
            personaId: persona.id,
            hour: routine.hour,
            place: Value(routine.place),
            activity: Value(routine.activity),
          ),
        );
      }
    }
    if (companions.isEmpty) return;

    await _db.batch((batch) => batch.insertAll(_db.personaRoutines, companions));
  }

  /// 三个内置策划脚本：由三幕演示脚本转换而来，可改可复制。
  Future<void> _seedPlanScripts() async {
    final scripts = await BuiltinPlanScripts.load();
    await PlanScriptRepository(_db).seedIfEmpty(scripts);
  }
}
