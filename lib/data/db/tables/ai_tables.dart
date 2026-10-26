import 'package:drift/drift.dart';

import 'content_tables.dart';

/// AI 住民与互动类表（规划书 §8）。

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

  /// 说话的人。v3.0 之后可能是 `post_voices` 里的临时网民，
  /// 因此不再外键到 `ai_personas`（否则每个临时身份都要在固定住民表里
  /// 插一条影子行，把住民主页和关注列表一起污染）。
  TextColumn get personaId => text()();

  /// like / comment / follow / message / repost
  TextColumn get type => text()();

  /// text / voice / image / emoji
  TextColumn get mediaType => text().nullable()();
  TextColumn get content => text().nullable()();

  /// 图片评论配的一句话。表情包是内容、文字是“顺便说一句”，
  /// 两者可以同时存在——以前只存 content，发表情包就把文字吞了。
  TextColumn get caption => text().nullable()();
  TextColumn get voicePath => text().nullable()();
  TextColumn get transcript => text().nullable()();
  IntColumn get voiceDurationMs => integer().nullable()();
  IntColumn get scheduledAt => integer()();
  IntColumn get executedAt => integer().nullable()();

  /// pending / done / cancelled
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// 这条互动从哪来：scheduled（随机排期）/ user_reply（接用户的话）/
  /// peer_reply（AI 接 AI）/ plan（策划脚本）。
  TextColumn get source => text().withDefault(const Constant('scheduled'))();
  BoolColumn get isAi => boolean().withDefault(const Constant(true))();
  TextColumn get scope => text().withDefault(const Constant('echo'))();
  TextColumn get parentId => text().nullable()();

  /// 楼中楼里"回复 XXX"。用户自己的评论存在 user_comments 里，
  /// AI 的回复只能存在这里——不写的话界面上就只剩一条孤零零的回复。
  TextColumn get replyToName => text().nullable()();
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
