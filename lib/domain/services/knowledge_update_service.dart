import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/knowledge_repository.dart';
import '../models/knowledge.dart';
import 'knowledge_service.dart';
import 'model_gateway.dart';
import 'web_search.dart';

class KnowledgeUpdateReport {
  const KnowledgeUpdateReport({
    required this.ran,
    this.added = 0,
    this.message = '',
  });

  const KnowledgeUpdateReport.skipped(this.message) : ran = false, added = 0;

  final bool ran;
  final int added;
  final String message;
}

/// 热门梗的每周自动更新（v4.11）。
///
/// 三个硬约束：
/// 1. **只增不删**：这一轮失败或模型抽风，旧条目必须原样留着。
/// 2. **来源可追**：每条都带搜索结果的链接和抓取时间；30 天后自动过期。
/// 3. **跨 isolate 节流**：WorkManager 和前台可能同时醒，10 分钟内只跑一次。
///
/// 不配模型的用户不会得到"半成品梗"：直接跳过，下次再试。
class KnowledgeUpdateService {
  KnowledgeUpdateService({
    required this.repository,
    required this.knowledge,
    required this.search,
    required this.gateway,
  });

  final KnowledgeRepository repository;
  final KnowledgeService knowledge;
  final WebSearchService search;
  final ModelGateway gateway;

  static const Duration interval = Duration(days: 7);
  static const Duration attemptCooldown = Duration(minutes: 10);
  static const int maxEntries = 8;

  bool _running = false;

  /// [force] 只在用户点「立即更新」时为 true：跳过七天/十分钟节流，
  /// 但仍会检查模型和自动更新开关。
  Future<KnowledgeUpdateReport> maybeRun({
    bool background = false,
    bool force = false,
  }) async {
    if (_running) {
      return const KnowledgeUpdateReport.skipped('上一轮还在跑');
    }
    final base = await repository.ensureTrendBase();
    if (!base.enabled || !base.autoUpdate) {
      return const KnowledgeUpdateReport.skipped('热门梗自动更新已关闭');
    }

    final now = DateTime.now();
    if (!force && base.lastUpdatedAt > 0) {
      final last = DateTime.fromMillisecondsSinceEpoch(base.lastUpdatedAt);
      if (now.difference(last) < interval) {
        return const KnowledgeUpdateReport.skipped('还没到一周');
      }
    }
    final attempt = await repository.trendAttemptAt();
    if (!force &&
        attempt != null &&
        now.difference(attempt) < attemptCooldown) {
      return const KnowledgeUpdateReport.skipped('刚试过，等一会儿再试');
    }

    _running = true;
    await repository.markTrendAttempt(now);
    try {
      final report = await _run(base, now, background: background);
      return report;
    } catch (error) {
      debugPrint('[知识库] 热门梗更新失败：$error');
      return KnowledgeUpdateReport(ran: false, message: '这一轮没更新成功：$error');
    } finally {
      _running = false;
    }
  }

