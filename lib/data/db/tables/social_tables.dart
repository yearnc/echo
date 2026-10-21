import 'package:drift/drift.dart';

import 'ai_tables.dart';
import 'content_tables.dart';

/// 社区关系层（阶段 B）。
///
/// 阶段 A 的社区是**单向**的：住民只在"你的帖子"下面出现，彼此之间没有关系，
/// 也不记得你发过什么。这一组表就是那条分界线——住民从这里开始有生活轨迹、
/// 和你的关系会变、会私信你。
///
/// 表先建、业务后写：这几张表的形状是由规划书 §3 / §8 定下来的，
/// 与其在 B3—B6 里各迁一次，不如地基一次打好（每次迁移都要面对
/// "老库升上来会不会丢数据"这个问题，能少问一次就少问一次）。

/// 住民与用户的关系（规划书 §8 `ai_relationships`）。
///
/// 一行 = 一个住民。存的是**当前状态**，不是往来流水——
/// 具体说过什么在 `ai_interactions` 里，这里只留"到哪一步了"。
@DataClassName('AiRelationshipRow')
class AiRelationships extends Table {
  TextColumn get personaId => text().references(AiPersonas, #id)();

  /// 亲密档位：0 陌生 → 1 眼熟 → 2 互关 → 3 熟人 → 4 好友
  /// （规划书 §3.9）。存数字而不是字符串，是因为它要被比较和排序。
  IntColumn get relationshipLevel => integer().withDefault(const Constant(0))();
  IntColumn get intimacy => integer().withDefault(const Constant(0))();

  /// 互动次数。与 `intimacy` 分开：一个是"聊过几回"，一个是"多亲近"——
  /// 十条礼貌回复不该等于一次深夜长谈。
  IntColumn get interactionCount => integer().withDefault(const Constant(0))();
  IntColumn get lastInteractionAt => integer().nullable()();

  /// 压缩过的「我记得你…」。
  ///
  /// 不是聊天记录：全量历史喂给模型既贵又没必要，还有隐私上的顾虑
  /// （用户的帖文不该被整段搬进每一次请求）。见阶段 B 计划书决策 4。
  TextColumn get memorySummary => text().withDefault(const Constant(''))();

  /// 谁关注了谁：none / following / followed / mutual
  TextColumn get followState => text().withDefault(const Constant('none'))();

  TextColumn get scope => text().withDefault(const Constant('echo'))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {personaId};
}

/// 住民的生活轨迹（规划书 §3.2）。
///
/// 一行 = 某个住民在某个钟点、在某个地方、做某件事。
/// 住民自己的动态（B3）就是从这里长出来的：通勤的人发通勤的牢骚，
/// 夜里活跃的人发夜里的东西。空着也不影响——动态生成会退回通用模板。
@DataClassName('PersonaRoutineRow')
@TableIndex(name: 'persona_routines_persona', columns: {#personaId})
class PersonaRoutines extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get personaId => text().references(AiPersonas, #id)();
  IntColumn get hour => integer()();
  TextColumn get place => text().withDefault(const Constant(''))();
  TextColumn get activity => text().withDefault(const Constant(''))();
}

/// 私信（规划书 §3.5 / §6.2）。
///
/// 一句话一对一会话：一个住民一条线，不做群聊。
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
