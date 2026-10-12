import 'dart:math';

import '../models/post.dart';

/// 热榜（B6）：**纯逻辑，不碰数据库**。
///
/// 排序是产品里少数几样"一眼能看穿"的东西：分数算错了、老帖子永远压着新帖，
/// 用户立刻能感觉到。所以它单独一个文件、单独测，边界（并列、空数据、
/// 时间戳在未来的排期帖）都有用例守着。
class Trending {
  /// 一条帖子值多少热度。
  ///
  /// - 点赞 1 分，评论 3 分——**说话比点赞重**，这跟点赞按钮那个轻飘飘的
  ///   交互是一回事。
  /// - 再加**时间衰减**，半衰期 12 小时：昨天的爆款不该永远压着今天的新帖，
  ///   否则热榜第二天就没人再打开了。
  /// - 时间戳在未来的（排好期还没兑现的）不衰减，按"刚发生"算。
  static double postScore({
    required int likes,
    required int comments,
    required DateTime createdAt,
    required DateTime now,
    Duration halfLife = const Duration(hours: 12),
  }) {
    final raw = likes + comments * 3;
    if (raw <= 0) return 0;

    final ageMinutes = now.difference(createdAt).inMinutes;
    if (ageMinutes <= 0) return raw.toDouble();

    final halfLifeMinutes = halfLife.inMinutes;
    if (halfLifeMinutes <= 0) return raw.toDouble();

    return raw * pow(0.5, ageMinutes / halfLifeMinutes).toDouble();
  }

  /// 今日热帖。分数并列时**新的排前面**——同一档热度里，先看到今天的更有意义。
  static List<Post> rankPosts(
    List<Post> posts, {
    required DateTime now,
    int limit = 20,
  }) {
    final scored = [
      for (final post in posts)
        (
          post: post,
          score: postScore(
            likes: post.likeCount,
            comments: post.commentCount,
            createdAt: post.createdAt,
            now: now,
          ),
        ),
    ];

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.post.createdAt.compareTo(a.post.createdAt);
    });

    return [
      for (final entry in scored.take(limit))
        if (entry.score > 0) entry.post,
    ];
  }

  /// 热门话题：同一个话题下的帖子热度加在一起。
  ///
  /// 没有话题的帖子不参与——"无话题"不是话题。
  static List<TopicHeat> rankTopics(
    List<Post> posts, {
    required DateTime now,
    int limit = 10,
  }) {
    final heat = <String, double>{};
    final counts = <String, int>{};

    for (final post in posts) {
      final topic = post.topicName?.trim() ?? '';
      if (topic.isEmpty) continue;

      heat[topic] = (heat[topic] ?? 0) +
          postScore(
            likes: post.likeCount,
            comments: post.commentCount,
            createdAt: post.createdAt,
            now: now,
          );
      counts[topic] = (counts[topic] ?? 0) + 1;
    }

    final ranked = [
      for (final entry in heat.entries)
        TopicHeat(
          name: entry.key,
          heat: entry.value,
          postCount: counts[entry.key] ?? 0,
        ),
    ];

    ranked.sort((a, b) {
      final byHeat = b.heat.compareTo(a.heat);
      if (byHeat != 0) return byHeat;
      // 热度一样时，帖子多的排前面；再一样就按名字，保证顺序是确定的
      final byCount = b.postCount.compareTo(a.postCount);
      return byCount != 0 ? byCount : a.name.compareTo(b.name);
    });

    return ranked.take(limit).toList(growable: false);
  }

  /// 活跃住民：最近这段时间里发过多少动态。
  ///
  /// 只数**窗口内**的：一个人上个月发过二十条，和"他现在还在说话"是两回事。
  static List<ActiveResident> rankResidents(
    List<Post> residentPosts, {
    required DateTime now,
    Duration window = const Duration(days: 3),
    int limit = 10,
  }) {
    final since = now.subtract(window);
    final counts = <String, int>{};

    for (final post in residentPosts) {
      final author = post.authorPersonaId?.trim() ?? '';
      if (author.isEmpty) continue;
      if (post.createdAt.isBefore(since)) continue;
      counts[author] = (counts[author] ?? 0) + 1;
    }

    final ranked = [
      for (final entry in counts.entries)
        ActiveResident(personaId: entry.key, postCount: entry.value),
    ];

    ranked.sort((a, b) {
      final byCount = b.postCount.compareTo(a.postCount);
      return byCount != 0 ? byCount : a.personaId.compareTo(b.personaId);
    });

    return ranked.take(limit).toList(growable: false);
  }
}

/// 一个话题在榜上的样子。
class TopicHeat {
  const TopicHeat({
    required this.name,
    required this.heat,
    required this.postCount,
  });

  final String name;
  final double heat;
  final int postCount;
}

/// 一位住民在榜上的样子。
class ActiveResident {
  const ActiveResident({required this.personaId, required this.postCount});

  final String personaId;
  final int postCount;
}