  Future<KnowledgeUpdateReport> _run(
    KnowledgeBase base,
    DateTime now, {
    required bool background,
  }) async {
    final config = await gateway.activeConfig();
    if (config == null) {
      return const KnowledgeUpdateReport.skipped(
        '没有可用的对话模型，热门梗先不更新',
      );
    }

    final year = now.year;
    final queries = [
      '$year年 本月 网络流行语 热梗 出处 用法',
      '最近流行的网络梗 来源 意思 $year',
      '$year 热门梗 盘点 例子',
    ];

    final hits = <String>[];
    final urls = <String>{};
    for (final query in queries) {
      final outcome = await search.search(query);
      if (!outcome.ok) {
        debugPrint('[知识库] 搜索“$query”没成：${outcome.message}');
        continue;
      }
      for (final item in outcome.results.take(6)) {
        urls.add(item.url);
        hits.add(
          '- ${item.title}\n  ${item.snippet}\n  ${item.url}'
          '${item.date.isEmpty ? '' : '（${item.date}）'}',
        );
      }
    }
    if (hits.isEmpty) {
      return const KnowledgeUpdateReport.skipped('没搜到可用内容，保留旧条目');
    }

    final raw = await gateway.complete(
      config: config,
      messages: [
        {
          'role': 'system',
          'content':
              '你是网络用语观察员。只根据给出的搜索结果整理，'
              '不要凭记忆补充，也不要编造来源。'
              '不确定是不是梗、或者搜索结果互相矛盾的，宁可不收。',
        },
        {
          'role': 'user',
          'content': _prompt(hits),
        },
      ],
      temperature: 0.3,
      maxTokens: 2200,
      timeout: const Duration(seconds: 75),
    );

    final entries = _parse(raw);
    if (entries.isEmpty) {
      return const KnowledgeUpdateReport.skipped('模型没整理出可用条目，保留旧内容');
    }

    var added = 0;
    for (final item in entries.take(maxEntries)) {
      final title = (item['title'] as String?)?.trim() ?? '';
      if (title.isEmpty) continue;
      final content = (item['content'] as String?)?.trim() ?? '';
      final summary = (item['summary'] as String?)?.trim() ?? '';
      if (content.isEmpty && summary.isEmpty) continue;

      final url = (item['source_url'] as String?)?.trim() ?? '';
      final sourceUrl = urls.contains(url) ? url : (urls.isEmpty ? '' : urls.first);
      await knowledge.upsertAutoEntry(
        baseId: base.id,
        entry: KnowledgeEntry(
          id: '',
          baseId: base.id,
          title: title,
          summary: summary,
          content: content,
          examples: _stringList(item['examples']).take(3).toList(),
          tags: _stringList(item['tags']).take(6).toList(),
          sourceUrl: sourceUrl,
          sourceTitle: (item['source_title'] as String?)?.trim() ?? '',
        ),
      );
      added++;
    }

    if (added == 0) {
      return const KnowledgeUpdateReport.skipped('没有写进任何条目，保留旧内容');
    }
    await repository.touchBase(
      base.id,
      lastUpdatedAt: now.millisecondsSinceEpoch,
    );
    knowledge.invalidate(baseId: base.id);
    debugPrint('[知识库] 热门梗更新：$added 条（${background ? '后台' : '前台'}）');
    return KnowledgeUpdateReport(ran: true, added: added, message: '更新了 $added 条');
  }

  static String _prompt(List<String> hits) => '''
下面是最近的搜索结果。请整理最多 $maxEntries 个**确实在结果里出现过**的网络梗。

每个梗输出一个对象：
{
  "title": "梗名",
  "summary": "一句话：什么意思、什么场合能用",
  "content": "来源：……；用处：……（来源说不清就写“来源不明确”）",
  "examples": ["例句1", "例句2"],
  "tags": ["标签"],
  "source_url": "必须从下面的链接里原样选一个；选不出就留空",
  "source_title": "来源站点/文章名"
}

要求：
- 举例要像真人在评论区随手打的，不要解释梗本身。
- 不要收已经过气、或者搜索结果里只有一条含糊提及的。
- 只输出 JSON 数组，不要代码块，不要解释。

搜索结果：
${hits.join('\n\n')}
''';

  static List<Map<String, dynamic>> _parse(String raw) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    } catch (error) {
      debugPrint('[知识库] 解析模型结果失败：$error');
      return const [];
    }
  }

  static List<String> _stringList(Object? raw) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
    }
    if (raw is String && raw.trim().isNotEmpty) return [raw.trim()];
    return const [];
  }
}

final knowledgeUpdateServiceProvider = Provider<KnowledgeUpdateService>(
  (ref) => KnowledgeUpdateService(
    repository: ref.watch(knowledgeRepositoryProvider),
    knowledge: ref.watch(knowledgeServiceProvider),
    search: ref.watch(webSearchServiceProvider),
    gateway: ref.watch(modelGatewayProvider),
  ),
);
