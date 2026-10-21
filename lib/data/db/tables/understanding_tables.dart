import 'package:drift/drift.dart';

import 'content_tables.dart';

/// 一条帖子“看懂了什么”（v3.0 的解析层）。
///
/// 发帖后只算一次，所有临时网民共享；帖子编辑后置空重算。
@DataClassName('PostUnderstandingRow')
class PostUnderstandings extends Table {
  TextColumn get postId => text().references(Posts, #id)();

  /// 玩梗 / 感伤 / 分享 / 吐槽 / 求助 / 炫耀 / 日常
  TextColumn get tone => text().withDefault(const Constant(''))();

  /// 游戏 / 行业 / 生活 / 情感 / 知识 / 其他
  TextColumn get domain => text().withDefault(const Constant(''))();

  /// 游戏名、角色、术语、梗名（JSON 数组）
  TextColumn get entities => text().withDefault(const Constant('[]'))();

  /// 一句话：这条帖子在说什么
  TextColumn get point => text().withDefault(const Constant(''))();

  /// 图片理解（v24）：一次解析，所有网民共享。
  /// 没有配视觉模型或帖子没图时为空。
  TextColumn get imageSummary => text().withDefault(const Constant(''))();

  /// 玩梗时：笑点机制
  TextColumn get jokeMechanism => text().withDefault(const Constant(''))();

  /// 感伤时：情绪落在哪件事上
  TextColumn get emotion => text().withDefault(const Constant(''))();

  /// 游戏/行业：圈内人真正会接的点
  TextColumn get insiderAngle => text().withDefault(const Constant(''))();

  /// 是否需要外部知识（联网）
  BoolColumn get needsWeb => boolean().withDefault(const Constant(false))();

  /// 0—1；低的时候评论只许提问/围观，不许装懂
  RealColumn get confidence => real().withDefault(const Constant(0))();
  TextColumn get model => text().withDefault(const Constant(''))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {postId};
}
