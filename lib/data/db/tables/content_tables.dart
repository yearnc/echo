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

  /// 身份资料（v24）：给模型的前缀用，只存在本机。
  ///
  /// 性别存的是稳定的枚举值（male/female/nonbinary/secret），
  /// 界面显示成中文；这样换文案时不用动数据库。
  TextColumn get gender => text().withDefault(const Constant(''))();
  TextColumn get ageRange => text().withDefault(const Constant(''))();
  TextColumn get occupation => text().withDefault(const Constant(''))();
  TextColumn get city => text().withDefault(const Constant(''))();
  TextColumn get interests => text().withDefault(const Constant(''))();

  /// 希望 AI 怎么称呼你（可以和昵称不同）。
  TextColumn get preferredName => text().withDefault(const Constant(''))();
  TextColumn get intro => text().withDefault(const Constant(''))();
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

  /// 固定住民自己发的动态记的是他的 id；用户发的为空。
  ///
  /// 不设外键：固定住民可以被删除（软删除），而动态要留着；
  /// 而且这一列只回答"谁发的"，不承担级联语义。
  TextColumn get authorResidentId => text().nullable()();

  /// 这条是“用语音发的”吗（v4.0）。
  ///
  /// 空串 = 打字发的；`me` = 用户自己的语音；其余 = 固定住民的 id。
  /// 正文仍然是转写后的文字，这个字段只负责在界面上标一句“来自 XX 的语音”。
  TextColumn get speechBy => text().withDefault(const Constant(''))();

  /// 用户语音帖的原始音频（`file:` 引用）。住民语音帖只有转写稿，没有文件。
  TextColumn get voicePath => text().nullable()();
  IntColumn get speechDurationMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
