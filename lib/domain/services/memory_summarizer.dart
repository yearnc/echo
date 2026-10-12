import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/post_repository.dart';
import '../../data/repositories/relationship_repository.dart';
import '../models/ai_persona.dart';
import '../models/model_config.dart';
import 'model_content_generator.dart';
import 'model_gateway.dart';

/// 「我记得你…」（B4）。
///
/// 住民记得你什么，就存在 `ai_relationships.memory_summary` 这一列里。
/// 它不是聊天记录：全量历史既贵又没必要，还有隐私上的顾虑——你的帖文
/// 不该被整段搬进每一次请求。所以这里存的是**压缩过的一句话**。
///
/// 这件事**永远不该影响到互动本身**：它跑在后台、带冷却、整段包着 catch，
/// 失败了就当这次没记住。住民照样评论你，只是少一点"上次那事"。
class MemorySummarizer {
  const MemorySummarizer({
    required this.db,
    required this.posts,
    required this.relationships,
    required this.gateway,
  });

  final AppDatabase db;
  final PostRepository posts;
  final RelationshipRepository relationships;
  final ModelGateway gateway;

  /// 同一个人多久才重新记一次。
  ///
  /// 记忆是慢慢变的，而且它要花一次模型调用；每次兑现互动都重记一遍，
  /// 既贵又会把"他记得的事"洗成一堆同义句。
  static const Duration cooldown = Duration(hours: 12);

  /// 每个人上次被记住的时刻。和 `world.lastTickAt` 一个性质：调度水位，
  /// 不属于关系本身，所以放 app_settings 而不是再给关系表加一列。
  static const String watermarkPrefix = 'resident.memory.lastAt.';

  /// 一次给一批人更新记忆。返回真的写了几条。
  ///
  /// **一次请求写完整批**（和评论一样）：八个人分别问一遍模型，既是八次花销，
  /// 也容易让每个人的记忆长得一模一样。
  Future<int> refresh({required List<AiPersona> personas}) async {
    if (personas.isEmpty) return 0;

    final now = DateTime.now();
    final marks = await _watermarks(personas.map((persona) => persona.id));
    final due = [
      for (final persona in personas)
        if (_isDue(marks[persona.id], now)) persona,
    ];
    if (due.isEmpty) return 0;

    // scope 显式写出来：记忆只在回响世界里用，清醒模式的记录不参与
    final recent = await posts.recentMine(scope: 'echo');
    final contents = [
      for (final post in recent)
        if (post.content.trim().isNotEmpty) post.content,
    ];
    if (contents.isEmpty) return 0;

    var lines = <String, String>{};
    try {
      final config = await gateway.activeConfig();
      if (config != null) {
        lines = await _askModel(
          config: config,
          personas: due,
          recentPosts: contents,
        );
      }
    } catch (error) {
      debugPrint('[记忆] 模型没写成，退回截一句：$error');
    }

    // 没配模型、模型挂了、或者它一条都没写出来——退回到"截一句原话"。
    // 批量生成少写一条的（解析时被丢掉的），也补上。
    final gist = localGist(contents.first);
    if (gist != null) {
      for (final persona in due) {
        lines.putIfAbsent(persona.id, () => gist);
      }
    }
    if (lines.isEmpty) return 0;

    var written = 0;
    for (final persona in due) {
      final line = lines[persona.id]?.trim() ?? '';
      if (line.isEmpty) continue;

      await relationships.updateMemory(personaId: persona.id, summary: line);
      await _saveWatermark(persona.id, now);
      written++;
    }
    return written;
  }

  Future<Map<String, String>> _askModel({
    required ModelConfig config,
    required List<AiPersona> personas,
    required List<String> recentPosts,
  }) async {
    final raw = await gateway.complete(
      config: config,
      messages: [
        {'role': 'system', 'content': memoryPrompt(personas, recentPosts)},
        {'role': 'user', 'content': '请写出这 ${personas.length} 条记忆。'},
      ],
      temperature: 0.8,
      maxTokens: 400,
      timeout: const Duration(seconds: 20),
    );

    final byIndex = ModelContentGenerator.parseIndexedContents(
      raw,
      personas.length,
    );
    return {
      for (final entry in byIndex.entries) personas[entry.key - 1].id: entry.value,
    };
  }

