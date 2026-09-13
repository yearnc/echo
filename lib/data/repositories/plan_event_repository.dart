import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/plan_script.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 一条已经算出绝对时间的策划事件。
class PlannedPlanEvent {
  const PlannedPlanEvent({required this.step, required this.atMs});

  final PlanStep step;

  /// 发帖时刻 + 脚本里的秒数。
  final int atMs;
}

/// 策划事件队列的读写。
class PlanEventRepository {
  const PlanEventRepository(this._db);

  final AppDatabase _db;

  static const String statusPending = 'pending';
  static const String statusDone = 'done';

  Future<void> insertAll({
    required String postId,
    required String scriptId,
    required List<PlannedPlanEvent> events,
  }) async {
    if (events.isEmpty) return;

    final rows = <PlanEventsCompanion>[];
    for (var i = 0; i < events.length; i++) {
      final step = events[i].step;
      rows.add(
        PlanEventsCompanion.insert(
          id: 'plan_${postId}_$i',
          postId: postId,
          type: step.type,
          scheduledAt: events[i].atMs,
          scriptId: Value(scriptId),
          personaId: Value(step.personaId),
          mediaType: Value(step.mediaType),
          content: Value(step.content),
          voiceAsset: Value(step.voiceAsset),
          transcript: Value(step.transcript),
          delta: Value(step.delta),
          likes: Value(step.likes),
          comments: Value(step.comments),
          toMode: Value(step.toMode),
          analysisJson: Value(
            step.analysis == null ? null : jsonEncode(step.analysis!.toJson()),
          ),
        ),
      );
    }

    await _db.batch((batch) => batch.insertAll(_db.planEvents, rows));
  }

  /// 到点该执行的策划事件。
  Future<List<PlanEventRow>> duePending(DateTime now) async {
    final query = _db.select(_db.planEvents)
      ..where(
        (t) =>
            t.status.equals(statusPending) &
            t.scheduledAt.isSmallerOrEqualValue(now.millisecondsSinceEpoch),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.scheduledAt)]);
    return query.get();
  }

  /// 还有多少条没执行（心跳靠它决定要不要跑秒级）。
  Future<int> countPending() async {
    final count = _db.planEvents.id.count();
    final query = _db.selectOnly(_db.planEvents)
      ..addColumns([count])
      ..where(_db.planEvents.status.equals(statusPending));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> markExecuted(String id) async {
    await (_db.update(_db.planEvents)..where((t) => t.id.equals(id))).write(
      PlanEventsCompanion(
        status: const Value(statusDone),
        executedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 取消所有还没执行的策划事件（切到清醒模式时用）。
  Future<int> cancelAllPending() async {
    return (_db.update(_db.planEvents)
          ..where((t) => t.status.equals(statusPending)))
        .write(const PlanEventsCompanion(status: Value('cancelled')));
  }

  /// 取消一条帖子上还没执行的策划事件（删除帖子/放弃拍摄时用）。
  Future<void> cancelForPost(String postId) async {
    await (_db.update(_db.planEvents)..where(
          (t) => t.postId.equals(postId) & t.status.equals(statusPending),
        ))
        .write(const PlanEventsCompanion(status: Value('cancelled')));
  }
}

final planEventRepositoryProvider = Provider<PlanEventRepository>(
  (ref) => PlanEventRepository(ref.watch(databaseProvider)),
);
