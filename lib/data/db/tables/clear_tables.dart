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

  /// 做这件事时的心情（B11），见 `RealActionMood`。空 = 没记。
  TextColumn get mood => text().withDefault(const Constant(''))();

  IntColumn get createdAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get scope => text().withDefault(const Constant('clear'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 真实生活相册（v31）。
///
/// 只收用户**主动拍/选**的照片，全部 scope=clear：它不进信息流、
/// 不会被送去模型、也不出现在回响侧任何页面。这里不做滤镜、不做 AI 生成，
/// 照片就是照片。
@DataClassName('ClearPhotoRow')
@TableIndex(name: 'clear_photos_created', columns: {#createdAt})
class ClearPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get path => text()();
  TextColumn get caption => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get scope => text().withDefault(const Constant('clear'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 一次清醒分析的快照（v31）。
///
/// 分析结果按维度存在 `payload`（JSON 数组）里，带上生成区间与来源：
/// `source=real` 表示全部来自本机记录，`ai` 留给以后接模型时区分。
/// 存快照而不是每次现算，是为了让用户能对上“当时看到的是哪一版数字”。
@DataClassName('ClearInsightRow')
class ClearInsights extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text().withDefault(const Constant('overview'))();
  IntColumn get periodStart => integer()();
  IntColumn get periodEnd => integer()();
  IntColumn get generatedAt => integer()();
  TextColumn get payload => text()();
  TextColumn get summary => text().withDefault(const Constant(''))();
  TextColumn get source => text().withDefault(const Constant('real'))();
  TextColumn get scope => text().withDefault(const Constant('clear'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 前台使用会话（v31）。
///
/// 只记“APP 在这一段时间里是打开的”。它不是 AI 数据，也不参与清醒分析
/// 的“线上投入”以外任何结论——用途只有两个：让用户看见时间花在哪，
/// 以及支撑他自己设置的每日上限。
@DataClassName('UsageSessionRow')
@TableIndex(name: 'usage_sessions_started', columns: {#startedAt})
class UsageSessions extends Table {
  TextColumn get id => text()();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer()();
  IntColumn get durationMs => integer()();
  TextColumn get scope => text().withDefault(const Constant('shared'))();

  @override
  Set<Column> get primaryKey => {id};
}
