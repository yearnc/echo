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

  /// 用途：chat（对话）/ image（文生图）。
  ///
  /// 两者是分开配的，也允许只配其中之一——文生图比对话贵一个量级，
  /// 用户完全可能只想用便宜的那个。
  TextColumn get kind => text().withDefault(const Constant('chat'))();

  /// 这条对话模型能不能直接收图片（v24）。
  /// 关着的时候私信图片不会塞进请求，避免整轮 400。
  BoolColumn get supportsVision =>
      boolean().withDefault(const Constant(false))();

  /// 语音合成模型支持哪些音色配置方式（v41）。
  ///
  /// 四种方式不是每家都支持：OpenAI 的 `instructions` 能按描述调语气，
  /// 硅基流动 CosyVoice2 要参考音频 + 逐字稿。
  /// 编辑页按这里的开关决定哪几项可选，避免用户配完才发现服务商不认。
  BoolColumn get ttsVoiceDescription =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get ttsReferenceOnly =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get ttsReferenceDescription =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get ttsReferenceTranscript =>
      boolean().withDefault(const Constant(false))();

  /// 当前启用中的那一条为 true（**同一用途**里只允许一条）
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
