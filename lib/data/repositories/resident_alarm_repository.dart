import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/resident_alarm.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 固定住民的闹钟（v4.0）。
///
/// 它只回答“什么时候该叫醒谁”，不替调度器做决定：
/// 前台心跳和后台任务都来问 [due]，到点的那一条被消费一次就不再出现。
class ResidentAlarmRepository {
  ResidentAlarmRepository(this._db);

  final AppDatabase _db;
  static final Random _rand = Random();

  /// 一位住民同时最多留几个未到点闹钟。
  static const int maxPending = 5;

  /// 最短 / 最长：太短会在同一分钟里反复醒，太长就不像“定个闹钟”了。
  static const Duration minLead = Duration(minutes: 5);
  static const Duration maxLead = Duration(days: 30);

  Future<String> schedule({
    required String residentId,
    required DateTime fireAt,
    String reason = '',
  }) async {
    final id =
        'alarm_${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 20)}';
    await _db.into(_db.residentAlarms).insert(
      ResidentAlarmsCompanion.insert(
        id: id,
        residentId: residentId,
        fireAt: fireAt.millisecondsSinceEpoch,
        reason: Value(reason.trim()),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    return id;
  }

  Future<List<ResidentAlarm>> pending(
    String residentId, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final rows =
        await (_db.select(_db.residentAlarms)
              ..where(
                (t) =>
                    t.residentId.equals(residentId) &
                    t.firedAt.isNull() &
                    t.cancelledAt.isNull() &
                    t.fireAt.isBiggerThanValue(at.millisecondsSinceEpoch),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.fireAt)]))
            .get();
    return rows.map(_toDomain).toList(growable: false);
  }

  Future<ResidentAlarm?> next(String residentId, {DateTime? now}) async {
    final list = await pending(residentId, now: now);
    return list.isEmpty ? null : list.first;
  }

  Future<bool> hasUpcoming(String residentId, {DateTime? now}) async =>
      await next(residentId, now: now) != null;

  /// 所有到点、还没触发也没取消的闹钟（按时间先后）。
  Future<List<ResidentAlarm>> due({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final rows =
        await (_db.select(_db.residentAlarms)
              ..where(
                (t) =>
                    t.firedAt.isNull() &
                    t.cancelledAt.isNull() &
                    t.fireAt.isSmallerOrEqualValue(
                      at.millisecondsSinceEpoch,
                    ),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.fireAt)]))
            .get();
    return rows.map(_toDomain).toList(growable: false);
  }

  /// 消费掉一个闹钟。返回 false 说明它已经被别人（或上一次心跳）处理过了。
  Future<bool> markFired(String id, {DateTime? at}) async {
    final now = at ?? DateTime.now();
    final affected =
        await (_db.update(_db.residentAlarms)..where(
              (t) =>
                  t.id.equals(id) &
                  t.firedAt.isNull() &
                  t.cancelledAt.isNull(),
            ))
            .write(
              ResidentAlarmsCompanion(
                firedAt: Value(now.millisecondsSinceEpoch),
              ),
            );
    return affected > 0;
  }

  Future<bool> cancel(String id, String residentId, {DateTime? at}) async {
    final now = at ?? DateTime.now();
    final affected =
        await (_db.update(_db.residentAlarms)..where(
              (t) =>
                  t.id.equals(id) &
                  t.residentId.equals(residentId) &
                  t.firedAt.isNull() &
                  t.cancelledAt.isNull(),
            ))
            .write(
              ResidentAlarmsCompanion(
                cancelledAt: Value(now.millisecondsSinceEpoch),
              ),
            );
    return affected > 0;
  }

  Future<int> cancelAll(String residentId, {DateTime? at}) async {
    final now = at ?? DateTime.now();
    return (_db.update(
      _db.residentAlarms,
    )..where(
      (t) =>
          t.residentId.equals(residentId) &
          t.firedAt.isNull() &
          t.cancelledAt.isNull(),
    )).write(
      ResidentAlarmsCompanion(cancelledAt: Value(now.millisecondsSinceEpoch)),
    );
  }

  /// 住民编辑页 / 日志页用：还没响的闹钟，按时间正序。
  ///
  /// 不按“现在”过滤：正好到点、还没被心跳消费的那一条也该显示出来，
  /// 而不是在页面打开的那一秒凭空消失。
  Stream<List<ResidentAlarm>> watchUpcoming(String residentId) {
    final query = _db.select(_db.residentAlarms)
      ..where(
        (t) =>
            t.residentId.equals(residentId) &
            t.firedAt.isNull() &
            t.cancelledAt.isNull(),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.fireAt)]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  ResidentAlarm _toDomain(ResidentAlarmRow row) => ResidentAlarm(
    id: row.id,
    residentId: row.residentId,
    fireAt: DateTime.fromMillisecondsSinceEpoch(row.fireAt),
    reason: row.reason,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    firedAt: row.firedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.firedAt!),
    cancelledAt: row.cancelledAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.cancelledAt!),
  );
}

