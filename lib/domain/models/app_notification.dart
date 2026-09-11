/// 一条通知。
///
/// 文案刻意**不带 AI 前缀**——"温柔学姐 评论了你的帖子"，
/// 沉浸感就是靠这些细节堆出来的；合规交给页面底部那行固定小字。
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body = '',
    required this.createdAt,
    this.isRead = false,
  });

  final String id;

  /// like / comment / follow / system
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
}
