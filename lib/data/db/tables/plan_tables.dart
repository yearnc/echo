import 'package:drift/drift.dart';

import 'content_tables.dart';

/// 策划模式的内容资产（规划书 §6.1）。

/// 策划脚本。
///
/// 脚本放在数据库里而不是 assets 里，因为它必须可编辑：改名、改开局内容、
/// 增删事件、复制一份再改、删掉。内置的三幕脚本在首次启动时播种进来，
/// 之后与自建脚本一视同仁（只是不允许删除）。
@DataClassName('PlanScriptRow')
class PlanScripts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();

  /// 开局内容：勾选脚本时填进发布页，用户仍可修改。
  TextColumn get postContent => text().withDefault(const Constant(''))();
  TextColumn get postImages => text().withDefault(const Constant('[]'))();
  TextColumn get topicName => text().nullable()();

  /// 事件表（JSON 数组），结构见 `domain/models/plan_script.dart`。
  TextColumn get stepsJson => text().withDefault(const Constant('[]'))();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 策划事件队列。
///
/// 和 [AiInteractions] 分开，是因为两者语义不同：
/// - `ai_interactions` 是**随机排期**的互动（普通发帖，0—48h 摊开，人格来点赞/评论）
/// - `plan_events` 是**脚本排期**的舞台指令（策划帖，秒级精确，还能切模式、出分析）
///
/// 评论事件兑现时会额外写一条 `ai_interactions`（status=done），
/// 这样评论区用的还是同一套查询；点赞/设定数据直接改帖子计数。
@DataClassName('PlanEventRow')
@TableIndex(name: 'plan_events_due', columns: {#status, #scheduledAt})
class PlanEvents extends Table {
  TextColumn get id => text()();
  TextColumn get postId => text().references(Posts, #id)();
  TextColumn get scriptId => text().nullable()();

  /// like_burst / comment / stats / mode / analysis
  TextColumn get type => text()();

  TextColumn get personaId => text().nullable()();
  TextColumn get mediaType => text().nullable()();
  TextColumn get content => text().nullable()();
  TextColumn get voiceAsset => text().nullable()();

  /// 语音条时长（毫秒）。脚本里带过来的，评论区靠它显示 "6"" 而不是 "0""。
  IntColumn get voiceDurationMs => integer().nullable()();
  TextColumn get transcript => text().nullable()();

  /// like_burst：这一批多少个赞
  IntColumn get delta => integer().nullable()();

  /// stats：直接设定的赞数 / 评论数
  IntColumn get likes => integer().nullable()();
  IntColumn get comments => integer().nullable()();

  /// mode：目标模式
  TextColumn get toMode => text().nullable()();

  /// analysis：五项分析（JSON）
  TextColumn get analysisJson => text().nullable()();

  IntColumn get scheduledAt => integer()();
  IntColumn get executedAt => integer().nullable()();

  /// pending / done / cancelled
  TextColumn get status => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
