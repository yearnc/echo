/// 住民在某个钟点的去处（规划书 §3.2 生活轨迹）。
///
/// 「几点、在哪、干什么」这三样就够撑起住民自己的动态了——
/// 早八的人在食堂，夜里活跃的人在宿舍。空着也不影响，动态会退回通用模板。
class PersonaRoutine {
  const PersonaRoutine({
    required this.hour,
    this.place = '',
    this.activity = '',
  });

  final int hour;
  final String place;
  final String activity;

  factory PersonaRoutine.fromJson(Map<String, dynamic> json) => PersonaRoutine(
    hour: (json['hour'] as num?)?.toInt() ?? 0,
    place: json['place'] as String? ?? '',
    activity: json['activity'] as String? ?? '',
  );
}

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
    this.circle = '',
    this.tone = '',
    this.activeHours = const [],
    this.relationship = '同校网友',
    this.likeProbability = 0.5,
    this.commentProbability = 0.4,
    this.replyLength = 'medium',
    this.voiceModel = '',
    this.level = 1,
    this.badges = const [],
    this.followers = 0,
    this.following = 0,
    this.memoryEnabled = true,
    this.relationshipLevel = 0,
    this.commentSamples = const [],
    this.routines = const [],
  });

  final String id;
  final String name;

  /// 头像引用：`asset:` / `file:` / 空（走文字头像兜底）。
  final String avatar;
  final String bio;
  final String languageStyle;
  final String personalityType;

  /// 圈层：信息流按圈子分发时的归属（同校圈 / 树洞 / 学习 / 运动 / 摄影…）。
  /// 空字符串表示"哪个圈子都沾一点"，分发时按同校圈算。
  final String circle;

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
  final int followers;
  final int following;
  final bool memoryEnabled;
  final int relationshipLevel;

  /// 预置评论样例：演示模式离线可用，同时给真实模型当 few-shot。
  final List<String> commentSamples;

  /// 作息与去处。住民自己发动态时的素材（B3）。
  final List<PersonaRoutine> routines;

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
      circle: json['circle'] as String? ?? '',
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
      followers: (json['followers'] as num?)?.toInt() ?? 0,
      following: (json['following'] as num?)?.toInt() ?? 0,
      memoryEnabled: json['memoryEnabled'] as bool? ?? true,
      relationshipLevel: (json['relationshipLevel'] as num?)?.toInt() ?? 0,
      commentSamples: parseList('commentSamples', (e) => e as String),
      routines: parseList(
        'routines',
        (e) => PersonaRoutine.fromJson(e as Map<String, dynamic>),
      )..sort((a, b) => a.hour.compareTo(b.hour)),
    );
  }
}
