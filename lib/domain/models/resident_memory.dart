/// 固定住民的一条长期记忆。
class ResidentMemory {
  const ResidentMemory({
    required this.id,
    required this.residentId,
    this.source = '',
    this.sourceId,
    this.summary = '',
    this.content = '',
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });

  final String id;
  final String residentId;

  /// dm / comment / post / manual
  final String source;
  final String? sourceId;
  final String summary;
  final String content;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;

  /// 给提示词用的一小段，最多 200 字。
  String toPromptLine() {
    final text = summary.isNotEmpty ? summary : content;
    final clipped = text.length > 200 ? '${text.substring(0, 200)}…' : text;
    final tagText = tags.isEmpty ? '' : '［${tags.join('、')}］';
    return '$tagText$clipped';
  }
}
