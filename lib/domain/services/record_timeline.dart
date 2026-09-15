import '../models/clear_journal.dart';
import '../models/post.dart';

/// 清醒模式"记录"的统一时间线。
///
/// 背景（2026-09-15 真机实测发现）：记录页此前有两个各自为政的东西——
/// 周报只数**真实行动页**打下的点，而下面的「最近」只显示**发布页**写的图文记录。
/// 看起来像两个互不相干的功能，其实是同一件事的两种记法：
///
/// - 发布页：能配图、成段，适合"今天去了哪、看到了什么"
/// - 真实行动页：带分类、够快，适合"跑了 3 公里"这种一句话打点
///
/// 所以它们合成一条时间线，周报也一起数。这里放的是纯逻辑，
/// 因此"两类怎么合、窗口怎么算"可以直接测，不用起一整个页面。
class TimelineEntry {
  const TimelineEntry({
    required this.at,
    required this.text,
    this.detail = '',
    this.images = const [],
    this.category,
  });

  /// 从发布页写下的图文记录来。
  factory TimelineEntry.ofPost(Post post) => TimelineEntry(
    at: post.createdAt,
    text: post.content,
    images: post.images,
  );

  /// 从真实行动页打下的点来。
  factory TimelineEntry.ofAction(RealAction action) => TimelineEntry(
    at: action.createdAt,
    text: action.title,
    detail: action.description,
    category: action.category.label,
  );

  final DateTime at;

  /// 主体：图文记录的正文，或真实行动的标题。
  final String text;

  /// 补充说明（只有真实行动有）。
  final String detail;

  /// 图片引用（只有图文记录有）。时间线只展示第一张缩略图。
  final List<String> images;

  /// 分类标签（只有真实行动有）。
  final String? category;
}

/// 把两类记录合成一条时间线，新的在最前面。
List<TimelineEntry> buildTimeline({
  required List<Post> posts,
  required List<RealAction> actions,
}) {
  final entries = [
    ...posts.map(TimelineEntry.ofPost),
    ...actions.map(TimelineEntry.ofAction),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return entries;
}

/// 数一数 [since] 之后记了几条（周报用）。
///
/// 用 `isBefore` 的反面而不是 `isAfter`：判断的是"在窗口内"，
/// 边界上的那一秒不该被算丢。
int countEntriesSince(List<TimelineEntry> entries, DateTime since) =>
    entries.where((entry) => !entry.at.isBefore(since)).length;
