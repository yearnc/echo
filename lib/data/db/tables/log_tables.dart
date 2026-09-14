import 'package:drift/drift.dart';

import 'content_tables.dart';

/// 清醒模式产出与各类日志表（规划书 §8）。

/// 客观分析结果（清醒模式独有）。
@DataClassName('AnalysisResultRow')
class AnalysisResults extends Table {
  TextColumn get id => text()();
  TextColumn get postId => text().references(Posts, #id)();
  TextColumn get imageDescription => text().nullable()();
  TextColumn get emotionAnalysis => text().nullable()();
  TextColumn get logicAnalysis => text().nullable()();
  TextColumn get factCheck => text().nullable()();
  TextColumn get suggestions => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get scope => text().withDefault(const Constant('clear'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 模式切换日志：冷却期校验与审计都靠它。
@DataClassName('ModeSwitchLogRow')
class ModeSwitchLogs extends Table {
  TextColumn get id => text()();
  TextColumn get fromMode => text()();
  TextColumn get toMode => text()();
  IntColumn get switchedAt => integer()();

  /// archived / purged / kept
  TextColumn get archiveAction => text().withDefault(const Constant('kept'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 通知记录，红点计数与聚合的依据。
@DataClassName('NotificationLogRow')
@TableIndex(name: 'notification_logs_delivered', columns: {#deliveredAt})
class NotificationLogs extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get body => text().withDefault(const Constant(''))();

  /// 这条通知指向的帖子（点击通知跳转用）。系统通知可以为空。
  TextColumn get postId => text().nullable()();
  IntColumn get scheduledAt => integer().nullable()();
  IntColumn get deliveredAt => integer().nullable()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  TextColumn get scope => text().withDefault(const Constant('echo'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 反馈查看日志：防沉迷提醒的触发依据（"你已连续查看反馈 12 次"）。
@DataClassName('FeedbackViewLogRow')
class FeedbackViewLogs extends Table {
  TextColumn get id => text()();
  TextColumn get postId => text().nullable()();
  IntColumn get viewedAt => integer()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get scope => text().withDefault(const Constant('echo'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 防沉迷日志（规划书 §8 / §13）。
///
/// 只记录、不拦截：它的用途是让用户（和周报）能回看"这周被提醒了几次、
/// 冷静模式开了多久"，而不是拿来做惩罚或强制退出——那会把工具变成家长。
@DataClassName('AddictionLogRow')
class AddictionLogs extends Table {
  TextColumn get id => text()();

  /// feedback_threshold / cooldown_on / cooldown_off / session_long
  TextColumn get eventType => text()();

  /// 事件附带的数值：触发时的查看次数、使用时长（分钟）等。
  IntColumn get value => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer()();
  TextColumn get scope => text().withDefault(const Constant('shared'))();

  @override
  Set<Column> get primaryKey => {id};
}
