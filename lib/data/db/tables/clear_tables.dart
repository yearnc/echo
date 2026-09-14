import 'package:drift/drift.dart';

/// 清醒模式的价值重建闭环（规划书 §4 / §8）。
///
/// 这两张表是"觉醒之后做什么"的落点：回响模式生产的是别人给的反应，
/// 这里生产的是用户自己想清楚的事和真正做过的事。

/// 价值澄清：用户写下的「我真正重视的事」。
///
/// `sortOrder` 必须落库，不能靠 `createdAt` 代替——排序本身就是这份练习的
/// 一部分（"哪件事更重要"正是要逼用户面对的问题），而同一分钟写下的两条
/// 按时间分不出先后。
@DataClassName('ValueClarificationRow')
class ValueClarifications extends Table {
  TextColumn get id => text()();
  TextColumn get content => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get scope => text().withDefault(const Constant('clear'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 真实行动记录：线下真正做过的事。
///
/// 与 `posts`（scope=clear）的分工：那条记录的是**想法**，这条记录的是
/// **做过的事**，带分类，供每周反思报告统计"运动 / 阅读 / 社交 / 创作"各几次。
@DataClassName('RealActionRow')
@TableIndex(name: 'real_actions_created', columns: {#createdAt})
class RealActions extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();

  /// sport / reading / social / creation / other，见 `RealActionCategory`。
  TextColumn get category => text()();

  IntColumn get createdAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get scope => text().withDefault(const Constant('clear'))();

  @override
  Set<Column> get primaryKey => {id};
}
