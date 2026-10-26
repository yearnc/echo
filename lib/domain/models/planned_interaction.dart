/// 一条排好期的互动（还没落到数据库）。
class PlannedInteraction {
  const PlannedInteraction({
    required this.personaId,
    required this.type,
    required this.scheduledAt,
    this.content,
    this.caption = '',
    this.mediaType = 'text',
    this.likeBatch = 1,
  });

  final String personaId;

  /// like / comment
  final String type;
  final DateTime scheduledAt;
  final String? content;

  /// 图片评论配的文字。表情包和一句话可以同时发。
  final String caption;
  final String mediaType;

  /// type=like 时表示"这一批代表多少个赞"：
  /// 居民自己的点赞是 1，匿名人群批次是 5~40（社区里沉默的大多数）。
  final int likeBatch;

  bool get isLike => type == 'like';
  bool get isComment => type == 'comment';

  PlannedInteraction copyWith({DateTime? scheduledAt}) => PlannedInteraction(
    personaId: personaId,
    type: type,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    content: content,
    caption: caption,
    mediaType: mediaType,
    likeBatch: likeBatch,
  );
}
