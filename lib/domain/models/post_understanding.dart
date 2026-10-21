/// 一条帖子"看懂了什么"（v3.0 解析层）。
///
/// 一次解析，所有临时网民共享。置信度低时，评论只许提问/围观，不许装懂。
class PostUnderstanding {
  const PostUnderstanding({
    required this.postId,
    this.tone = '',
    this.domain = '',
    this.entities = const [],
    this.point = '',
    this.imageSummary = '',
    this.jokeMechanism = '',
    this.emotion = '',
    this.insiderAngle = '',
    this.needsWeb = false,
    this.confidence = 0,
    this.model = '',
    required this.updatedAt,
  });

  final String postId;

  /// 玩梗 / 感伤 / 分享 / 吐槽 / 求助 / 炫耀 / 日常
  final String tone;

  /// 游戏 / 行业 / 生活 / 情感 / 知识 / 其他
  final String domain;

  final List<String> entities;

  /// 一句话：这条帖子在说什么。
  final String point;

  /// 图片内容摘要（v24）：一帖只解析一次，所有网民共享。
  final String imageSummary;
  final String jokeMechanism;
  final String emotion;
  final String insiderAngle;
  final bool needsWeb;
  final double confidence;
  final String model;
  final DateTime updatedAt;

  bool get isConfident => confidence >= 0.55;
  bool get isJoke => tone.contains('梗');
  bool get isEmotional => tone.contains('感伤') || tone.contains('情绪');

  /// 给评论提示词用的一段固定文本。
  String toPromptBlock() {
    final buffer = StringBuffer()
      ..writeln('【这条帖子已经看懂了】')
      ..writeln('语气：${tone.isEmpty ? '日常' : tone}')
      ..writeln('领域：${domain.isEmpty ? '生活' : domain}');
    if (point.isNotEmpty) buffer.writeln('在说：$point');
    if (imageSummary.isNotEmpty) {
      buffer.writeln('图片里：$imageSummary');
    }
    if (entities.isNotEmpty) {
      buffer.writeln('提到的：${entities.join('、')}');
    }
    if (jokeMechanism.isNotEmpty) buffer.writeln('笑点：$jokeMechanism');
    if (emotion.isNotEmpty) buffer.writeln('情绪落点：$emotion');
    if (insiderAngle.isNotEmpty) buffer.writeln('圈内角度：$insiderAngle');
    buffer.writeln(
      isConfident
          ? '理解置信度：${confidence.toStringAsFixed(2)}'
          : '理解不确定（${confidence.toStringAsFixed(2)}）：只能提问或围观，不许装懂',
    );
    return buffer.toString().trim();
  }
}
