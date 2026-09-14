import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 防沉迷事件类型（规划书 §13）。
abstract final class AddictionEventType {
  /// 查看反馈次数超过阈值，弹了一次提醒。
  static const String feedbackThreshold = 'feedback_threshold';

  /// 冷静模式开关。
  static const String coolDownOn = 'cooldown_on';
  static const String coolDownOff = 'cooldown_off';

  /// 单次使用时长过长。
  static const String sessionLong = 'session_long';
}

/// 查看反馈与防沉迷事件的记录（规划书 §6.9 / §13）。
///
/// `feedback_view_logs` 这张表从建库起就在，但一直没有代码写它——
/// 防沉迷提醒因此没有依据。这里补上读写。
class AddictionRepository {
  const AddictionRepository(this._db);

  final AppDatabase _db;

  /// 默认统计窗口：最近 30 分钟。
  ///
  /// 用时间窗而不是"本次会话"，是因为用户滑走再打开几乎是无缝的——
  /// 按会话切分会让"反复回来看有没有人理我"这个真正的信号被切碎。
  static const int defaultWindowMs = 30 * 60 * 1000;

  static final Random _rand = Random();

  /// 时间戳 + 随机后缀（同 `PostRepository.newId` 的理由：只看时间戳会撞）。
  static String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 20)}';

  /// 记一次"查看反馈"（打开帖子详情 / 下拉刷新信息流都算）。
  Future<void> recordFeedbackView({String? postId, int durationMs = 0}) async {
    await _db
        .into(_db.feedbackViewLogs)
        .insert(
          FeedbackViewLogsCompanion.insert(
            id: _newId('view'),
            postId: Value(postId),
            viewedAt: DateTime.now().millisecondsSinceEpoch,
            durationMs: Value(durationMs),
          ),
        );
  }

  /// 时间窗内查看了几次反馈。
  Future<int> countFeedbackViews({int windowMs = defaultWindowMs}) async {
    final since = DateTime.now().millisecondsSinceEpoch - windowMs;
    final count = _db.feedbackViewLogs.id.count();
    final query = _db.selectOnly(_db.feedbackViewLogs)
      ..addColumns([count])
      ..where(_db.feedbackViewLogs.viewedAt.isBiggerOrEqualValue(since));
    return (await query.getSingle()).read(count) ?? 0;
  }

  Future<void> logEvent(String eventType, {int value = 0}) async {
    await _db
        .into(_db.addictionLogs)
        .insert(
          AddictionLogsCompanion.insert(
            id: _newId('addiction'),
            eventType: eventType,
            value: Value(value),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  /// 最近的事件，新的在前（心理安全页展示"这周提醒过你几次"）。
  Future<List<AddictionLogRow>> recentEvents({int limit = 20}) {
    final query = _db.select(_db.addictionLogs)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);
    return query.get();
  }

  /// 某类事件最近一次发生的时间（毫秒），没有则 null。
  ///
  /// 用来避免同一个窗口里反复弹同一条提醒——提醒的价值在于"被看见"，
  /// 连着弹三次只会让人想去关掉它。
  Future<int?> lastEventAt(String eventType) async {
    final query = _db.select(_db.addictionLogs)
      ..where((t) => t.eventType.equals(eventType))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row?.createdAt;
  }

  /// 某类事件在某时间点之后发生了几次。
  Future<int> countEventsSince(String eventType, int sinceMs) async {
    final count = _db.addictionLogs.id.count();
    final query = _db.selectOnly(_db.addictionLogs)
      ..addColumns([count])
      ..where(
        _db.addictionLogs.eventType.equals(eventType) &
            _db.addictionLogs.createdAt.isBiggerOrEqualValue(sinceMs),
      );
    return (await query.getSingle()).read(count) ?? 0;
  }
}

final addictionRepositoryProvider = Provider<AddictionRepository>(
  (ref) => AddictionRepository(ref.watch(databaseProvider)),
);
