import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/resident_sleep.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 固定住民的睡眠记录。
///
/// 只在这一张表里回答“现在是不是在睡、上一次睡到什么时候”；
/// 谁该睡、什么时候唤醒由 `ResidentSleepService` 决定。
class ResidentSleepRepository {
  ResidentSleepRepository(this._db);

  final AppDatabase _db;
  static final Random _rand = Random();

  String _newId() =>
      'sleep_${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 20)}';

  Future<ResidentSleepPeriod?> current(String residentId) async {
    final row =
        await (_db.select(_db.residentSleepPeriods)
              ..where(
                (t) => t.residentId.equals(residentId) & t.endedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Future<bool> isSleeping(String residentId) async =>
      await current(residentId) != null;

  Future<List<ResidentSleepPeriod>> sleeping() async {
    final rows =
        await (_db.select(_db.residentSleepPeriods)
              ..where((t) => t.endedAt.isNull())
              ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
            .get();
    return rows.map(_toDomain).toList(growable: false);
  }

  Stream<List<ResidentSleepPeriod>> watchSleeping() {
    final query = _db.select(_db.residentSleepPeriods)
      ..where((t) => t.endedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  Future<List<ResidentSleepPeriod>> periodsFor(
    String residentId, {
    int limit = 30,
  }) async {
    final rows =
        await (_db.select(_db.residentSleepPeriods)
              ..where((t) => t.residentId.equals(residentId))
              ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
              ..limit(limit))
            .get();
    return rows.map(_toDomain).toList(growable: false);
  }

  Stream<List<ResidentSleepPeriod>> watchPeriodsFor(
    String residentId, {
    int limit = 30,
  }) {
    final query = _db.select(_db.residentSleepPeriods)
      ..where((t) => t.residentId.equals(residentId))
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
      ..limit(limit);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  /// 开始一段睡眠。已经在睡就返回当前那段，不重复写。
  Future<ResidentSleepPeriod> start({
    required String residentId,
    required String startedBy,
    DateTime? at,
  }) async {
    final existing = await current(residentId);
    if (existing != null) return existing;
    final when = at ?? DateTime.now();
    final id = _newId();
    await _db.into(_db.residentSleepPeriods).insert(
      ResidentSleepPeriodsCompanion.insert(
        id: id,
        residentId: residentId,
        startedAt: when.millisecondsSinceEpoch,
        startedBy: Value(startedBy),
      ),
    );
    return (await current(residentId))!;
  }

  /// 结束当前这段睡眠；不在睡就返回 null。
  Future<ResidentSleepPeriod?> wake(
    String residentId, {
    required String endedBy,
    DateTime? at,
  }) async {
    final existing = await current(residentId);
    if (existing == null) return null;
    final when = at ?? DateTime.now();
    await (_db.update(_db.residentSleepPeriods)..where(
          (t) => t.id.equals(existing.id) & t.endedAt.isNull(),
        ))
        .write(
          ResidentSleepPeriodsCompanion(
            endedAt: Value(when.millisecondsSinceEpoch),
            endedBy: Value(endedBy),
          ),
        );
    return (await _findById(existing.id))!;
  }

  Future<void> setFarewell(String id, String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    await (_db.update(_db.residentSleepPeriods)
          ..where((t) => t.id.equals(id)))
        .write(ResidentSleepPeriodsCompanion(farewell: Value(clean)));
  }

  Future<ResidentSleepPeriod?> _findById(String id) async {
    final row =
        await (_db.select(_db.residentSleepPeriods)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  ResidentSleepPeriod _toDomain(ResidentSleepPeriodRow row) =>
      ResidentSleepPeriod(
        id: row.id,
        residentId: row.residentId,
        startedAt: DateTime.fromMillisecondsSinceEpoch(row.startedAt),
        endedAt: row.endedAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row.endedAt!),
        startedBy: row.startedBy,
        endedBy: row.endedBy,
        farewell: row.farewell,
      );
}

final residentSleepRepositoryProvider = Provider<ResidentSleepRepository>(
  (ref) => ResidentSleepRepository(ref.watch(databaseProvider)),
);

final sleepingResidentsProvider =
    StreamProvider<List<ResidentSleepPeriod>>(
      (ref) => ref.watch(residentSleepRepositoryProvider).watchSleeping(),
    );

final residentSleepPeriodsProvider = StreamProvider.autoDispose
    .family<List<ResidentSleepPeriod>, String>(
      (ref, residentId) => ref
          .watch(residentSleepRepositoryProvider)
          .watchPeriodsFor(residentId),
    );

final residentSleepStateProvider = StreamProvider.autoDispose
    .family<ResidentSleepPeriod?, String>(
      (ref, residentId) => ref
          .watch(residentSleepRepositoryProvider)
          .watchPeriodsFor(residentId, limit: 1)
          .map((list) => list.isEmpty ? null : list.first),
    );
