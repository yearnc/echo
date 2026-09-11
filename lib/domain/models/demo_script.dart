/// 演示模式的三幕脚本模型。
///
/// 脚本是**内容资产**（JSON），播放器是逻辑——两者分开，
/// 所以改台词、加评论、调节奏都不用碰 Dart 代码。
///
/// 刻意把所有可能的字段都摊平在 [DemoStep] 上：类型有十几种，
/// 每种只用到其中两三个字段，但用一个"宽而可空"的模型比写十几个子类
/// 更贴合脚本的实际形态（脚本会随时增删字段，子类体系会一直追着改）。
library;

class DemoScript {
  const DemoScript({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.durationHintMs,
    required this.steps,
    this.post,
    this.postRef,
  });

  final String id;
  final String title;
  final String subtitle;
  final int durationHintMs;
  final List<DemoStep> steps;

  /// 本幕自己的帖子（第一、二幕）。
  final DemoPostSpec? post;

  /// 复用另一幕的帖子（第三幕复用第一幕的天空照——"同一张照片"是这一幕的关键）。
  final String? postRef;

  factory DemoScript.fromJson(Map<String, dynamic> json) {
    final postJson = json['post'] as Map<String, dynamic>?;
    return DemoScript(
      id: json['id'] as String? ?? 'act',
      title: json['title'] as String? ?? '未命名',
      subtitle: json['subtitle'] as String? ?? '',
      durationHintMs: (json['durationHintMs'] as num?)?.toInt() ?? 0,
      post: postJson == null ? null : DemoPostSpec.fromJson(postJson),
      postRef: json['postRef'] as String?,
      steps: [
        ...(json['preSteps'] as List<dynamic>? ?? const [])
            .map((e) => DemoStep.fromJson(e as Map<String, dynamic>)),
        ...(json['steps'] as List<dynamic>? ?? const [])
            .map((e) => DemoStep.fromJson(e as Map<String, dynamic>)),
      ]..sort((a, b) => a.atMs.compareTo(b.atMs)),
    );
  }

  /// 时间轴总长度：以最后一个动作为准，脚本里的 durationHintMs 只是参考。
  int get effectiveDurationMs =>
      steps.isEmpty ? durationHintMs : steps.last.atMs;
}

class DemoPostSpec {
  const DemoPostSpec({
    required this.id,
    required this.content,
    this.images = const [],
    this.topicName,
    this.scope = 'echo',
  });

  final String id;
  final String content;
  final List<String> images;
  final String? topicName;
  final String scope;

  factory DemoPostSpec.fromJson(Map<String, dynamic> json) => DemoPostSpec(
        id: json['id'] as String? ?? 'demo_post',
        content: json['content'] as String? ?? '',
        images: (json['images'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(growable: false),
        topicName: json['topicName'] as String?,
        scope: json['scope'] as String? ?? 'echo',
      );
}

/// 客观分析结果（第三幕）。
class DemoAnalysis {
  const DemoAnalysis({
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

  factory DemoAnalysis.fromJson(Map<String, dynamic> json) => DemoAnalysis(
        imageDescription: json['imageDescription'] as String?,
        emotionAnalysis: json['emotionAnalysis'] as String?,
        logicAnalysis: json['logicAnalysis'] as String?,
        factCheck: json['factCheck'] as String?,
        suggestions: json['suggestions'] as String?,
      );

  /// 五项分析的有序列表，UI 直接遍历渲染。
  List<MapEntry<String, String>> get entries => [
        if (imageDescription != null) MapEntry('图片客观描述', imageDescription!),
        if (emotionAnalysis != null) MapEntry('文本情绪分析', emotionAnalysis!),
        if (logicAnalysis != null) MapEntry('逻辑结构分析', logicAnalysis!),
        if (factCheck != null) MapEntry('事实核查提示', factCheck!),
        if (suggestions != null) MapEntry('改进建议', suggestions!),
      ];
}

/// 时间轴上的一个动作。
class DemoStep {
  const DemoStep({
    required this.atMs,
    required this.type,
    this.personaId,
    this.mediaType = 'text',
    this.content,
    this.voiceAsset,
    this.transcript,
    this.voiceDurationMs,
    this.likes,
    this.comments,
    this.delta,
    this.hint,
    this.text,
    this.title,
    this.body,
    this.label,
    this.rank,
    this.confirmText,
    this.prompt,
    this.captions = const [],
    this.analysis,
    this.toMode,
    this.archiveAI = false,
    this.purgeAI = false,
    this.highlight = false,
  });

  final int atMs;

  /// stats / like_burst / comment / hot / overlay / notification / settings_hint
  /// / confirm_dialog / mode / notice / rebuild_guide / analysis / open_values
  /// / open_actions / weekly_report_preview / caption_suggestion / end_card
  final String type;

  final String? personaId;
  final String mediaType;
  final String? content;
  final String? voiceAsset;
  final String? transcript;
  final int? voiceDurationMs;

  final int? likes;
  final int? comments;
  final int? delta;

  final String? hint;
  final String? text;
  final String? title;
  final String? body;
  final String? label;
  final int? rank;
  final String? confirmText;
  final String? prompt;
  final List<String> captions;
  final DemoAnalysis? analysis;
  final String? toMode;
  final bool archiveAI;
  final bool purgeAI;
  final bool highlight;

  bool get isComment => type == 'comment';

  factory DemoStep.fromJson(Map<String, dynamic> json) {
    final analysisJson = json['analysis'] as Map<String, dynamic>?;
    return DemoStep(
      atMs: (json['atMs'] as num?)?.toInt() ?? 0,
      type: json['type'] as String? ?? 'overlay',
      personaId: json['personaId'] as String?,
      mediaType: json['mediaType'] as String? ?? 'text',
      content: json['content'] as String?,
      voiceAsset: json['voiceAsset'] as String?,
      transcript: json['transcript'] as String?,
      voiceDurationMs: (json['voiceDurationMs'] as num?)?.toInt(),
      likes: (json['likes'] as num?)?.toInt(),
      comments: (json['comments'] as num?)?.toInt(),
      delta: (json['delta'] as num?)?.toInt(),
      hint: json['hint'] as String?,
      text: json['text'] as String?,
      title: json['title'] as String?,
      body: json['body'] as String?,
      label: json['label'] as String?,
      rank: (json['rank'] as num?)?.toInt(),
      confirmText: json['confirmText'] as String?,
      prompt: json['prompt'] as String?,
      captions: (json['captions'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(growable: false),
      analysis: analysisJson == null ? null : DemoAnalysis.fromJson(analysisJson),
      toMode: json['to'] as String?,
      archiveAI: json['archiveAI'] as bool? ?? false,
      purgeAI: json['purgeAI'] as bool? ?? false,
      highlight: json['highlight'] as bool? ?? false,
    );
  }
}
