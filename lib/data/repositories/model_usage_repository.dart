import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/model_call_common.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 某个时间段的缓存用量汇总。
class ModelUsageSummary {
  const ModelUsageSummary({
    required this.calls,
    required this.promptTokens,
    required this.cachedTokens,
    required this.cacheWriteTokens,
    required this.completionTokens,
    this.byModel = const [],
  });

  final int calls;
  final int promptTokens;
  final int cachedTokens;
  final int cacheWriteTokens;
  final int completionTokens;
  final List<ModelUsageBreakdown> byModel;

  bool get hasData => calls > 0;

  /// 缓存命中率：命中 / 输入。服务商不同，这个口径也会有细微差别，
  /// 但“有没有在命中”一眼能看出来。
  int get cacheHitRate => promptTokens == 0
      ? 0
      : (cachedTokens / promptTokens * 100).clamp(0, 100).round();

  static const ModelUsageSummary empty = ModelUsageSummary(
    calls: 0,
    promptTokens: 0,
    cachedTokens: 0,
    cacheWriteTokens: 0,
    completionTokens: 0,
  );
}

class ModelUsageBreakdown {
  const ModelUsageBreakdown({
    required this.model,
    required this.calls,
    required this.promptTokens,
    required this.cachedTokens,
    required this.cacheWriteTokens,
    required this.completionTokens,
  });

  final String model;
  final int calls;
  final int promptTokens;
  final int cachedTokens;
  final int cacheWriteTokens;
  final int completionTokens;

  int get cacheHitRate => promptTokens == 0
      ? 0
      : (cachedTokens / promptTokens * 100).clamp(0, 100).round();
}

/// 模型用量的本地聚合。
///
/// 只记录 token 计数，不记录任何消息正文。按“天 + 模型”一行，
/// 不逐次保存，所以数据库不会因为聊天多而膨胀。
class ModelUsageRepository {
  const ModelUsageRepository(this._db);

  final AppDatabase _db;

  Future<void> record({
    required String model,
    required ModelUsage usage,
  }) async {
    if (!usage.hasData) return;
    final now = DateTime.now();
    final day = _dayOf(now);
    final id = '$day|$model';
    await _db.customStatement(
      '''
INSERT INTO model_usage_daily
  (id, day, model, calls, prompt_tokens, cached_tokens, cache_write_tokens,
   completion_tokens, updated_at)
VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  calls = calls + excluded.calls,
  prompt_tokens = prompt_tokens + excluded.prompt_tokens,
  cached_tokens = cached_tokens + excluded.cached_tokens,
  cache_write_tokens = cache_write_tokens + excluded.cache_write_tokens,
  completion_tokens = completion_tokens + excluded.completion_tokens,
  updated_at = excluded.updated_at
''',
      [
        id,
        day,
        model,
        usage.promptTokens,
        usage.cachedTokens,
        usage.cacheWriteTokens,
        usage.completionTokens,
        now.millisecondsSinceEpoch,
      ],
    );
    // 只留最近 90 天，足够看趋势，又不会无限长。
    await _db.customStatement(
      'DELETE FROM model_usage_daily WHERE day < ?',
      [_dayOf(now.subtract(const Duration(days: 90)))],
    );
  }

  Stream<ModelUsageSummary> watchSummary({int days = 1}) {
    final cutoff = _dayOf(
      DateTime.now().subtract(Duration(days: days.clamp(1, 90) - 1)),
    );
    return (_db.select(_db.modelUsageDaily)
          ..where((t) => t.day.isBiggerOrEqualValue(cutoff))
          ..orderBy([(t) => OrderingTerm.asc(t.day)]))
        .watch()
        .map(_summarize);
  }

  Future<ModelUsageSummary> summary({int days = 1}) async {
    final cutoff = _dayOf(
      DateTime.now().subtract(Duration(days: days.clamp(1, 90) - 1)),
    );
    final rows =
        await (_db.select(_db.modelUsageDaily)
              ..where((t) => t.day.isBiggerOrEqualValue(cutoff)))
            .get();
    return _summarize(rows);
  }

  static ModelUsageSummary _summarize(List<ModelUsageDailyRow> rows) {
    if (rows.isEmpty) return ModelUsageSummary.empty;
    var calls = 0;
    var prompt = 0;
    var cached = 0;
    var cacheWrite = 0;
    var completion = 0;
    final byModel = <String, List<int>>{};
    for (final row in rows) {
      calls += row.calls;
      prompt += row.promptTokens;
      cached += row.cachedTokens;
      cacheWrite += row.cacheWriteTokens;
      completion += row.completionTokens;
      final bucket = byModel.putIfAbsent(row.model, () => List<int>.filled(5, 0));
      bucket[0] += row.calls;
      bucket[1] += row.promptTokens;
      bucket[2] += row.cachedTokens;
      bucket[3] += row.cacheWriteTokens;
      bucket[4] += row.completionTokens;
    }
    final models = [
      for (final entry in byModel.entries)
        ModelUsageBreakdown(
          model: entry.key,
          calls: entry.value[0],
          promptTokens: entry.value[1],
          cachedTokens: entry.value[2],
          cacheWriteTokens: entry.value[3],
          completionTokens: entry.value[4],
        ),
    ]..sort((a, b) => b.promptTokens.compareTo(a.promptTokens));
    return ModelUsageSummary(
      calls: calls,
      promptTokens: prompt,
      cachedTokens: cached,
      cacheWriteTokens: cacheWrite,
      completionTokens: completion,
      byModel: models,
    );
  }

  static String _dayOf(DateTime at) =>
      '${at.year.toString().padLeft(4, '0')}-'
      '${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';
}

final modelUsageRepositoryProvider = Provider<ModelUsageRepository>((ref) {
  return ModelUsageRepository(ref.watch(databaseProvider));
});

final modelUsageSummaryProvider =
    StreamProvider.autoDispose.family<ModelUsageSummary, int>((ref, days) {
      return ref.watch(modelUsageRepositoryProvider).watchSummary(days: days);
    });
