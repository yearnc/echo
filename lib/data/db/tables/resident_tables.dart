import 'package:drift/drift.dart';

/// 用户自己配置的固定住民（v3.0 阶段三）。
///
/// 和 `PostVoices` 分开：那一张是“这条帖子里出现过的人”，
/// 这一张是“长期住在这里的人”。一个固定住民在每条帖子下会映射出
/// 一个 `post_voices` 快照，但记忆和关系都挂在这张表的 id 上。
@DataClassName('CustomResidentRow')
class CustomResidents extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get avatarAsset => text().withDefault(const Constant(''))();
  /// 一句话简介（列表里显示）。
  TextColumn get bio => text().withDefault(const Constant(''))();

  /// 详细设定：身份、背景、与用户的关系。
  TextColumn get description => text().withDefault(const Constant(''))();

  /// 性格：4—6 条行为描述。
  TextColumn get personality => text().withDefault(const Constant(''))();

  /// 场景：在哪儿遇到、当前是什么场合。
  TextColumn get scenario => text().withDefault(const Constant(''))();
  TextColumn get languageStyle => text().withDefault(const Constant(''))();
  TextColumn get tone => text().withDefault(const Constant(''))();

  /// 示例对话：教模型怎么接话。
  TextColumn get exampleDialogue => text().withDefault(const Constant(''))();

  /// 额外行为指令，放提示词尾部。
  TextColumn get extraInstructions => text().withDefault(const Constant(''))();

  /// 管理用标签，逗号分隔；不发给模型。
  TextColumn get tags => text().withDefault(const Constant(''))();

  BoolColumn get memoryEnabled => boolean().withDefault(const Constant(true))();

  /// null = 无上限。
  IntColumn get memoryLimit =>
      integer().nullable().withDefault(const Constant(400))();
  /// 这个住民单独指定的对话模型配置 id（v30）。空 = 用当前启用的那条。
  TextColumn get modelConfigId => text().withDefault(const Constant(''))();

  /// 会不会发语音（v36）。关着时 `send_voice` 工具不出现。
  BoolColumn get voiceEnabled => boolean().withDefault(const Constant(false))();

  /// 音色描述。没有上传参考音频时，用它在一组固定音色里选一个。
  TextColumn get voiceDescription => text().withDefault(const Constant(''))();

  /// 上传的参考音频（`file:` 引用），只给支持克隆的 TTS 服务用。
  TextColumn get voiceSamplePath => text().withDefault(const Constant(''))();

  /// 参考音频里说的那句话，克隆时要逐字对上。
  TextColumn get voiceSampleText => text().withDefault(const Constant(''))();

  /// 已经定下来的音色：`local:<sid>` / `cloud:<voice>` / `speech:...`。
  TextColumn get voiceRef => text().withDefault(const Constant(''))();

  /// 音色由什么定下来（v41）：
  /// `description` / `reference` / `reference_description` / `reference_transcript`。
  /// 哪几种可选由当前语音模型的能力决定。
  TextColumn get voiceMode =>
      text().withDefault(const Constant('description'))();
  IntColumn get createdAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 固定住民的收件箱（v3.3）。
///
/// 唤醒式交互的地基：每次醒来先看这里有什么没处理，由模型决定
/// 回谁、回什么、或者干脆已读不回。`handledAt` 必须有——否则
/// “选择不回”会和“还没看到”混在一起，永远算待办。
@DataClassName('ResidentInboxRow')
@TableIndex(name: 'resident_inbox_pending', columns: {#residentId, #handledAt})
class ResidentInboxItems extends Table {
  TextColumn get id => text()();
  TextColumn get residentId => text()();

  /// comment_on_post / reply_to_comment / dm
  TextColumn get kind => text()();
  TextColumn get refId => text()();
  TextColumn get postId => text().nullable()();
  TextColumn get actorName => text().withDefault(const Constant(''))();

  /// 对方具体说了什么（评论正文或私信内容，截断到两百字）。
  TextColumn get summary => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get handledAt => integer().nullable()();

  /// replied / ignored / merged
  TextColumn get decision => text().withDefault(const Constant(''))();
  TextColumn get wakeId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 固定住民的唤醒日志（v3.9）。
///
/// 每次真正醒来记一条：什么时候醒的、因为什么醒、这一轮醒了多久，
/// 以及**给未来的自己留的一句话**。日志页读它，住民自己也能用工具查——
/// 它不是给用户看的监控，而是让住民对“我什么时候来过”有记忆。
@DataClassName('ResidentWakeLogRow')
@TableIndex(name: 'resident_wake_logs_at', columns: {#residentId, #wokeAt})
class ResidentWakeLogs extends Table {
  TextColumn get id => text()();
  TextColumn get residentId => text()();

  /// user_action / heartbeat / background / setup
  TextColumn get trigger => text()();
  IntColumn get wokeAt => integer()();
  IntColumn get endedAt => integer().nullable()();

  /// 留给下一次醒来的自己的话。空串 = 没留。
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get noteAt => integer().nullable()();

  /// 这句话已经被哪一次醒来带进上下文了。只为 null 时才算“还没读到”，
  /// 否则同一句留言会在之后每一轮里反复出现。
  IntColumn get noteDeliveredAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 固定住民的长期记忆（v3.0）。
///
/// 只写用户明确表达的事实/偏好/事件；删除条目不删对话原文。
@DataClassName('ResidentMemoryRow')
class ResidentMemories extends Table {
  TextColumn get id => text()();
  TextColumn get residentId => text().references(CustomResidents, #id)();

  /// dm / comment / post / manual
  TextColumn get source => text().withDefault(const Constant(''))();
  TextColumn get sourceId => text().nullable()();
  TextColumn get summary => text().withDefault(const Constant(''))();
  TextColumn get content => text().withDefault(const Constant(''))();

  /// 逗号分隔：人物/地点/事件/偏好
  TextColumn get tags => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get archivedAt => integer().nullable()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
