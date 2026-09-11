/// 一条已经落库、还在等时间的互动。
///
/// 与 [PlannedInteraction] 的区别：这个是"已经排进队列的记录"，
/// 带 id 和所属帖子；那个是"规划器刚算出来的意图"。
class PendingInteraction {
  const PendingInteraction({
    required this.id,
    required this.postId,
    required this.personaId,
    required this.type,
    this.content,
    this.mediaType,
    this.voiceDurationMs,
    this.likeBatch = 1,
  });

  final String id;
  final String postId;
  final String personaId;

  /// like / comment
  final String type;
  final String? content;
  final String? mediaType;
  final int? voiceDurationMs;

  /// 见 [PlannedInteraction.likeBatch]。
  final int likeBatch;

  bool get isLike => type == 'like';
  bool get isComment => type == 'comment';
}
