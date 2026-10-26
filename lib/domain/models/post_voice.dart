import 'ai_persona.dart';

/// 网民身份的种类（规划书 §6.1）。
enum PostVoiceKind {
  /// 发帖时临时生成，帖子结束后不再出现。
  ephemeral('临时网民'),

  /// 用户自己配置的固定住民（阶段三）。
  custom('固定住民'),

  /// 老版本迁移进来的固定住民，只读。
  builtin('旧住民');

  const PostVoiceKind(this.label);
  final String label;

  static PostVoiceKind fromKey(String? raw) => switch (raw) {
    'custom' => PostVoiceKind.custom,
    'builtin' => PostVoiceKind.builtin,
    _ => PostVoiceKind.ephemeral,
  };

  String get key => name;
}

/// 一条帖子里出现的一个网民。
///
/// 和 `AiPersona` 分开：那一份是"出厂人设"，这一份是"这次出现的人"。
/// 临时网民没有长期记忆、没有关系、没有主页；固定住民才有。
class PostVoice {
  const PostVoice({
    required this.id,
    required this.postId,
    required this.kind,
    this.residentId,
    required this.name,
    this.avatarAsset = '',
    this.avatarSeed = 0,
    this.bio = '',
    this.languageStyle = '',
    this.tone = '',
    this.model = '',
    this.memoryEnabled = true,
    this.memoryLimit = 400,
    required this.createdAt,
  });

  final String id;
  final String postId;
  final PostVoiceKind kind;

  /// 固定住民在这条帖子里的快照指向谁；临时网民为空。
  final String? residentId;
  final String name;

  /// `asset:assets/avatars/avatar_001.webp` 这类引用；空表示文字头像。
  final String avatarAsset;
  final int avatarSeed;
  final String bio;
  final String languageStyle;
  final String tone;
  final String model;
  final bool memoryEnabled;
  final int? memoryLimit;
  final DateTime createdAt;

  bool get isEphemeral => kind == PostVoiceKind.ephemeral;

  /// 给现有内容生成层用的适配对象。
  ///
  /// 临时网民没有样例台词、没有作息、没有音色：这几项留空，
  /// 就不会在"模型失败"时把它们变成一串固定台词。
  AiPersona toPersona() => AiPersona(
    id: id,
    name: name,
    avatar: avatarAsset,
    bio: bio,
    languageStyle: languageStyle,
    personalityType: kind.label,
    tone: tone,
    activeHours: const [],
    relationship: kind == PostVoiceKind.ephemeral ? '路过的网友' : '社区邻居',
    likeProbability: 0.6,
    commentProbability: 0.7,
    replyLength: 'medium',
    // 固定住民的嗓子存在 model 里（`local:<sid>` / `cloud:<voice>`）；
    // 空表示这个人没开语音，别拿默认嗓子替他说话。
    // 旧内置住民没有这一层设置，仍给默认嗓子；临时网民只发文字。
    voiceModel: model.isNotEmpty
        ? model
        : (kind == PostVoiceKind.builtin ? 'voice_warm_default' : ''),
    level: 0,
    badges: const [],
    followers: 0,
    following: 0,
    memoryEnabled: memoryEnabled,
    relationshipLevel: 0,
    commentSamples: const [],
    routines: const [],
  );

  PostVoice copyWith({
    String? name,
    String? avatarAsset,
    String? bio,
    String? languageStyle,
    String? tone,
  }) => PostVoice(
    id: id,
    postId: postId,
    kind: kind,
    residentId: residentId,
    name: name ?? this.name,
    avatarAsset: avatarAsset ?? this.avatarAsset,
    avatarSeed: avatarSeed,
    bio: bio ?? this.bio,
    languageStyle: languageStyle ?? this.languageStyle,
    tone: tone ?? this.tone,
    model: model,
    memoryEnabled: memoryEnabled,
    memoryLimit: memoryLimit,
    createdAt: createdAt,
  );
}
