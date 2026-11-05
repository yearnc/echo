import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/knowledge_repository.dart';
import '../models/knowledge.dart';

/// 知识库往提示词里放什么、怎么放（v4.11）。
///
/// 缓存是硬约束：
/// - 临时网民按**知识库分组**生成稳定的 system 前缀，帖子内容仍放 user；
///   同一本册子跨帖复用，换人不用换前缀。
/// - 固定住民只注入索引（标题 + 一句话），详情走 `knowledge_search`。
/// - 块里**不放"更新于几分钟前"**这类会动的东西；时间只留在 user 末尾。
///
/// 过期条目不注入：热门梗烂得比想象中快，留着只会让模型硬套。
class KnowledgeService {
  KnowledgeService(this._repository);

  final KnowledgeRepository _repository;

  /// 临时网民一次带几条完整内容。再多会把 system 撑大，
  /// 而且一屏评论根本用不完。
  static const int transientEntryLimit = 6;

  /// 固定住民只带索引；详情按需查。
  static const int residentIndexLimit = 20;

  /// 自动抓取的梗 30 天过期。主人手动写的不设期限。
  static const Duration trendTtl = Duration(days: 30);

  final Map<String, _CachedBlock> _transientCache = {};
  final Map<String, _CachedBlock> _residentCache = {};

  // —— 临时网民 ——

  Future<List<KnowledgeBase>> transientBases() =>
      _repository.transientBases();

  /// 一本册子的稳定 system 片段。没有可用条目时返回空串。
  Future<String> transientBlock(KnowledgeBase base) async {
    final cached = _transientCache[base.id];
    if (cached != null && cached.stamp == base.updatedAt) {
      return cached.block;
    }
    final entries = await _repository.listEntries(base.id);
    final block = _buildTransientBlock(base, entries);
    _transientCache[base.id] = _CachedBlock(base.updatedAt, block);
    return block;
  }

  String _buildTransientBlock(
    KnowledgeBase base,
    List<KnowledgeEntry> entries,
  ) {
    if (entries.isEmpty) return '';
    final picked = entries.take(transientEntryLimit).toList(growable: false);
    final buffer = StringBuffer()
      ..writeln('【你这次带着的册子：《${base.name}》】');
    if (base.description.trim().isNotEmpty) {
      buffer.writeln(base.description.trim());
    }
    for (final entry in picked) {
      buffer.writeln(entry.toPromptBlock());
    }
    if (entries.length > picked.length) {
      buffer.writeln(
        '（册子里还有 ${entries.length - picked.length} 条，这次用不上就算了。）',
      );
    }
    buffer.write(
      '这些是素材，不是口癖：用得上的时候接一句，用不上就当没看见。'
      '不要解释梗，不要把来源链接写进评论，也不要为了用梗而硬套。',
    );
    return buffer.toString();
  }

  // —— 固定住民 ——

  Future<List<KnowledgeBase>> residentBases(String residentId) =>
      _repository.residentBases(residentId);

  /// 住民 system 里的索引块。按库分组，不加时间戳。
  Future<String> residentBlock(String residentId) async {
    final bases = await _repository.residentBases(residentId);
    if (bases.isEmpty) return '';
    final stamp = _stampFor(bases);
    final cached = _residentCache[residentId];
    if (cached != null && cached.stamp == stamp) return cached.block;

    final buffer = StringBuffer()..writeln('【你手边的知识库】');
    for (final base in bases) {
      final entries = await _repository.listEntries(base.id);
      if (entries.isEmpty) continue;
      buffer.writeln(
        '《${base.name}》[${base.id}] ${base.description.trim()}',
      );
      for (final entry in entries.take(residentIndexLimit)) {
        buffer.writeln(
          '- [${entry.id}] ${entry.title}'
          '${entry.summary.trim().isEmpty ? '' : '：${entry.summary.trim()}'}',
        );
      }
      if (entries.length > residentIndexLimit) {
        buffer.writeln('（其余 ${entries.length - residentIndexLimit} 条用 knowledge_search 查。）');
      }
    }
    buffer.write(
      '这些是你知道的东西，不是必须说出口的话题。'
      '需要细节时用 knowledge_search；听到值得记下的新东西，'
      '可以用 knowledge_write 记进你能看到的知识库。',
    );
    final block = buffer.toString();
    _residentCache[residentId] = _CachedBlock(stamp, block);
    return block;
  }

  int _stampFor(List<KnowledgeBase> bases) {
    var stamp = 17;
    for (final base in bases) {
      stamp = Object.hash(stamp, base.id, base.updatedAt);
    }
    return stamp;
  }

  /// 知识库改了以后主动丢掉缓存；上下文窗口那边另有失效逻辑。
  void invalidate({String? baseId, String? residentId}) {
    if (baseId != null) _transientCache.remove(baseId);
    if (residentId != null) _residentCache.remove(residentId);
    if (baseId == null && residentId == null) {
      _transientCache.clear();
      _residentCache.clear();
    }
  }

