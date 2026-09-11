/// AI 住民（规划书 §3.3）。
///
/// 字段与 `assets/personas/personas.json` 一一对应。人格是"内容资产"，
/// 所以放在 JSON 里而不是代码里——后续加人格、换头像、调语气都不用改 Dart。
class AiPersona {
  const AiPersona({
    required this.id,
    required this.name,
    this.avatar = '',
    this.bio = '',
    this.languageStyle = '',
    this.personalityType = '',
    this.tone = '',
    this.activeHours = const [],
    this.relationship = '同校网友',
    this.likeProbability = 0.5,
    this.commentProbability = 0.4,
    this.replyLength = 'medium',
    this.voiceModel = '',
    this.level = 1,
    this.badges = const [],
    this.ipLocation = '',
    this.followers = 0,
    this.following = 0,
    this.memoryEnabled = true,
    this.relationshipLevel = 0,
    this.commentSamples = const [],
  });

  final String id;
  final String name;

  /// 头像引用：`asset:` / `file:` / 空（走文字头像兜底）。
  final String avatar;
  final String bio;
  final String languageStyle;
  final String personalityType;

  /// 拼 system prompt 用的语气指令。
  final String tone;
  final List<int> activeHours;
  final String relationship;
  final double likeProbability;
  final double commentProbability;
  final String replyLength;
  final String voiceModel;
  final int level;
  final List<String> badges;
  final String ipLocation;
  final int followers;
  final int following;
  final bool memoryEnabled;
  final int relationshipLevel;

  /// 预置评论样例：演示模式离线可用，同时给真实模型当 few-shot。
  final List<String> commentSamples;

  /// 当前时刻是否属于该住民的活跃时段（含前后各 1 小时的宽容区间）。
  bool isActiveAt(DateTime time) {
    if (activeHours.isEmpty) return true;
    return activeHours.any((hour) => (hour - time.hour).abs() <= 1);
  }

  factory AiPersona.fromJson(Map<String, dynamic> json) {
    List<T> parseList<T>(String key, T Function(dynamic) convert) =>
        (json[key] as List<dynamic>? ?? const [])
            .map(convert)
            .toList(growable: false);

    return AiPersona(
      id: json['id'] as String,
      name: json['name'] as String,
      avatar: json['avatar'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      languageStyle: json['languageStyle'] as String? ?? '',
      personalityType: json['personalityType'] as String? ?? '',
      tone: json['tone'] as String? ?? '',
      activeHours: parseList('activeHours', (e) => (e as num).toInt()),
      relationship: json['relationship'] as String? ?? '同校网友',
      likeProbability: (json['likeProbability'] as num?)?.toDouble() ?? 0.5,
      commentProbability:
          (json['commentProbability'] as num?)?.toDouble() ?? 0.4,
      replyLength: json['replyLength'] as String? ?? 'medium',
      voiceModel: json['voiceModel'] as String? ?? '',
      level: (json['level'] as num?)?.toInt() ?? 1,
      badges: parseList('badges', (e) => e as String),
      ipLocation: json['ipLocation'] as String? ?? '',
      followers: (json['followers'] as num?)?.toInt() ?? 0,
      following: (json['following'] as num?)?.toInt() ?? 0,
      memoryEnabled: json['memoryEnabled'] as bool? ?? true,
      relationshipLevel: (json['relationshipLevel'] as num?)?.toInt() ?? 0,
      commentSamples: parseList('commentSamples', (e) => e as String),
    );
  }
}
