import 'ai_persona.dart';

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
    this.firstMessage = '',
    this.exampleDialogue = '',
    this.extraInstructions = '',
    this.tags = const [],
    this.activeHours = const [],
    this.memoryEnabled = true,
    this.memoryLimit = 400,
    this.alwaysShow = true,
    this.modelConfigId = '',
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

  /// 私信第一次开口用。
  final String firstMessage;

  /// 示例对话，教模型怎么接话。
  final String exampleDialogue;

  /// 额外行为指令，放提示词尾部。
  final String extraInstructions;

  /// 管理用标签，不发给模型。
  final List<String> tags;
  final List<int> activeHours;
  final bool memoryEnabled;

  /// null = 无上限。
  final int? memoryLimit;
  final bool alwaysShow;

  /// 这个住民单独使用的对话模型配置 id。空 = 用当前启用的那条。
  final String modelConfigId;
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
    activeHours: activeHours,
    relationship: '固定住民',
    likeProbability: 0.6,
    commentProbability: 0.7,
    replyLength: 'medium',
    voiceModel: '',
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
    String? firstMessage,
    String? exampleDialogue,
    String? extraInstructions,
    List<String>? tags,
    List<int>? activeHours,
    bool? memoryEnabled,
    int? memoryLimit,
    bool? alwaysShow,
    String? modelConfigId,
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
    firstMessage: firstMessage ?? this.firstMessage,
    exampleDialogue: exampleDialogue ?? this.exampleDialogue,
    extraInstructions: extraInstructions ?? this.extraInstructions,
    tags: tags ?? this.tags,
    activeHours: activeHours ?? this.activeHours,
    memoryEnabled: memoryEnabled ?? this.memoryEnabled,
    memoryLimit: memoryLimit ?? this.memoryLimit,
    alwaysShow: alwaysShow ?? this.alwaysShow,
    modelConfigId: modelConfigId ?? this.modelConfigId,
    createdAt: createdAt,
  );
}
