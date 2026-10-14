import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 一条已经兑现的互动（看板用）。
class InteractionPoint {
  const InteractionPoint({
    required this.at,
    required this.type,
    required this.likeBatch,
  });

  final DateTime at;

  /// like / comment / follow / message …
  final String type;

  /// type=like 时，这一条代表多少个赞（匿名人群批次可以顶好几个）。
  final int likeBatch;

  bool get isLike => type == 'like';
  bool get isComment => type == 'comment';
}

/// 数据看板要读的几样东西（B9，规划书 §3.10）。
///
/// 只往外拿**原始的点**，不做任何聚合：分桶、求和、算环比都交给
/// `DashboardStats` 那组纯函数去做。理由很实在——SQL 里算错一个
/// `GROUP BY`，页面上是一条看着挺像回事的假曲线，而且没人看得出。
class DashboardRepository {
  const DashboardRepository(this._db);

  final AppDatabase _db;

  static const String statusDone = 'done';

  /// 我自己发的帖子（住民的动态不算——那不是我发的）。
  Future<List<DateTime>> myPostTimes({required DateTime since}) async {
    final query = _db.select(_db.posts)
      ..where(
        (t) =>
            t.authorPersonaId.isNull() &
            t.deletedAt.isNull() &
            t.createdAt.isBiggerOrEqualValue(since.millisecondsSinceEpoch),
      );
    final rows = await query.get();
    return [
      for (final row in rows)
        DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    ];
  }

  /// 已经兑现的 AI 互动。排期里那些还没到的（pending）不算——
  /// 看板画的是"发生过什么"，不是"将要发生什么"。
  Future<List<InteractionPoint>> executedInteractions({
    required DateTime since,
  }) async {
    final query = _db.select(_db.aiInteractions)
      ..where(
        (t) =>
            t.status.equals(statusDone) &
            t.executedAt.isBiggerOrEqualValue(since.millisecondsSinceEpoch),
      );
    final rows = await query.get();

    return [
      for (final row in rows)
        if (row.executedAt != null)
          InteractionPoint(
            at: DateTime.fromMillisecondsSinceEpoch(row.executedAt!),
            type: row.type,
            likeBatch: row.likeCount,
          ),
    ];
  }

  /// 关注了我的人（单方面关注 + 互相关注）。
  Future<int> followerCount() async {
    final count = _db.aiRelationships.personaId.count();
    final query = _db.selectOnly(_db.aiRelationships)
      ..addColumns([count])
      ..where(
        _db.aiRelationships.followState.equals('followed') |
            _db.aiRelationships.followState.equals('mutual'),
      );
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// 最近 [since] 之后收到过几条私信（住民主动来敲门）。
  Future<int> receivedMessageCount({required DateTime since}) async {
    final count = _db.privateMessages.id.count();
    final query = _db.selectOnly(_db.privateMessages)
      ..addColumns([count])
      ..where(
        // 只数收到的（in）：自己发出去的不算"有人来找你"。
        _db.privateMessages.direction.equals('in') &
            _db.privateMessages.createdAt.isBiggerOrEqualValue(
              since.millisecondsSinceEpoch,
            ),
      );
    return (await query.getSingle()).read(count) ?? 0;
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(databaseProvider)),
);
