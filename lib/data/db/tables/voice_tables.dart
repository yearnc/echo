import 'package:drift/drift.dart';

import 'content_tables.dart';
import 'resident_tables.dart';

/// v3.0 的网民身份与上下文（规划书 §6.1 / §9）。

/// 一条帖子里出现过的网民。
///
/// `kind`：
/// - `ephemeral`：发帖时临时生成，帖子结束后不再出现；
/// - `custom`：用户自己配置的固定住民；
/// - `builtin`：老版本迁移进来的固定住民（只读）。
@DataClassName('PostVoiceRow')
@TableIndex(name: 'post_voices_by_post', columns: {#postId, #createdAt})
class PostVoices extends Table {
  TextColumn get id => text()();
  TextColumn get postId => text().references(Posts, #id)();
  TextColumn get kind => text().withDefault(const Constant('ephemeral'))();

  /// 固定住民在这条帖子里的快照指向谁；临时网民为空。
  TextColumn get residentId =>
      text().nullable().references(CustomResidents, #id)();
  TextColumn get name => text()();
  TextColumn get avatarAsset => text().withDefault(const Constant(''))();
  IntColumn get avatarSeed => integer().withDefault(const Constant(0))();
  TextColumn get bio => text().withDefault(const Constant(''))();
  TextColumn get languageStyle => text().withDefault(const Constant(''))();
  TextColumn get tone => text().withDefault(const Constant(''))();
  TextColumn get model => text().withDefault(const Constant(''))();

  /// 只有 custom 有意义：是否开长期记忆。
  BoolColumn get memoryEnabled => boolean().withDefault(const Constant(true))();

  /// 每个固定住民独立上限；null = 无上限。
  IntColumn get memoryLimit =>
      integer().nullable().withDefault(const Constant(400))();

  IntColumn get createdAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 一条上下文线程的缓存与压缩状态。
///
/// `voiceId` 为空表示"这条帖子的公共线程"；非空表示某个网民的私有对话。
@DataClassName('AiThreadRow')
@TableIndex(name: 'ai_threads_by_post', columns: {#postId, #voiceId})
class AiThreads extends Table {
  TextColumn get id => text()();
  TextColumn get postId => text().references(Posts, #id)();
  TextColumn get voiceId => text().nullable().references(PostVoices, #id)();
  TextColumn get provider => text().withDefault(const Constant(''))();
  TextColumn get model => text().withDefault(const Constant(''))();
  IntColumn get systemVersion => integer().withDefault(const Constant(1))();
  TextColumn get prefixHash => text().withDefault(const Constant(''))();
  IntColumn get messageCount => integer().withDefault(const Constant(0))();
  IntColumn get tokenEstimate => integer().withDefault(const Constant(0))();
  IntColumn get lastRequestAt => integer().nullable()();
  IntColumn get cacheReadTokens => integer().withDefault(const Constant(0))();
  IntColumn get cacheWriteTokens => integer().withDefault(const Constant(0))();
  IntColumn get compactedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 浏览记录：来过但没互动的人也要留痕。
@DataClassName('PostViewRow')
@TableIndex(name: 'post_views_by_post', columns: {#postId, #lastViewedAt})
class PostViews extends Table {
  TextColumn get id => text()();
  TextColumn get postId => text().references(Posts, #id)();

  /// 浏览者：临时网民/固定住民的 voice id，或者保留值 `viewer_me`（我自己）。
  /// 不设外键——"我"不在 post_voices 里。
  TextColumn get voiceId => text()();
  IntColumn get firstViewedAt => integer()();
  IntColumn get lastViewedAt => integer()();
  IntColumn get viewCount => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {postId, voiceId},
  ];
}
