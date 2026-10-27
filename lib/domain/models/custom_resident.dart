import 'ai_persona.dart';

/// 住民的声音由什么定下来（v41）。
///
/// 四种方式不是每家 TTS 都支持：OpenAI 能按文字描述调语气，
/// 硅基流动要“参考音频 + 逐字稿”；本机 vits-zh-ll 支持文字描述，
/// 本机 ZipVoice 支持参考音频 + 逐字稿。编辑页按模型能力决定哪几项可选。
enum ResidentVoiceMode {
  description('description', '内置音色', '本机 vits-zh-ll 的 5 个中文声线，直接选一个'),
  cloudDescription(
    'cloud_description',
    '文字描述（云端）',
    '让云端模型按文字描述调语气，比如“低沉温柔的男声”',
  ),
  referenceOnly('reference', '仅参考音频', '只上传一段声音，不带文字'),
  referenceDescription(
    'reference_description',
    '参考音频 + 文字描述',
    '参考音频定音色，文字描述补充语气',
  ),
  referenceTranscript(
    'reference_transcript',
    '参考音频 + 转录文本',
    '上传音频并逐字填上里面说的话，克隆最准',
  );

  const ResidentVoiceMode(this.key, this.label, this.hint);

  final String key;
  final String label;
  final String hint;

  bool get usesSample => switch (this) {
    ResidentVoiceMode.referenceOnly ||
    ResidentVoiceMode.referenceDescription ||
    ResidentVoiceMode.referenceTranscript => true,
    _ => false,
  };

  bool get usesDescription => switch (this) {
    ResidentVoiceMode.cloudDescription ||
    ResidentVoiceMode.referenceDescription => true,
    _ => false,
  };

  bool get usesTranscript =>
      this == ResidentVoiceMode.referenceTranscript;

  /// 本机内置的 5 个声线。
  bool get usesLocalSpeaker => this == ResidentVoiceMode.description;

  static ResidentVoiceMode fromKey(String? raw) => values.firstWhere(
    (mode) => mode.key == raw,
    orElse: () => ResidentVoiceMode.description,
  );
}

/// 用户自己配置的固定住民（阶段三）。
class CustomResident {
  const CustomResident({
    required this.id,
    required this.name,
    this.avatarAsset = '',
    this.bio = '',
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.languageStyle = '',
    this.tone = '',
    this.exampleDialogue = '',
    this.extraInstructions = '',
    this.tags = const [],
    this.memoryEnabled = true,
    this.memoryLimit = 400,
    this.modelConfigId = '',
    this.voiceEnabled = false,
    this.voiceDescription = '',
    this.voiceSamplePath = '',
    this.voiceSampleText = '',
    this.voiceRef = '',
    this.voiceMode = ResidentVoiceMode.description,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String avatarAsset;

  /// 列表里显示的一句话简介。
  final String bio;

  /// 详细设定：身份、背景、与用户的关系。
  final String description;

  /// 4—6 条行为描述。
  final String personality;

  /// 在哪儿遇到、当前是什么场合。
  final String scenario;
  final String languageStyle;
  final String tone;

  /// 示例对话，教模型怎么接话。
  final String exampleDialogue;

  /// 额外行为指令，放提示词尾部。
  final String extraInstructions;

  /// 管理用标签，不发给模型。
  final List<String> tags;
  final bool memoryEnabled;

  /// null = 无上限。
  final int? memoryLimit;

  /// 这个住民单独使用的对话模型配置 id。空 = 用当前启用的那条。
  final String modelConfigId;

  /// 会不会发语音。关着时模型看不到 `send_voice` 工具。
  final bool voiceEnabled;

  /// 用户写的音色描述（低沉、温柔、语速慢……）。
  final String voiceDescription;

  /// 参考音频与它的逐字文本，只在支持克隆的 TTS 服务下使用。
  final String voiceSamplePath;
  final String voiceSampleText;

  /// 已经定下来的音色。`local:<sid>` / `cloud:<voice>` / `speech:...`。
  final String voiceRef;

  /// 用哪种方式定音色（v41）。
  final ResidentVoiceMode voiceMode;
  final DateTime createdAt;

  /// 给现有内容生成层用的适配对象。
  ///
  /// 固定住民比临时网民多的是人设和记忆，这里只负责把"设定"翻译成
  /// 生成层认识的三段：身份/背景/场景、说话方式/示例、语气/额外指令。
  /// 记忆不在这里——它每次按需检索，塞进人设会过期。
  AiPersona toPersona() => AiPersona(
    id: id,
    name: name,
    avatar: avatarAsset,
    bio: [bio, description, scenario]
        .where((part) => part.trim().isNotEmpty)
        .join('\n'),
    languageStyle: [languageStyle, exampleDialogue]
        .where((part) => part.trim().isNotEmpty)
        .join('\n'),
    personalityType: '固定住民',
    tone: [tone, extraInstructions]
        .where((part) => part.trim().isNotEmpty)
        .join('；'),
    activeHours: const [],
    relationship: '固定住民',
    likeProbability: 0.6,
    commentProbability: 0.7,
    replyLength: 'medium',
    // 固定住民的音色是用户选/克隆出来的；没开语音时留空，
    // 评论区的自动语音也就不会挑到它。
    voiceModel: voiceEnabled
        ? (voiceRef.trim().isEmpty ? 'voice_warm_default' : voiceRef.trim())
        : '',
    level: 1,
    badges: const [],
    followers: 0,
    following: 0,
    memoryEnabled: memoryEnabled,
    relationshipLevel: 0,
    commentSamples: const [],
    routines: const [],
  );

  CustomResident copyWith({
    String? name,
    String? avatarAsset,
    String? bio,
    String? description,
    String? personality,
    String? scenario,
    String? languageStyle,
    String? tone,
    String? exampleDialogue,
    String? extraInstructions,
    List<String>? tags,
    bool? memoryEnabled,
    int? memoryLimit,
    String? modelConfigId,
    bool? voiceEnabled,
    String? voiceDescription,
    String? voiceSamplePath,
    String? voiceSampleText,
    String? voiceRef,
    ResidentVoiceMode? voiceMode,
  }) => CustomResident(
    id: id,
    name: name ?? this.name,
    avatarAsset: avatarAsset ?? this.avatarAsset,
    bio: bio ?? this.bio,
    description: description ?? this.description,
    personality: personality ?? this.personality,
    scenario: scenario ?? this.scenario,
    languageStyle: languageStyle ?? this.languageStyle,
    tone: tone ?? this.tone,
    exampleDialogue: exampleDialogue ?? this.exampleDialogue,
    extraInstructions: extraInstructions ?? this.extraInstructions,
    tags: tags ?? this.tags,
    memoryEnabled: memoryEnabled ?? this.memoryEnabled,
    memoryLimit: memoryLimit ?? this.memoryLimit,
    modelConfigId: modelConfigId ?? this.modelConfigId,
    voiceEnabled: voiceEnabled ?? this.voiceEnabled,
    voiceDescription: voiceDescription ?? this.voiceDescription,
    voiceSamplePath: voiceSamplePath ?? this.voiceSamplePath,
    voiceSampleText: voiceSampleText ?? this.voiceSampleText,
    voiceRef: voiceRef ?? this.voiceRef,
    voiceMode: voiceMode ?? this.voiceMode,
    createdAt: createdAt,
  );
}
