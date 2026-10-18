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
    required this.scheduledAt,
    this.content,
    this.mediaType,
    this.voiceDurationMs,
    this.likeBatch = 1,
    this.source = 'scheduled',
    this.parentId,
  });

  final String id;
  final String postId;
  final String personaId;

  /// 它**本该**发生的时刻。
  ///
  /// 冷启动补发时，通知要按这个时间记账，而不是按"现在"——
  /// 否则离线两天回来，十几次互动会在同一秒里变成一排"刚刚"。
  final DateTime scheduledAt;

  /// like / comment
  final String type;
  final String? content;
  final String? mediaType;
  final int? voiceDurationMs;

  /// 见 [PlannedInteraction.likeBatch]。
  final int likeBatch;

  /// scheduled / user_reply / peer_reply / plan
  final String source;

  /// 非空表示这是楼中楼回复，指向被回复的那条评论。
  final String? parentId;

  bool get isPeerReply => source == 'peer_reply';
  bool get isLike => type == 'like';
  bool get isComment => type == 'comment';
}
