import 'package:drift/drift.dart';

import 'content_tables.dart';

/// 私信（规划书 §3.5 / §6.2）。
///
/// 一对一会话：一个住民一条线。
@DataClassName('PrivateMessageRow')
@TableIndex(name: 'private_messages_persona', columns: {#personaId})
class PrivateMessages extends Table {
  TextColumn get id => text()();

  /// 会话对方：旧住民的 id，或者固定住民的 id（v3.0）。
  /// 两张表各自保证 id 唯一，这里不设外键。
  TextColumn get personaId => text()();

  /// in = 住民发给我的，out = 我发出去的
  TextColumn get direction => text()();
  TextColumn get content => text().withDefault(const Constant(''))();

  /// text / voice / sticker / image
  TextColumn get mediaType => text().withDefault(const Constant('text'))();

  /// 图片的描述，或者表情包的名字/标签。
  ///
  /// 住民看不到用户手机里的图时，至少要知道“这张图里是什么”；
  /// 表情包同理——只写“发来一个表情包”，下次聊天就什么也用不上。
  TextColumn get caption => text().withDefault(const Constant(''))();
  TextColumn get voicePath => text().nullable()();
  TextColumn get transcript => text().nullable()();
  IntColumn get createdAt => integer()();

  /// 已读时刻。只有收到的消息才需要它，自己发出去的为 null。
  IntColumn get readAt => integer().nullable()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get scope => text().withDefault(const Constant('echo'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 我自己说的话（B3.5）。
///
/// 与 `ai_interactions` 分开存是有道理的：住民那些评论要排期、要兑现、
/// 切到清醒模式时要被拦下来，而"我刚才回了句什么"没有这些事——
/// 它写下来就是写下来了。合并发生在读取那一层（见 `watchComments`）。
@DataClassName('UserCommentRow')
@TableIndex(name: 'user_comments_post', columns: {#postId})
class UserComments extends Table {
  TextColumn get id => text()();
  TextColumn get postId => text().references(Posts, #id)();
  TextColumn get content => text()();

  /// text / image（image 时 content 存图片引用，评论区表情包也走这里）
  TextColumn get mediaType => text().withDefault(const Constant('text'))();

  /// 图片评论配的文字。图是内容、字是“顺便说一句”，两者可以一起发；
  /// 以前只有一个 content 字段，发图就必须把输入框里的话丢掉。
  TextColumn get caption => text().withDefault(const Constant(''))();

  /// 这条是在回谁。指向的可能是住民的评论（在 `ai_interactions` 里），
  /// 也可能是别人回我的——跨两张表，所以这里不设外键。
  TextColumn get parentId => text().nullable()();

  /// 被回复的人叫什么。存名字而不是每次去查，是因为对方可能是住民、
  /// 也可能是"我"，而查名字要跨两张表；这个名字只用来显示"回复 XXX"。
  TextColumn get replyToName => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 我赞过的评论。
///
/// 跟帖子不一样：帖子的赞可以直接记在帖子自己那一行上（一条帖子一颗心），
/// 而评论有很多条，只能单独记"哪些被赞过"。`commentId` 指向的可能是
/// `ai_interactions` 里的住民评论，也可能是 `user_comments` 里的，
/// 所以这里同样不设外键。
@DataClassName('CommentLikeRow')
class CommentLikes extends Table {
  TextColumn get commentId => text()();

  /// user = 我自己点的；voice = 某个 AI 网民点的。
  TextColumn get actorKind => text().withDefault(const Constant('user'))();

  /// voice 时是 post_voices 的 id；user 时为空串。
  TextColumn get actorId => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {commentId, actorKind, actorId};
}

/// 话题（规划书 §3.4）。
///
/// 帖子与话题的关联**没有**另开一张表：一条帖子只能挂一个话题
/// （发布页就是单选），现有的 `posts.topicId` 已经够表达，
/// 多对多等真出现"一条帖子挂多个话题"的需求再说。
@DataClassName('TopicRow')
class Topics extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();

  /// 热度。由帖子数、互动数算出来，缓存成整数好排序；
  /// 怎么算的写在计算它的那处（B6），不在这里。
  IntColumn get heat => integer().withDefault(const Constant(0))();

  /// 内置话题从 assets 播种，不可删；用户新建的可以删。
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get scope => text().withDefault(const Constant('shared'))();

  @override
  Set<Column> get primaryKey => {id};
}
