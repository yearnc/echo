import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_session.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 前台使用会话的读写（v31）。
///
/// 只记“APP 开着的时间”，不记录任何操作内容。跨天时按自然日拆成多条，
/// 这样“今天用了多久”不用在查询时再做时间切片，也不会因为一次跨夜
/// 把昨天的时长算到今天头上。
class UsageRepository {
  const UsageRepository(this._db);

  final AppDatabase _db;

  static final Random _rand = Random();

  Future<void> logSession({required DateTime start, required DateTime end}) async {
    if (!end.isAfter(start)) return;
    final rows = <UsageSessionsCompanion>[];

    var cursor = start;
    while (cursor.isBefore(end)) {
      final dayEnd = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
      ).add(const Duration(days: 1));
      final segmentEnd = end.isBefore(dayEnd) ? end : dayEnd;
      final duration = segmentEnd.difference(cursor).inMilliseconds;
      if (duration > 0) {
        rows.add(
          UsageSessionsCompanion.insert(
            id: 'usage_${cursor.microsecondsSinceEpoch}_'
                '${_rand.nextInt(1 << 20)}',
            startedAt: cursor.millisecondsSinceEpoch,
            endedAt: segmentEnd.millisecondsSinceEpoch,
            durationMs: duration,
          ),
        );
      }
      cursor = segmentEnd;
    }

    if (rows.isEmpty) return;
    await _db.batch((batch) => batch.insertAll(_db.usageSessions, rows));
  }

  /// [since] 之后的总时长（毫秒）。
  Future<int> totalMsSince(DateTime since) async {
    final total = _db.usageSessions.durationMs.sum();
    final query = _db.selectOnly(_db.usageSessions)
      ..addColumns([total])
      ..where(
        _db.usageSessions.startedAt.isBiggerOrEqualValue(
          since.millisecondsSinceEpoch,
        ),
      );
    final row = await query.getSingle();
    return row.read(total) ?? 0;
  }

  /// 今天零点以来的总时长（毫秒）。
  Future<int> todayMs() {
    final now = DateTime.now();
    return totalMsSince(DateTime(now.year, now.month, now.day));
  }

  Future<List<UsageSessionRow>> all() {
    final query = _db.select(_db.usageSessions)
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    return query.get();
  }

  Future<int> deleteAll() => _db.delete(_db.usageSessions).go();
}

final usageRepositoryProvider = Provider<UsageRepository>(
  (ref) => UsageRepository(ref.watch(databaseProvider)),
);

/// 今天用了多久（分钟）：已落库的部分 + 正在进行的这段前台会话。
final todayUsageMinutesProvider = FutureProvider.autoDispose<int>((ref) async {
  final ms = await ref.watch(usageRepositoryProvider).todayMs();
  return ((ms + AppSession.foregroundMsToday) / 60000).round();
});
