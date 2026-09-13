import 'package:drift/drift.dart';

/// 模型配置（规划书 §6.9 / M5）。

/// 一条模型接入配置。
///
/// **API Key 不在这张表里**：它进系统钥匙串（flutter_secure_storage，
/// Windows 上是 DPAPI、Android 上是 Keystore），数据库里只留
/// "这个配置存在"和它的地址、模型名。这样即使有人拷走了 echo.sqlite，
/// 也拿不到密钥。
@DataClassName('ModelConfigRow')
class ModelConfigs extends Table {
  TextColumn get id => text()();

  /// 预设服务商标识：openai / deepseek / qwen / zhipu / custom
  TextColumn get provider => text()();

  /// 展示名，用户可改
  TextColumn get label => text()();

  /// OpenAI 兼容的 base url（不带 /chat/completions）
  TextColumn get baseUrl => text()();

  TextColumn get model => text()();

  /// 当前启用中的那一条为 true（同一时间只允许一条）
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
