import 'package:drift/drift.dart';

import 'content_tables.dart';

/// AI 住民与互动类表（规划书 §8）。

/// AI 人格。阶段 A 从 assets/personas.json 播种，阶段 B 支持用户自定义。
@DataClassName('AiPersonaRow')
class AiPersonas extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get avatar => text().withDefault(const Constant(''))();
  TextColumn get bio => text().withDefault(const Constant(''))();
  TextColumn get languageStyle => text().withDefault(const Constant(''))();
  TextColumn get tone => text().withDefault(const Constant(''))();
  TextColumn get activeHours => text().withDefault(const Constant('[]'))();
  RealColumn get likeProbability => real().withDefault(const Constant(0.5))();
  RealColumn get commentProbability =>
      real().withDefault(const Constant(0.4))();
  TextColumn get replyLength => text().withDefault(const Constant('medium'))();
  TextColumn get voiceModel => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get scope => text().withDefault(const Constant('echo'))();
  IntColumn get level => integer().withDefault(const Constant(1))();
  TextColumn get badges => text().withDefault(const Constant('[]'))();
  IntColumn get followers => integer().withDefault(const Constant(0))();
  IntColumn get following => integer().withDefault(const Constant(0))();
  TextColumn get personalityType => text().withDefault(const Constant(''))();
  BoolColumn get memoryEnabled => boolean().withDefault(const Constant(true))();
  IntColumn get relationshipLevel => integer().withDefault(const Constant(0))();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// AI 互动队列——阶段 A 的核心表。
///
/// 发帖时就把 0—48 小时内的互动**排好队**（`scheduledAt`），
/// APP 冷启动或回前台时扫描到期的记录补发，绕开系统后台任务限制。
@DataClassName('AiInteractionRow')
@TableIndex(
  name: 'ai_interactions_lookup',
  columns: {#postId, #personaId, #status},
)
@TableIndex(name: 'ai_interactions_scheduled', columns: {#scheduledAt})
class AiInteractions extends Table {
  TextColumn get id => text()();
  TextColumn get postId => text().references(Posts, #id)();
  TextColumn get personaId => text().references(AiPersonas, #id)();

  /// like / comment / follow / message / repost
  TextColumn get type => text()();

  /// text / voice / image / emoji
  TextColumn get mediaType => text().nullable()();
  TextColumn get content => text().nullable()();
  TextColumn get voicePath => text().nullable()();
  TextColumn get transcript => text().nullable()();
  IntColumn get voiceDurationMs => integer().nullable()();
  IntColumn get scheduledAt => integer()();
  IntColumn get executedAt => integer().nullable()();

  /// pending / done / cancelled
  TextColumn get status => text().withDefault(const Constant('pending'))();
  BoolColumn get isAi => boolean().withDefault(const Constant(true))();
  TextColumn get scope => text().withDefault(const Constant('echo'))();
  TextColumn get parentId => text().nullable()();
  IntColumn get likeCount => integer().withDefault(const Constant(0))();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  // 这里刻意**不加** (postId, personaId, type) 唯一约束：
  // 规划书 §3.6 要求住民能"连续回复、追问、@用户"，
  // 所以同一个人格完全可以对同一条帖子评论多次。
  // "一个人只能点一次赞" 属于调度规则，放在调度器里判断，
  // 不该由数据库表结构来约束（否则会误伤多次评论）。
}
