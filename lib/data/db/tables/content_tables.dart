import 'package:drift/drift.dart';

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

  @override
  Set<Column> get primaryKey => {id};
}
