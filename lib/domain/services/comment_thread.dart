import '../models/post.dart';

/// 把平铺的评论组装成能读的对话（B7）。**纯逻辑**。
///
/// 数据库里评论是平的（`parent_id` 指一下而已），因为"谁回了谁"本来就只是
/// 一条边的信息。但一屏评论要读得下去，就得让回复**跟在它回的那条后面**、
/// 并且缩进一层——否则同一个人的两句追问隔着二十条评论，那不像对话。
///
/// 两条规矩是从计划书 §B7 来的：
/// - **最多两层**（顶层 + 一层回复）：手机屏幕上三层楼就开始读不动了；
/// - 太深的挂到它最近的可回复祖先下面，而不是丢掉，也不是平铺在最外层。
class CommentThreads {
  const CommentThreads._();

  /// 铺开成一条阅读顺序。回复紧跟在被回复的那条下面，`depth` 就是缩进层级。
  ///
  /// [maxDepth] 是**缩进**的上限，不是数据的上限：深度超过它的评论仍然保留，
  /// 只是缩进到头、挂到能挂的地方。
  static List<ThreadedComment> build(
    List<PostComment> comments, {
    int maxDepth = 1,
  }) {
    if (comments.isEmpty) return const [];

    final sorted = [...comments]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final byId = {for (final comment in sorted) comment.id: comment};

    final childrenOf = <String, List<PostComment>>{};
    final roots = <PostComment>[];

    for (final comment in sorted) {
      final anchor = _anchorOf(comment, byId, maxDepth);
      // 没有父、父不在这一批里（被删了）、或者绕回了自己：当顶层
      if (anchor == null) {
        roots.add(comment);
        continue;
      }
      childrenOf.putIfAbsent(anchor.id, () => []).add(comment);
    }

    final result = <ThreadedComment>[];
    void walk(PostComment comment, int depth) {
      result.add(
        ThreadedComment(comment: comment, depth: depth.clamp(0, maxDepth)),
      );
      for (final child in childrenOf[comment.id] ?? const <PostComment>[]) {
        walk(child, depth + 1);
      }
    }

    for (final root in roots) {
      walk(root, 0);
    }
    return result;
  }

  /// 这条评论该挂在谁下面。返回 null 表示它是顶层。
  ///
  /// 从自己往上走，一直走到缩进还装得下的那一层；父评论不在这一批里
  /// （被删了、或者根本没加载到）就当它是顶层——**不能让它消失**，
  /// 一条看不见的评论比一条位置不完美的评论糟糕得多。
  static PostComment? _anchorOf(
    PostComment comment,
    Map<String, PostComment> byId,
    int maxDepth,
  ) {
    if (maxDepth <= 0) return null; // 全是顶层

    final parentId = comment.parentId;
    if (parentId == null) return null;

    final parent = byId[parentId];
    if (parent == null) return null; // 父不在这一批里：自己当顶层
    var cursor = parent;

    // 缩进已经满了就继续往上走，挂到还装得下的那一层——
    // 三楼的回复该贴到一楼旁边，而不是浮在最外面
    var depth = 1;
    final visited = <String>{comment.id, cursor.id};
    while (depth >= maxDepth && cursor.parentId != null) {
      final next = byId[cursor.parentId!];
      if (next == null) break;
      if (!visited.add(next.id)) return null; // 数据坏了绕成环：当顶层
      cursor = next;
      depth++;
    }
    return cursor;
  }
}

/// 评论区里的一条：它在阅读顺序里的位置，以及该缩进几层。
class ThreadedComment {
  const ThreadedComment({required this.comment, required this.depth});

  final PostComment comment;

  /// 0 = 顶层，1 = 一层回复（就这么两层，够用）。
  final int depth;

  bool get isReply => depth > 0;
}
