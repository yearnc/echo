import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/constants/app_texts.dart';
import '../../domain/models/ai_persona.dart';
import '../../domain/models/app_mode.dart';
import '../../domain/models/demo_script.dart';
import '../demo/demo_script_repository.dart';
import '../seed/demo_posts.dart';
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
    // 必须在人格之后：ai_interactions.personaId 有外键指向 ai_personas
    await _seedDemoContent();
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

  /// 首次启动时铺一批内容，让信息流不是空的。
  ///
  /// 回响模式的演示内容直接**从三幕脚本生成**：脚本里标了 `done` 的动作
  /// 就是"已经发生过的互动"，所以彩排时不需要等 0—48 小时。
  /// 用同一份脚本播种和播放，能保证镜头里的内容和数据库里的内容永远一致。
  Future<void> _seedDemoContent() async {
    final count = await _db.posts.count().getSingle();
    if (count > 0) return;

    final scripts = await const DemoScriptRepository().loadAll();
    final echoScripts = scripts.where((s) => s.post != null).toList();
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.batch((batch) {
      for (final script in echoScripts) {
        final spec = script.post!;
        final stats = _finalStatsOf(script);
        final lastAt = script.effectiveDurationMs;

        batch.insert(
          _db.posts,
          PostsCompanion(
            id: Value(spec.id),
            content: Value(spec.content),
            images: Value(jsonEncode(spec.images)),
            createdAt: Value(now - lastAt),
            scope: Value(spec.scope),
            topicName: Value(spec.topicName),
            isHot: Value(stats.likes > 100),
            likeCount: Value(stats.likes),
            commentCount: Value(stats.comments),
          ),
        );

        final index = <String, int>{};
        for (final step in script.steps.where((s) => s.isComment)) {
          final personaId = step.personaId ?? 'persona_001';
          final seq = index.update(personaId, (v) => v + 1, ifAbsent: () => 0);
          // 评论的"发生时间"按脚本时间轴倒推，读起来像自然散布的
          final at = now - (lastAt - step.atMs);
          batch.insert(
            _db.aiInteractions,
            AiInteractionsCompanion(
              id: Value('${spec.id}_${personaId}_$seq'),
              postId: Value(spec.id),
              personaId: Value(personaId),
              type: const Value('comment'),
              mediaType: Value(step.mediaType),
              content: Value(step.content),
              voicePath: Value(step.voiceAsset),
              transcript: Value(step.transcript),
              voiceDurationMs: Value(step.voiceDurationMs),
              scheduledAt: Value(at),
              executedAt: Value(at),
              status: const Value('done'),
              likeCount: Value(_likeSeedFor(step.atMs)),
            ),
          );
        }
      }

      // 清醒模式的示例记录（第三幕切过去之后能看到）
      for (final record in DemoPosts.clearRecords) {
        batch.insert(
          _db.posts,
          PostsCompanion(
            id: Value(record.id),
            content: Value(record.content),
            images: Value(jsonEncode(record.images)),
            createdAt: Value(record.createdAt.millisecondsSinceEpoch),
            scope: Value(record.scope),
          ),
        );
      }
    });
  }

  /// 把时间轴跑一遍，算出这条帖子最终的点赞/评论数。
  _Stats _finalStatsOf(DemoScript script) {
    var likes = 0;
    var comments = 0;
    for (final step in script.steps) {
      switch (step.type) {
        case 'stats':
          likes = step.likes ?? likes;
          comments = step.comments ?? comments;
        case 'like_burst':
          likes += step.delta ?? 0;
        case 'comment':
          comments += 1;
      }
    }
    return _Stats(likes, comments);
  }

  /// 评论自带的小赞数：越早出现的评论攒得越多，看着更像真的。
  int _likeSeedFor(int atMs) => (atMs / 1000).round().clamp(0, 40);
}

class _Stats {
  const _Stats(this.likes, this.comments);

  final int likes;
  final int comments;
}
