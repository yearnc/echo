import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/clear_insight.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 清醒分析快照的读写。
///
/// 只保留最新一版用于展示；旧快照不删（它们是用户数据的一部分，导出时要用）。
class ClearInsightRepository {
  const ClearInsightRepository(this._db);

  final AppDatabase _db;

  static final Random _rand = Random();

  Future<ClearInsight> save(ClearInsight insight) async {
    await _db
        .into(_db.clearInsights)
        .insert(
          ClearInsightsCompanion.insert(
            id: 'insight_${DateTime.now().microsecondsSinceEpoch}_'
                '${_rand.nextInt(1 << 20)}',
            periodStart: insight.periodStart.millisecondsSinceEpoch,
            periodEnd: insight.periodEnd.millisecondsSinceEpoch,
            generatedAt: insight.generatedAt.millisecondsSinceEpoch,
            payload: insight.encodePayload(),
            summary: Value(insight.summary),
            source: Value(insight.source),
          ),
        );
    return insight;
  }

  Stream<ClearInsight?> watchLatest() {
    final query = _db.select(_db.clearInsights)
      ..where((t) => t.scope.equals('clear'))
      ..orderBy([(t) => OrderingTerm.desc(t.generatedAt)])
      ..limit(1);
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : _toDomain(row),
    );
  }

  Future<ClearInsight?> latest() async {
    final query = _db.select(_db.clearInsights)
      ..where((t) => t.scope.equals('clear'))
      ..orderBy([(t) => OrderingTerm.desc(t.generatedAt)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Future<List<ClearInsight>> all() async {
    final query = _db.select(_db.clearInsights)
      ..where((t) => t.scope.equals('clear'))
      ..orderBy([(t) => OrderingTerm.desc(t.generatedAt)]);
    return (await query.get()).map(_toDomain).toList(growable: false);
  }

  Future<int> deleteAll() =>
      _db.delete(_db.clearInsights).go();

  ClearInsight _toDomain(ClearInsightRow row) => ClearInsight(
    generatedAt: DateTime.fromMillisecondsSinceEpoch(row.generatedAt),
    periodStart: DateTime.fromMillisecondsSinceEpoch(row.periodStart),
    periodEnd: DateTime.fromMillisecondsSinceEpoch(row.periodEnd),
    summary: row.summary,
    source: row.source,
    metrics: ClearInsight.decodePayload(row.payload),
  );
}

final clearInsightRepositoryProvider = Provider<ClearInsightRepository>(
  (ref) => ClearInsightRepository(ref.watch(databaseProvider)),
);

final latestClearInsightProvider = StreamProvider<ClearInsight?>(
  (ref) => ref.watch(clearInsightRepositoryProvider).watchLatest(),
);
