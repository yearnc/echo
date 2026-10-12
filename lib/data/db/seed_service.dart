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
  /// 已装上的内容资产版本（见 [_seedPersonas]）。
  static const String contentVersionKey = 'personas.contentVersion';

  Future<void> _seedPersonas() async {
    final raw = await rootBundle.loadString('assets/personas/personas.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final personas = (decoded['personas'] as List<dynamic>? ?? const [])
        .map((item) => AiPersona.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    if (personas.isEmpty) return;

    await _insertMissingPersonas(personas);
    await _insertMissingRoutines(personas);

    // 住民是**内容资产**，会随内容一起改（整套人设换过一次）。
    // 而"只补不覆盖"意味着老库永远拿不到新内容，所以这里按内容版本号判断：
    // 版本变了就把内容字段整批刷新一遍。老库第一次升上来（没有版本号）
    // 也会走这一趟——那正好是它最需要拿到新内容的时候。
    final version = '${decoded['_schemaVersion'] ?? 0}';
    if (await _readSetting(contentVersionKey) == version) return;

    await _refreshPersonaContent(personas);
    await _renameLegacyTopics();
    await _saveSetting(contentVersionKey, version);
  }

  /// 上一版的世界观标签 → 这一版（一次性的）。
  ///
  /// 帖子本身是历史，一个字都不动；但它的**话题标签**是分发用的分类，
  /// 留着"同校圈"这种词，老帖子会在新社区里一直出戏。
  static const Map<String, String> legacyTopics = {
    '同校圈': '日常',
    '学习': '读书',
    '失物招领': '日常',
    '表白墙': '树洞',
    '社团招新': '日常',
    '兴趣小组': '日常',
    '二手': '日常',
  };

  Future<void> _renameLegacyTopics() async {
    await _db.batch((batch) {
      for (final entry in legacyTopics.entries) {
        batch.update(
          _db.posts,
          PostsCompanion(topicName: Value(entry.value)),
          where: (t) => t.topicName.equals(entry.key),
        );
      }
    });
  }

  /// 把内容字段整批重写成 assets 里那一份。
  ///
  /// 只碰**内容**：名字、人设、语气、圈子、作息。运行期的那本账
  /// （和你的关系、私信、互动、帖子、他有没有被删过）一个字都不动——
  /// 那些是这个库的历史，不该随内容一起被换掉。
  Future<void> _refreshPersonaContent(List<AiPersona> personas) async {
    await _db.batch((batch) {
      for (final persona in personas) {
        batch.update(
          _db.aiPersonas,
          AiPersonasCompanion(
            name: Value(persona.name),
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
          ),
          where: (t) => t.id.equals(persona.id),
        );
      }
    });

    // 作息整批重来：它是内容的一部分，"几点在哪"改了就整条换掉，
    // 而不是新加几条、旧的还留着
    await _db.delete(_db.personaRoutines).go();
    await _insertMissingRoutines(personas);
  }

  Future<String?> _readSetting(String key) async {
    final row =
        await (_db.select(_db.appSettings)..where((t) => t.key.equals(key)))
            .getSingleOrNull();
    return row?.value;
  }

  Future<void> _saveSetting(String key, String value) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: key,
            value: value,
            scope: const Value('shared'),
          ),
        );
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
