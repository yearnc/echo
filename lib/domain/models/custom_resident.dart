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
  final DateTime createdAt;

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
    createdAt: createdAt,
  );
}
