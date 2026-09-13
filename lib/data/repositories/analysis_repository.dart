import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/plan_script.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 客观分析结果的读写（清醒模式独有）。
///
/// 目前唯一的写入方是策划脚本里的「展示客观分析」事件：
/// 到点时把脚本里写好的五项分析落库，分析页读到的就是它。
class AnalysisRepository {
  const AnalysisRepository(this._db);

  final AppDatabase _db;

  Future<void> insertFromPlan({
    required String postId,
    required PlanAnalysis analysis,
    String scope = 'clear',
  }) async {
    if (analysis.isEmpty) return;

    await _db
        .into(_db.analysisResults)
        .insert(
          AnalysisResultsCompanion.insert(
            id: 'analysis_${postId}_${DateTime.now().microsecondsSinceEpoch}',
            postId: postId,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            imageDescription: Value(analysis.imageDescription),
            emotionAnalysis: Value(analysis.emotionAnalysis),
            logicAnalysis: Value(analysis.logicAnalysis),
            factCheck: Value(analysis.factCheck),
            suggestions: Value(analysis.suggestions),
            scope: Value(scope),
          ),
        );
  }

  Future<AnalysisResultRow?> findByPost(String postId) async {
    final query = _db.select(_db.analysisResults)
      ..where((t) => t.postId.equals(postId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(1);
    return query.getSingleOrNull();
  }

  Stream<AnalysisResultRow?> watchByPost(String postId) {
    final query = _db.select(_db.analysisResults)
      ..where((t) => t.postId.equals(postId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(1);
    return query.watchSingleOrNull();
  }
}

final analysisRepositoryProvider = Provider<AnalysisRepository>(
  (ref) => AnalysisRepository(ref.watch(databaseProvider)),
);