/// 把工具里的一句话（`90` / `2h` / `21:30` / `2026-10-29 08:00`）
/// 解析成绝对时间。解析不了或超出范围就返回 null，由工具把原因交回模型。
///
/// 纯函数，方便测试。
DateTime? parseAlarmWhen(
  String raw, {
  DateTime? now,
  Duration minLead = ResidentAlarmRepository.minLead,
  Duration maxLead = ResidentAlarmRepository.maxLead,
}) {
  final at = now ?? DateTime.now();
  final text = raw.trim();
  if (text.isEmpty) return null;

  DateTime? candidate;
  final minutes = RegExp(r'^(\d{1,5})$').firstMatch(text);
  if (minutes != null) {
    candidate = at.add(Duration(minutes: int.parse(minutes.group(1)!)));
  } else {
    final shorthand = RegExp(
      r'^(\d{1,4})\s*([mh])$',
      caseSensitive: false,
    ).firstMatch(text);
    if (shorthand != null) {
      final value = int.parse(shorthand.group(1)!);
      candidate = at.add(
        shorthand.group(2)!.toLowerCase() == 'h'
            ? Duration(hours: value)
            : Duration(minutes: value),
      );
    } else {
      final hm = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
      if (hm != null) {
        final hour = int.parse(hm.group(1)!);
        final minute = int.parse(hm.group(2)!);
        if (hour > 23 || minute > 59) return null;
        candidate = DateTime(at.year, at.month, at.day, hour, minute);
        if (!candidate.isAfter(at)) {
          candidate = candidate.add(const Duration(days: 1));
        }
      } else {
        final full = RegExp(
          r'^(\d{4})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{2})$',
        ).firstMatch(text);
        if (full != null) {
          final year = int.parse(full.group(1)!);
          final month = int.parse(full.group(2)!);
          final day = int.parse(full.group(3)!);
          final hour = int.parse(full.group(4)!);
          final minute = int.parse(full.group(5)!);
          if (month < 1 || month > 12 || day < 1 || day > 31) return null;
          if (hour > 23 || minute > 59) return null;
          candidate = DateTime(year, month, day, hour, minute);
        }
      }
    }
  }

  if (candidate == null) return null;
  final lead = candidate.difference(at);
  if (lead < minLead || lead > maxLead) return null;
  return candidate;
}

final residentAlarmRepositoryProvider = Provider<ResidentAlarmRepository>(
  (ref) => ResidentAlarmRepository(ref.watch(databaseProvider)),
);

/// 某位住民还没响的闹钟（日志页 / 编辑页）。
final residentAlarmsProvider = StreamProvider.autoDispose
    .family<List<ResidentAlarm>, String>(
      (ref, residentId) =>
          ref.watch(residentAlarmRepositoryProvider).watchUpcoming(residentId),
    );
