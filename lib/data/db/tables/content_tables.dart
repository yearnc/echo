import 'package:drift/drift.dart';

import 'ai_tables.dart';

/// 配置与内容类表（规划书 §8）。

// 所有 Drift 行类统一加 `Row` 后缀：领域模型（Post / AiPersona / Sticker…）
// 才是业务代码里的名字，数据库行对象不该占用它们。

/// 键值配置。`scope` 区分 shared / echo / clear（规划书 §2.4.3）。
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  TextColumn get scope => text().withDefault(const Constant('shared'))();

  @override
  Set<Column> get primaryKey => {key};
}

/// 用户资料（阶段 A 单行）。
@DataClassName('UserProfileRow')
class UserProfile extends Table {
  TextColumn get id => text()();
  TextColumn get nickname => text().withDefault(const Constant(''))();
  TextColumn get avatar => text().withDefault(const Constant(''))();
  TextColumn get signature => text().withDefault(const Constant(''))();
  IntColumn get level => integer().withDefault(const Constant(1))();
  IntColumn get exp => integer().withDefault(const Constant(0))();
  IntColumn get followers => integer().withDefault(const Constant(0))();
  IntColumn get following => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 帖子。图片以 JSON 数组文本存放（`asset:` / `file:` 引用）。
@DataClassName('PostRow')
@TableIndex(name: 'posts_created_at', columns: {#createdAt})
class Posts extends Table {
  TextColumn get id => text()();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get images => text().withDefault(const Constant('[]'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer().nullable()();
  TextColumn get scope => text().withDefault(const Constant('shared'))();
  BoolColumn get isAiGenerated =>
      boolean().withDefault(const Constant(false))();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get topicId => text().nullable()();
  TextColumn get topicName => text().nullable()();
  BoolColumn get allowAiReply => boolean().withDefault(const Constant(true))();
  TextColumn get replyDensity => text().nullable()();
  TextColumn get likeLevel => text().nullable()();
  IntColumn get humanLevel => integer().nullable()();
  BoolColumn get isHot => boolean().withDefault(const Constant(false))();
  IntColumn get likeCount => integer().withDefault(const Constant(0))();
  IntColumn get commentCount => integer().withDefault(const Constant(0))();

  /// 我点过赞的时刻；null 表示没点过。
  ///
  /// 存时刻而不是布尔值，是因为"什么时候点的"以后可能有用（比如排序、
  /// 比如看自己的互动轨迹）；而它反正只占一个整数。
  IntColumn get likedAt => integer().nullable()();

  /// 住民自己发的动态在这里记下作者；用户发的为 null。
  ///
  /// 住民动态走同一张 `posts` 表而不是另开一张（阶段 B 计划书决策 3）：
  /// 信息流、帖子详情、评论区、点赞计数全部现成，`ai_interactions` 的外键
  /// 也不用改语义——"谁发的"只多这一个字段。
  TextColumn get authorPersonaId =>
      text().nullable().references(AiPersonas, #id)();

  /// 固定住民自己发的动态记的是他的 id；用户发的、旧住民发的为空。
  ///
  /// 不设外键：固定住民可以被删除（软删除），而动态要留着；
  /// 而且这一列只回答"谁发的"，不承担级联语义。
  TextColumn get authorResidentId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
