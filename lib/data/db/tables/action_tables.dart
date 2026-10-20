import 'package:drift/drift.dart';

/// 所有副作用动作的统一账本（v3.0 阶段三）。
///
/// 批量围观、工具调用、用户手动操作最后都落到同一张表：谁、对谁、
/// 做了什么、参数是什么、结果如何。`idempotency_key` 唯一，保证
/// 同一个动作重复调用只生效一次——工具调用最怕的就是模型重试把同一句话
/// 发两遍。
@DataClassName('ActionLogRow')
@TableIndex(name: 'action_logs_actor', columns: {#actorId, #action})
class ActionLogs extends Table {
  TextColumn get id => text()();

  /// 谁做的：固定住民 id、临时网民 voice id，或 `user`。
  TextColumn get actorId => text()();
  TextColumn get actorKind => text()();

  /// view_post / like_post / comment_post / reply_comment / like_comment /
  /// send_dm / create_post / search_memory / web_search / list_tools。
  TextColumn get action => text()();
  TextColumn get targetId => text().withDefault(const Constant(''))();

  /// 参数快照（JSON）。只用于排查"它到底让模型做了什么"。
  TextColumn get params => text().withDefault(const Constant('{}'))();
  TextColumn get source => text().withDefault(const Constant('tool'))();

  /// 幂等键：同一个键只执行一次。
  TextColumn get idempotencyKey => text().unique()();

  /// 结构化结果（JSON 或一句话）。失败也写，方便查"为什么没成"。
  TextColumn get result => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