  /// 记忆提示词：素材是**你**的帖子，产出是每个人自己那句话。纯函数，单独测。
  ///
  /// 刻意点名"每个人记住的点可以不一样"：住民各有各的圈子和兴趣，
  /// 摄影的人记住那张天空照，爱做饭的人记住那锅汤——同一件事在八个人眼里
  /// 本来就该有八种说法。否则八条记忆一模一样，一眼就是"系统生成"。
  static String memoryPrompt(
    List<AiPersona> personas,
    List<String> recentPosts,
  ) {
    final buffer = StringBuffer()
      ..writeln('你是「回响」这个社区里的几个人。下面是一位邻居最近发过的东西，')
      ..writeln('请你们各自用一句话记住他，15—30 字，像"他上周拍过一张天空照"这样。')
      ..writeln()
      ..writeln('要点：')
      ..writeln('- 只写你记住的、具体的事，不要评价、不要客套、不要对他说什么')
      ..writeln('- 每个人记住的点可以不一样，跟你自己平时在意的东西有关')
      ..writeln('- 不要提到自己是 AI，不要复述整段原话')
      ..writeln()
      ..writeln('他最近发过的：');

    for (final post in recentPosts) {
      buffer.writeln('- ${_flatten(post)}');
    }

    buffer
      ..writeln()
      ..writeln('你们分别是谁：');

    for (var i = 0; i < personas.length; i++) {
      final persona = personas[i];
      final circle = persona.circle.isEmpty ? '日常' : persona.circle;
      buffer.writeln('[${i + 1}] ${persona.name}（$circle｜${persona.personalityType}）');
    }

    buffer
      ..writeln()
      ..writeln('只输出一个 JSON 数组，不要代码块、不要任何解释：')
      ..writeln('[{"index": 1, "content": "一句话"}, ...]');

    return buffer.toString();
  }

  /// 没配模型（或者模型挂了）时的兜底：从最近那条帖子里截一句。
  ///
  /// 它不如模型写得好——模型会说"他拍过一张天空照，那天风挺大"，这里只能把
  /// 原话截一段出来。但"记得你发过什么"这件事本身是真的，而没配模型的用户
  /// 不该连这个都没有。
  static String? localGist(String content) {
    final flat = _flatten(content);
    if (flat.isEmpty) return null;

    final head = flat.split(RegExp(r'[。！？!?]')).first.trim();
    final picked = head.isEmpty ? flat : head;
    final clipped = picked.length <= 24 ? picked : '${picked.substring(0, 24)}…';
    return '他最近发过：「$clipped」';
  }

  static String _flatten(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _isDue(DateTime? last, DateTime now) =>
      last == null || now.difference(last) >= cooldown;

  Future<Map<String, DateTime>> _watermarks(Iterable<String> personaIds) async {
    final query = db.select(db.appSettings)
      ..where((t) => t.key.like('$watermarkPrefix%'));
    final rows = await query.get();

    final result = <String, DateTime>{};
    for (final row in rows) {
      final raw = int.tryParse(row.value);
      if (raw == null) continue;
      result[row.key.substring(watermarkPrefix.length)] =
          DateTime.fromMillisecondsSinceEpoch(raw);
    }
    return result;
  }

  Future<void> _saveWatermark(String personaId, DateTime at) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: '$watermarkPrefix$personaId',
            value: '${at.millisecondsSinceEpoch}',
            scope: const Value('echo'),
          ),
        );
  }
}

final memorySummarizerProvider = Provider<MemorySummarizer>(
  (ref) => MemorySummarizer(
    db: ref.watch(databaseProvider),
    posts: ref.watch(postRepositoryProvider),
    relationships: ref.watch(relationshipRepositoryProvider),
    gateway: ref.watch(modelGatewayProvider),
  ),
);
