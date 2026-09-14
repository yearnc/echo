import 'dart:math';

/// 策划脚本（规划书 §6.1 策划模式）。
///
/// 与旧的"演示模式"最大的区别：**脚本不参与播放，它只负责排期**。
/// 用户在发布页勾选策划模式、选一个脚本，发帖时把脚本里的事件全部写成
/// `ai_interactions` 的排期；之后就像普通帖子一样被调度器逐条兑现。
/// 所以屏幕上没有任何"演示 UI"，帖子本身就是一条普通帖子。
///
/// 三个内置脚本由 `assets/demo/act1~3.json` 转换而来（三幕脚本资产不浪费）。
class PlanScript {
  const PlanScript({
    required this.id,
    required this.name,
    this.isBuiltIn = false,
    this.postContent = '',
    this.postImages = const [],
    this.topicName,
    this.steps = const [],
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final String id;
  final String name;

  /// 内置脚本（三幕转来的）。内置脚本也能改、能复制，只是不允许删除，
  /// 免得用户手滑之后再也找不回三幕。
  final bool isBuiltIn;

  /// 开局内容：勾选脚本时填进发布页的正文，用户还能改。
  final String postContent;
  final List<String> postImages;
  final String? topicName;

  final List<PlanStep> steps;
  final int createdAt;
  final int updatedAt;

  PlanScript copyWith({
    String? id,
    String? name,
    bool? isBuiltIn,
    String? postContent,
    List<String>? postImages,
    String? topicName,
    bool clearTopic = false,
    List<PlanStep>? steps,
    int? createdAt,
    int? updatedAt,
  }) {
    return PlanScript(
      id: id ?? this.id,
      name: name ?? this.name,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      postContent: postContent ?? this.postContent,
      postImages: postImages ?? this.postImages,
      topicName: clearTopic ? null : (topicName ?? this.topicName),
      steps: steps ?? this.steps,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isBuiltIn': isBuiltIn,
    'post': {
      'content': postContent,
      'images': postImages,
      if (topicName != null) 'topicName': topicName,
    },
    'steps': steps.map((s) => s.toJson()).toList(growable: false),
  };

  factory PlanScript.fromJson(Map<String, dynamic> json) {
    final post = json['post'] as Map<String, dynamic>? ?? const {};
    return PlanScript(
      id: json['id'] as String? ?? 'script',
      name: json['name'] as String? ?? '未命名脚本',
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      postContent: post['content'] as String? ?? '',
      postImages: (post['images'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(growable: false),
      topicName: post['topicName'] as String?,
      steps: (json['steps'] as List<dynamic>? ?? const [])
          .map((e) => PlanStep.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

/// 事件类型常量。
abstract final class PlanStepType {
  /// 一批点赞（delta 个）
  static const String likeBurst = 'like_burst';

  /// 一条评论（文本或语音）
  static const String comment = 'comment';

  /// 把赞数/评论数直接设成某个值（营造"这条帖子已经火了"的开局）
  static const String stats = 'stats';

  /// 切换模式（回响 ↔ 清醒）
  static const String mode = 'mode';

  /// 展示客观分析（只出现在画面上，不参与计数）
  static const String analysis = 'analysis';

  /// 跳到价值澄清页（第三幕"觉醒与重构"的落点）。
  static const String openValues = 'open_values';

  /// 跳到真实行动页。
  static const String openActions = 'open_actions';

  /// 需要跳转的两类事件：它们不改变数据，只是把用户带到该去的地方。
  static const List<String> navigationTypes = [openValues, openActions];

  static const List<String> all = [
    likeBurst,
    comment,
    stats,
    mode,
    analysis,
    openValues,
    openActions,
  ];

  static String label(String type) => switch (type) {
    likeBurst => '点赞',
    comment => '评论',
    stats => '设定数据',
    mode => '切换模式',
    analysis => '客观分析',
    openValues => '打开价值澄清',
    openActions => '打开真实行动',
    _ => type,
  };

  /// 该类型是不是"带人去某个页面"。
  static bool isNavigation(String type) => navigationTypes.contains(type);
}

/// 一条策划事件。
///
/// 刻意"宽而可空"：类型只有五种，每种只用其中两三个
/// 字段，但用一个模型比写五个子类更贴合脚本随手增删字段的实际形态。
class PlanStep {
  const PlanStep({
    required this.at,
    required this.type,
    this.personaId,
    this.mediaType = 'text',
    this.content,
    this.voiceAsset,
    this.transcript,
    this.durationMs,
    this.delta,
    this.likes,
    this.comments,
    this.toMode,
    this.analysis,
    this.highlight = false,
  });

  /// 发帖后第几秒。`"30"` = 第 30 秒，`"30~90"` = 这 60 秒里随机一个时刻。
  /// 允许小数（`"1.2"`），因为脚本是从毫秒精度的旧时间轴转过来的。
  final String at;

  /// 见 [PlanStepType]。
  final String type;

  final String? personaId;

  /// text / voice
  final String mediaType;
  final String? content;
  final String? voiceAsset;
  final String? transcript;

  /// 语音条的时长（毫秒）。
  ///
  /// 阶段 A 还没有真实 TTS，语音条播的是预置音频，所以时长得从脚本里带过来——
  /// 否则评论区只能显示 0"，而 0" 的语音条在画面上就是穿帮。
  final int? durationMs;

  /// like_burst：这一批多少个赞。
  final int? delta;

  /// stats：直接设定的赞数 / 评论数。
  final int? likes;
  final int? comments;

  /// mode：目标模式（echo / clear）。
  final String? toMode;

  /// analysis：五项客观分析。
  final PlanAnalysis? analysis;

  final bool highlight;

  /// 解析 `at` 得到的毫秒区间；返回 null 表示写法不合法。
  (int minMs, int maxMs)? get rangeMs {
    final parts = at.trim().split('~');
    double? lo;
    double? hi;
    if (parts.length == 1) {
      lo = double.tryParse(parts[0].trim());
      hi = lo;
    } else if (parts.length == 2) {
      lo = double.tryParse(parts[0].trim());
      hi = double.tryParse(parts[1].trim());
    }
    if (lo == null || hi == null || lo.isNegative || hi.isNegative) return null;
    final a = (lo * 1000).round();
    final b = (hi * 1000).round();
    return a <= b ? (a, b) : (b, a);
  }

  bool get isValid => rangeMs != null;

  /// 区间里取一个具体时刻。写死单个秒数时就是它本身。
  int resolveMs(Random random) {
    final range = rangeMs;
    if (range == null) return 0;
    final (min, max) = range;
    if (max <= min) return min;
    return min + random.nextInt(max - min + 1);
  }

  PlanStep copyWith({
    String? at,
    String? type,
    String? personaId,
    String? mediaType,
    String? content,
    String? voiceAsset,
    String? transcript,
    int? durationMs,
    int? delta,
    int? likes,
    int? comments,
    String? toMode,
    PlanAnalysis? analysis,
    bool? highlight,
  }) {
    return PlanStep(
      at: at ?? this.at,
      type: type ?? this.type,
      personaId: personaId ?? this.personaId,
      mediaType: mediaType ?? this.mediaType,
      content: content ?? this.content,
      voiceAsset: voiceAsset ?? this.voiceAsset,
      transcript: transcript ?? this.transcript,
      durationMs: durationMs ?? this.durationMs,
      delta: delta ?? this.delta,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      toMode: toMode ?? this.toMode,
      analysis: analysis ?? this.analysis,
      highlight: highlight ?? this.highlight,
    );
  }

  Map<String, dynamic> toJson() => {
    'at': at,
    'type': type,
    if (personaId != null) 'personaId': personaId,
    if (mediaType != 'text') 'mediaType': mediaType,
    if (content != null) 'content': content,
    if (voiceAsset != null) 'voiceAsset': voiceAsset,
    if (transcript != null) 'transcript': transcript,
    if (durationMs != null) 'voiceDurationMs': durationMs,
    if (delta != null) 'delta': delta,
    if (likes != null) 'likes': likes,
    if (comments != null) 'comments': comments,
    if (toMode != null) 'to': toMode,
    if (analysis != null) 'analysis': analysis!.toJson(),
    if (highlight) 'highlight': true,
  };

  factory PlanStep.fromJson(Map<String, dynamic> json) {
    final analysisJson = json['analysis'] as Map<String, dynamic>?;
    return PlanStep(
      // 兼容旧脚本的 atMs（毫秒），转成秒。
      at: json['at'] as String? ?? _secondsOf(json),
      type: json['type'] as String? ?? PlanStepType.comment,
      personaId: json['personaId'] as String?,
      mediaType: json['mediaType'] as String? ?? 'text',
      content: json['content'] as String?,
      voiceAsset: json['voiceAsset'] as String?,
      transcript: json['transcript'] as String?,
      durationMs: (json['voiceDurationMs'] as num?)?.toInt(),
      delta: (json['delta'] as num?)?.toInt(),
      likes: (json['likes'] as num?)?.toInt(),
      comments: (json['comments'] as num?)?.toInt(),
      toMode: json['to'] as String?,
      analysis: analysisJson == null
          ? null
          : PlanAnalysis.fromJson(analysisJson),
      highlight: json['highlight'] as bool? ?? false,
    );
  }

  static String _secondsOf(Map<String, dynamic> json) {
    final ms = (json['atMs'] as num?)?.toDouble() ?? 0;
    final seconds = ms / 1000;
    return seconds == seconds.roundToDouble()
        ? seconds.round().toString()
        : seconds.toStringAsFixed(1);
  }
}

/// 客观分析结果（策划脚本里的"展示分析"事件）。
class PlanAnalysis {
  const PlanAnalysis({
    this.imageDescription,
    this.emotionAnalysis,
    this.logicAnalysis,
    this.factCheck,
    this.suggestions,
  });

  final String? imageDescription;
  final String? emotionAnalysis;
  final String? logicAnalysis;
  final String? factCheck;
  final String? suggestions;

  /// 五项分析的有序列表，UI 直接遍历渲染。
  List<MapEntry<String, String>> get entries => [
    if (imageDescription != null && imageDescription!.isNotEmpty)
      MapEntry('图片客观描述', imageDescription!),
    if (emotionAnalysis != null && emotionAnalysis!.isNotEmpty)
      MapEntry('文本情绪分析', emotionAnalysis!),
    if (logicAnalysis != null && logicAnalysis!.isNotEmpty)
      MapEntry('逻辑结构分析', logicAnalysis!),
    if (factCheck != null && factCheck!.isNotEmpty)
      MapEntry('事实核查提示', factCheck!),
    if (suggestions != null && suggestions!.isNotEmpty)
      MapEntry('改进建议', suggestions!),
  ];

  bool get isEmpty => entries.isEmpty;

  Map<String, dynamic> toJson() => {
    if (imageDescription != null) 'imageDescription': imageDescription,
    if (emotionAnalysis != null) 'emotionAnalysis': emotionAnalysis,
    if (logicAnalysis != null) 'logicAnalysis': logicAnalysis,
    if (factCheck != null) 'factCheck': factCheck,
    if (suggestions != null) 'suggestions': suggestions,
  };

  factory PlanAnalysis.fromJson(Map<String, dynamic> json) => PlanAnalysis(
    imageDescription: json['imageDescription'] as String?,
    emotionAnalysis: json['emotionAnalysis'] as String?,
    logicAnalysis: json['logicAnalysis'] as String?,
    factCheck: json['factCheck'] as String?,
    suggestions: json['suggestions'] as String?,
  );
}
