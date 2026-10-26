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
  ///
  /// [scope] 必须分开：回响看板只数社区帖子，清醒看板只数真实记录。
  /// 混在一起的话，清醒侧“本周记录”会突然多出几条 AI 社区里的帖子。
  Future<List<DateTime>> myPostTimes({
    required DateTime since,
    String scope = 'echo',
  }) async {
    final query = _db.select(_db.posts)
      ..where(
        (t) =>
            t.authorResidentId.isNull() &
            t.scope.equals(scope) &
            t.deletedAt.isNull() &
            t.createdAt.isBiggerOrEqualValue(since.millisecondsSinceEpoch),
      );
    final rows = await query.get();
    return [
      for (final row in rows)
        DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    ];
  }

  /// 我自己写下评论的时间（清醒分析的“主动表达”维度）。
  Future<List<DateTime>> myCommentTimes({required DateTime since}) async {
    final query = _db.select(_db.userComments)
      ..where(
        (t) =>
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
    // 时间用 scheduled_at：补发时 executed_at 是"打开 APP 的这一刻"，
    // 积压几天的互动会全堆在同一分钟，图表就失真了。
    final query = _db.select(_db.aiInteractions)
      ..where(
        (t) =>
            t.status.equals(statusDone) &
            t.scheduledAt.isBiggerOrEqualValue(since.millisecondsSinceEpoch) &
            // 浏览只进“看过”名单，不算一次互动
            (t.type.equals('like') | t.type.equals('comment')),
      );
    final rows = await query.get();

    return [
      for (final row in rows)
        InteractionPoint(
          at: DateTime.fromMillisecondsSinceEpoch(row.scheduledAt),
          type: row.type,
          likeBatch: row.likeCount,
        ),
    ];
  }

  /// 旧住民的关注关系已经整体下线，固定住民没有这套账。
  Future<int> followerCount() async => 0;

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
