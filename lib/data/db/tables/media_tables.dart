import 'package:drift/drift.dart';

/// 素材表：头像与表情包（规划书素材策略）。
///
/// 内置素材（`source = asset`）与用户上传（`source = file`）统一登记在一张表里，
/// UI 只认 `path` 这一个字段——所以"内置图换掉"和"用户自己传一张"
/// 对页面来说是同一件事，不需要两套逻辑。
/// 用户导入的“网友头像”池（v3.3）。
///
/// 临时网民的头像原来只能从内置的 32 张里挑；用户想用自己的图库时，
/// 这一池优先于内置素材。只存引用，文件本身在 APP 私有目录。
@DataClassName('CustomAvatarRow')
class CustomAvatars extends Table {
  TextColumn get id => text()();
  TextColumn get path => text()();
  IntColumn get createdAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('StickerRow')
class Stickers extends Table {
  TextColumn get id => text()();

  /// 展示名，也是图片缺失时的文字兜底内容。
  TextColumn get name => text()();
  TextColumn get category => text()();

  /// AI 选表情时看的标签（JSON 数组）。没标签的表情包不会进 AI 目录。
  TextColumn get tags => text().withDefault(const Constant('[]'))();

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
