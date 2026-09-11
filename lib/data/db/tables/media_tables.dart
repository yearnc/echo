import 'package:drift/drift.dart';

/// 素材表：头像与表情包（规划书素材策略）。
///
/// 内置素材（`source = asset`）与用户上传（`source = file`）统一登记在一张表里，
/// UI 只认 `path` 这一个字段——所以"内置图换掉"和"用户自己传一张"
/// 对页面来说是同一件事，不需要两套逻辑。
@DataClassName('StickerRow')
class Stickers extends Table {
  TextColumn get id => text()();

  /// 展示名，也是图片缺失时的文字兜底内容。
  TextColumn get name => text()();
  TextColumn get category => text()();

  /// asset / file
  TextColumn get source => text().withDefault(const Constant('asset'))();
  TextColumn get path => text()();
  BoolColumn get isUser => boolean().withDefault(const Constant(false))();
  BoolColumn get isBuiltin => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer().nullable()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get scope => text().withDefault(const Constant('shared'))();

  @override
  Set<Column> get primaryKey => {id};
}
