import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/app_notification.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 通知的读写。
///
/// 通知是"互动发生"的副产品：调度器每兑现一条互动，就写一条通知。
/// 红点数量直接来自未读条数，所以不会出现"数字和列表对不上"的经典毛病。
class NotificationRepository {
  const NotificationRepository(this._db);

  final AppDatabase _db;

  Stream<List<AppNotification>> watchRecent({int limit = 40}) {
    final query = _db.select(_db.notificationLogs)
      ..orderBy([(t) => OrderingTerm.desc(t.deliveredAt)])
      ..limit(limit);

    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  /// 未读数量（底部导航的红点用）。
  Stream<int> watchUnreadCount() {
    final count = _db.notificationLogs.id.count();
    final query = _db.selectOnly(_db.notificationLogs)
      ..addColumns([count])
      ..where(_db.notificationLogs.isRead.equals(false));

    return query.watchSingle().map((row) => row.read(count) ?? 0);
  }

  /// [id] 可由调用方指定，用来从来源派生通知 id（调度器传互动 id）。
  /// 一次补发可能在**同一微秒**内写入几十条通知，用时间戳当 id 会撞主键；
  /// 按来源派生则天然幂等——同一条互动不会产生第二条通知。
  Future<void> insert({
    String? id,
    required String type,
    required String title,
    String body = '',
    String? postId,
    String scope = 'echo',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.notificationLogs)
        .insert(
          NotificationLogsCompanion(
            id: Value(id ?? 'n_${DateTime.now().microsecondsSinceEpoch}'),
            type: Value(type),
            title: Value(title),
            body: Value(body),
            postId: Value(postId),
            scheduledAt: Value(now),
            deliveredAt: Value(now),
            scope: Value(scope),
          ),
        );
  }

  Future<void> markAllRead() async {
    await _db
        .update(_db.notificationLogs)
        .write(const NotificationLogsCompanion(isRead: Value(true)));
  }

  AppNotification _toDomain(NotificationLogRow row) => AppNotification(
    id: row.id,
    type: row.type,
    title: row.title,
    body: row.body,
    postId: row.postId,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row.deliveredAt ?? row.scheduledAt ?? 0,
    ),
    isRead: row.isRead,
  );
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(databaseProvider)),
);

final notificationsProvider = StreamProvider.autoDispose<List<AppNotification>>(
  (ref) => ref.watch(notificationRepositoryProvider).watchRecent(),
);

/// 底部导航红点数据源。
final unreadNotificationCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(notificationRepositoryProvider).watchUnreadCount(),
);
