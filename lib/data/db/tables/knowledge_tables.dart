import 'package:drift/drift.dart';

/// 知识库（v4.11）。
///
/// 知识库不是"更长的 system prompt"，而是**有归属的内容**：
/// 谁写的、给谁看、多久失效，都落在表里。这样临时网民换一批人时，
/// 换的是"读哪本册子"，而不是每次重新拼一大段提示词。
///
/// 两类归属：
/// - `independent`：只给临时网民（`ownerKind = transient`），
///   或只给某一位固定住民（`ownerKind = resident`）。
/// - `shared`：服务对象写在 [KnowledgeTargets]，可以同时给
///   全体网民、全体住民或指定住民。
@DataClassName('KnowledgeBaseRow')
@TableIndex(name: 'knowledge_bases_scope', columns: {#scope, #updatedAt})
class KnowledgeBases extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  /// 给主人看的一句话说明，也会作为"这本书的视角"注入提示词。
  TextColumn get description => text().withDefault(const Constant(''))();

  /// independent / shared
  TextColumn get scope => text()();

  /// transient / resident；共享库固定为 shared。
  TextColumn get ownerKind => text().withDefault(const Constant('transient'))();

  /// ownerKind = resident 时绑定的人；其余为空。
  TextColumn get ownerResidentId =>
      text().withDefault(const Constant(''))();

  /// 内置库（目前只有"热门梗"）：不可删除，但条目可以改。
  BoolColumn get builtin => boolean().withDefault(const Constant(false))();

  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 是否允许系统每周自动更新（热门梗库默认开）。
  BoolColumn get autoUpdate => boolean().withDefault(const Constant(false))();

  /// 上次成功更新时间。0 表示从未更新。
  IntColumn get lastUpdatedAt => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 知识条目。
///
/// `summary` 是索引（常驻提示词），`content` 是正文（按需拉取）。
/// 热门梗库的正文必须写清来源、用处和两三个例子——这是主人定的格式。
@DataClassName('KnowledgeEntryRow')
@TableIndex(name: 'knowledge_entries_base', columns: {#baseId, #updatedAt})
class KnowledgeEntries extends Table {
  TextColumn get id => text()();

  TextColumn get baseId => text()();

  /// 梗名 / 知识点标题。
  TextColumn get title => text()();

  /// 一句话：这东西是什么、什么时候能用。
  TextColumn get summary => text().withDefault(const Constant(''))();

  /// 详细正文：来源、用处、例子。
  TextColumn get content => text().withDefault(const Constant(''))();

  /// JSON 数组，两三个例句。
  TextColumn get examples => text().withDefault(const Constant('[]'))();

  /// JSON 数组，检索用的标签。
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  TextColumn get sourceUrl => text().withDefault(const Constant(''))();

  TextColumn get sourceTitle => text().withDefault(const Constant(''))();

  /// 这条内容是什么时候核实/抓取的。
  IntColumn get verifiedAt => integer().withDefault(const Constant(0))();

  /// 过期时间；0 表示不过期。过期的条目不再注入提示词。
  IntColumn get expiresAt => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 共享知识库的服务对象。
///
/// `targetKind`：
/// - `transient_all`：全体临时网民
/// - `resident_all`：全体固定住民
/// - `resident`：`targetId` 指定的那一位
@DataClassName('KnowledgeTargetRow')
class KnowledgeTargets extends Table {
  TextColumn get baseId => text()();

  TextColumn get targetKind => text()();

  TextColumn get targetId => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {baseId, targetKind, targetId};
}