  // —— 工具用的检索与写入 ——

  /// 只在这位住民能看到的库里找。返回结果已按相关度排好。
  Future<List<KnowledgeEntry>> search({
    required String residentId,
    required String query,
    int limit = 5,
    String baseId = '',
  }) async {
    final text = query.trim().toLowerCase();
    final visible = await _repository.residentBases(residentId);
    final bases = baseId.trim().isEmpty
        ? visible
        : visible.where((base) => base.id == baseId.trim()).toList();
    final baseNames = {for (final base in bases) base.id: base.name};
    final scored = <(int, KnowledgeEntry)>[];
    for (final base in bases) {
      final entries = await _repository.listEntries(base.id);
      for (final entry in entries) {
        final score = _score(entry, text);
        if (score > 0) scored.add((score, entry));
      }
    }
    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      return byScore != 0 ? byScore : a.$2.id.compareTo(b.$2.id);
    });
    debugPrint(
      '[知识库] $residentId 检索“$query”：'
      '${scored.length} 条命中，库=${baseNames.values.join('、')}',
    );
    return [for (final item in scored.take(limit.clamp(1, 20))) item.$2];
  }

  static int _score(KnowledgeEntry entry, String query) {
    if (query.isEmpty) return 1;
    var score = 0;
    if (entry.title.toLowerCase().contains(query)) score += 6;
    for (final tag in entry.tags) {
      if (query.contains(tag.toLowerCase()) || tag.toLowerCase().contains(query)) {
        score += 4;
      }
    }
    if (entry.summary.toLowerCase().contains(query)) score += 2;
    if (entry.content.toLowerCase().contains(query)) score += 1;
    return score;
  }

  /// 住民写入知识库。只能写进自己看得到的库；内置热门梗库也允许补条目。
  Future<KnowledgeEntry> write({
    required String residentId,
    required String baseId,
    required String title,
    String summary = '',
    String content = '',
    List<String> examples = const [],
    List<String> tags = const [],
    String sourceUrl = '',
    String sourceTitle = '',
    String entryId = '',
  }) async {
    final bases = await _repository.residentBases(residentId);
    final base = bases.where((item) => item.id == baseId).firstOrNull;
    if (base == null) {
      throw ArgumentError('这位住民看不到知识库 $baseId');
    }
    final now = DateTime.now();
    final existing = entryId.trim().isEmpty
        ? null
        : await _repository.findEntry(entryId.trim());
    if (existing != null && existing.baseId != baseId) {
      throw ArgumentError('条目不属于这个知识库');
    }
    final entry = KnowledgeEntry(
      id: existing?.id ?? '',
      baseId: baseId,
      title: title,
      summary: summary,
      content: content,
      examples: examples,
      tags: tags,
      sourceUrl: sourceUrl,
      sourceTitle: sourceTitle,
      verifiedAt: now.millisecondsSinceEpoch,
      // 自动更新的库（热门梗）里的新条目带 TTL；普通库不过期。
      expiresAt: base.autoUpdate
          ? now.add(trendTtl).millisecondsSinceEpoch
          : 0,
      createdAt: existing?.createdAt ?? 0,
    );
    await _repository.upsertEntry(entry);
    invalidate(baseId: baseId, residentId: residentId);
    final saved = await _repository.listEntries(baseId);
    return saved.firstWhere(
      (item) => item.title == title.trim(),
      orElse: () => entry,
    );
  }

  /// 自动更新专用：同一标题视为同一条，保留人工补充的内容。
  Future<void> upsertAutoEntry({
    required String baseId,
    required KnowledgeEntry entry,
  }) async {
    final existing = await _repository.listEntries(baseId, includeExpired: true);
    final same = existing.where((item) => item.title.trim() == entry.title.trim());
    final target = same.isEmpty ? null : same.first;
    final now = DateTime.now();
    await _repository.upsertEntry(
      KnowledgeEntry(
        id: target?.id ?? '',
        baseId: baseId,
        title: entry.title,
        summary: entry.summary,
        content: entry.content,
        examples: entry.examples,
        tags: entry.tags,
        sourceUrl: entry.sourceUrl,
        sourceTitle: entry.sourceTitle,
        verifiedAt: now.millisecondsSinceEpoch,
        expiresAt: now.add(trendTtl).millisecondsSinceEpoch,
        createdAt: target?.createdAt ?? 0,
      ),
    );
    invalidate(baseId: baseId);
  }
}

class _CachedBlock {
  const _CachedBlock(this.stamp, this.block);

  final int stamp;
  final String block;
}

final knowledgeServiceProvider = Provider<KnowledgeService>(
  (ref) => KnowledgeService(ref.watch(knowledgeRepositoryProvider)),
);
