import '../../domain/models/post.dart';

/// 清醒模式的示例记录。
///
/// 回响模式的演示内容（天空照、垃圾桶照及其 AI 评论）已经搬到
/// `assets/demo/act1.json` / `act2.json` —— 那里是唯一的内容来源，
/// 演示播放与首次播种共用同一份脚本，避免两处慢慢写歪。
///
/// 这里只留清醒模式需要的"真实记录"，它们没有 AI 互动，
/// 是第三幕之后用户会看到的那种内容。
class DemoPosts {
  const DemoPosts._();

  static final DateTime _base = DateTime.now();

  /// 清醒模式的记录（演示第三幕切过去之后能看到）。
  static List<Post> get clearRecords => [
        Post(
          id: 'demo_record_walk',
          content: '傍晚去操场走了三圈，风有点凉，回来煮了碗面。',
          createdAt: _base.subtract(const Duration(hours: 5)),
          scope: 'clear',
        ),
        Post(
          id: 'demo_record_book',
          content: '把借了两个月的那本书读完了，最后一章在图书馆四楼。',
          createdAt: _base.subtract(const Duration(days: 1, hours: 3)),
          scope: 'clear',
        ),
      ];
}
