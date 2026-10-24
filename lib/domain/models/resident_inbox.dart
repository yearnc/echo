/// 固定住民收件箱里的一条待办。
class ResidentInboxItem {
  const ResidentInboxItem({
    required this.id,
    required this.residentId,
    required this.kind,
    required this.refId,
    required this.createdAt,
    this.postId,
    this.summary = '',
  });

  final String id;
  final String residentId;

  /// comment_on_post / reply_to_comment / dm
  final String kind;
  final String refId;
  final String? postId;
  final String summary;
  final DateTime createdAt;
}
