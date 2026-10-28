import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/resident_wake_log.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 固定住民的唤醒日志（v3.9）。
///
/// 只在**真正醒来**之后写：没有对话模型、这一轮压根没跑起来的不记，
/// 否则日志里全是“醒了但什么也没做”的空条目。
class ResidentWakeLogRepository {
  const ResidentWakeLogRepository(this._db);

  final AppDatabase _db;

  /// 用户连续发消息时，这一段时间内的几次唤醒算同一次对话。
  ///
  /// 以前每发一句就记一条日志，几分钟里能出现三四条“有人叫了 TA”，
  /// 看起来像在刷屏。合并成一条之后，日志才是“聊了一会儿”，
  /// 而不是“被戳了三下”。只合并 user_action，不碰心跳和后台。
  static const Duration coalesceWindow = Duration(minutes: 10);

  /// 记一次醒来。id 直接用这一轮的 wakeId，工具里能对上。
  Future<void> start({
    required String id,
    required String residentId,
    required String trigger,
    required DateTime at,
  }) async {
    await _db
        .into(_db.residentWakeLogs)
        .insertOnConflictUpdate(
          ResidentWakeLogsCompanion.insert(
            id: id,
            residentId: residentId,
            trigger: trigger,
            wokeAt: at.millisecondsSinceEpoch,
          ),
        );
  }

  /// 最近一条“有人叫了 TA”的日志，且结束在合并窗口内。
  ///
  /// 返回它就是要把新的这一轮并进去，而不是再插一条。
  Future<ResidentWakeLog?> reusableUserWake(
    String residentId, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final row =
        await (_db.select(_db.residentWakeLogs)
              ..where((t) => t.residentId.equals(residentId))
              ..orderBy([(t) => OrderingTerm.desc(t.wokeAt)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null || row.trigger != 'user_action') return null;
    final last = DateTime.fromMillisecondsSinceEpoch(row.endedAt ?? row.wokeAt);
    if (at.difference(last) > coalesceWindow) return null;
    return _toDomain(row);
  }

  /// 把一条已经结束的日志重新打开：新的这一轮并进去，结束时统一算时长。
  Future<void> reopen(String id) async {
    await (_db.update(
      _db.residentWakeLogs,
    )..where((t) => t.id.equals(id))).write(
      const ResidentWakeLogsCompanion(endedAt: Value(null)),
    );
  }

  /// 记下一个工具调用。
  ///
  /// 连续两次同名只留一次（例如一口气发三段私信，页面上“发私信”一条就够）；
  /// 中间隔着别的工具则各自保留，顺序就是说事的顺序。
  Future<void> recordTool(String id, String name) async {
    final tool = name.trim();
    if (tool.isEmpty) return;
    final row = await (_db.select(
      _db.residentWakeLogs,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;

    final tools = _tools(row.tools);
    if (tools.isNotEmpty && tools.last == tool) return;
    tools.add(tool);
    await (_db.update(
      _db.residentWakeLogs,
    )..where((t) => t.id.equals(id))).write(
      ResidentWakeLogsCompanion(tools: Value(jsonEncode(tools))),
    );
  }

  /// 这一轮结束（成功、失败都记），日志页才能算出醒了多久。
  Future<void> finish(String id, {required DateTime at}) async {
    await (_db.update(
      _db.residentWakeLogs,
    )..where((t) => t.id.equals(id))).write(
      ResidentWakeLogsCompanion(endedAt: Value(at.millisecondsSinceEpoch)),
    );
  }

  /// 最近一条留给“下一次”的留言。排除当前这一轮。
  Future<ResidentWakeLog?> lastNote(
    String residentId, {
    String? excludeId,
  }) async {
    final query = _db.select(_db.residentWakeLogs)
      ..where(
        (t) =>
            t.residentId.equals(residentId) &
            t.note.isNotValue('') &
            t.noteDeliveredAt.isNull(),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.wokeAt)])
      ..limit(1);
    if (excludeId != null) {
      query.where((t) => t.id.equals(excludeId).not());
    }
    final row = await query.getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  /// 今天（本地时间 0 点之后）醒过几次。
  Future<List<ResidentWakeLog>> today(
    String residentId, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final start = DateTime(at.year, at.month, at.day);
    return _between(residentId, start, start.add(const Duration(days: 1)));
  }

  /// 最近几天（日记用），按时间倒序。
  Future<List<ResidentWakeLog>> recent(
    String residentId, {
    int days = 1,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final start = DateTime(
      at.year,
      at.month,
      at.day,
    ).subtract(Duration(days: (days - 1).clamp(0, 30)));
    return _between(residentId, start, at.add(const Duration(days: 1)));
  }

  Future<List<ResidentWakeLog>> _between(
    String residentId,
    DateTime from,
    DateTime to,
  ) async {
    final rows =
        await (_db.select(_db.residentWakeLogs)
              ..where(
                (t) =>
                    t.residentId.equals(residentId) &
                    t.wokeAt.isBiggerOrEqualValue(from.millisecondsSinceEpoch) &
                    t.wokeAt.isSmallerThanValue(to.millisecondsSinceEpoch),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.wokeAt)]))
            .get();
    return rows.map(_toDomain).toList(growable: false);
  }

  /// 日志页用：全部记录，按时间倒序。
  Stream<List<ResidentWakeLog>> watchAll(String residentId) {
    final query = _db.select(_db.residentWakeLogs)
      ..where((t) => t.residentId.equals(residentId))
      ..orderBy([(t) => OrderingTerm.desc(t.wokeAt)]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  /// 这句话已经交给下一次醒来了，之后不再重复带。
  Future<void> markNoteDelivered(String id) async {
    await (_db.update(
      _db.residentWakeLogs,
    )..where((t) => t.id.equals(id))).write(
      ResidentWakeLogsCompanion(
        noteDeliveredAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 给未来的自己留言。只改这一轮自己的那条。
  Future<bool> setNote(String id, String note) async {
    final text = note.trim();
    if (text.isEmpty) return false;
    final affected =
        await (_db.update(
          _db.residentWakeLogs,
        )..where((t) => t.id.equals(id))).write(
          ResidentWakeLogsCompanion(
            note: Value(text),
            noteAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
    return affected > 0;
  }

  ResidentWakeLog _toDomain(ResidentWakeLogRow row) => ResidentWakeLog(
    id: row.id,
    residentId: row.residentId,
    trigger: row.trigger,
    wokeAt: DateTime.fromMillisecondsSinceEpoch(row.wokeAt),
    endedAt: row.endedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.endedAt!),
    note: row.note,
    noteAt: row.noteAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.noteAt!),
    tools: _tools(row.tools),
  );

  static List<String> _tools(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return [
        for (final item in decoded)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
    } catch (_) {
      return <String>[];
    }
  }
}

final residentWakeLogRepositoryProvider = Provider<ResidentWakeLogRepository>(
  (ref) => ResidentWakeLogRepository(ref.watch(databaseProvider)),
);

/// 某位住民的唤醒日志（日志页）。
final residentWakeLogsProvider = StreamProvider.autoDispose
    .family<List<ResidentWakeLog>, String>(
      (ref, residentId) =>
          ref.watch(residentWakeLogRepositoryProvider).watchAll(residentId),
    );
