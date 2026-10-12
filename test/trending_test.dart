import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/services/trending.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 12, 20);

  Post post({
    required String id,
    int likes = 0,
    int comments = 0,
    Duration age = Duration.zero,
    String? topic,
    String? author,
  }) => Post(
    id: id,
    content: '帖子 $id',
    createdAt: now.subtract(age),
    likeCount: likes,
    commentCount: comments,
    topicName: topic,
    authorPersonaId: author,
  );

  group('一条帖子的热度', () {
    test('没人理的帖子没有热度', () {
      expect(
        Trending.postScore(
          likes: 0,
          comments: 0,
          createdAt: now,
          now: now,
        ),
        0,
      );
    });

    test('评论比点赞重：一条评论顶三个赞', () {
      expect(
        Trending.postScore(likes: 3, comments: 1, createdAt: now, now: now),
        6,
      );
    });

    test('十二小时掉一半', () {
      final fresh = Trending.postScore(
        likes: 10,
        comments: 0,
        createdAt: now,
        now: now,
      );
      final old = Trending.postScore(
        likes: 10,
        comments: 0,
        createdAt: now.subtract(const Duration(hours: 12)),
        now: now,
      );

      expect(old, closeTo(fresh / 2, 0.001));
    });

    test('时间戳在未来的（还没兑现的排期）不衰减', () {
      expect(
        Trending.postScore(
          likes: 5,
          comments: 0,
          createdAt: now.add(const Duration(hours: 2)),
          now: now,
        ),
        5,
      );
    });
  });

  group('今日热帖', () {
    test('按热度排，老的爆款会被新帖追上', () {
      final oldHit = post(id: 'old', likes: 100, age: const Duration(days: 3));
      final today = post(id: 'today', likes: 30);

      final ranked = Trending.rankPosts([oldHit, today], now: now);

      expect(ranked.first.id, 'today');
    });

    test('分数并列时，新的排前面', () {
      final older = post(id: 'older', likes: 5, age: const Duration(minutes: 1));
      final newer = post(id: 'newer', likes: 5);

      final ranked = Trending.rankPosts([older, newer], now: now);

      expect(ranked.map((item) => item.id), ['newer', 'older']);
    });

    test('没人理的帖子不占榜位', () {
      final ranked = Trending.rankPosts([
        post(id: 'a', likes: 3),
        post(id: 'empty'),
      ], now: now);

      expect(ranked.map((item) => item.id), ['a']);
    });

    test('空数据不炸', () {
      expect(Trending.rankPosts(const [], now: now), isEmpty);
    });

    test('榜单有上限', () {
      final many = [
        for (var i = 0; i < 30; i++) post(id: 'p$i', likes: i + 1),
      ];

      expect(Trending.rankPosts(many, now: now, limit: 5).length, 5);
    });
  });

  group('热门话题', () {
    test('同一个话题下的热度加在一起', () {
      final ranked = Trending.rankTopics([
        post(id: 'a', likes: 10, topic: '随手拍'),
        post(id: 'b', likes: 5, topic: '随手拍'),
        post(id: 'c', likes: 12, topic: '期末周'),
      ], now: now);

      expect(ranked.first.name, '随手拍');
      expect(ranked.first.postCount, 2);
      expect(ranked.last.name, '期末周');
    });

    test('没有话题的帖子不参与——"无话题"不是话题', () {
      final ranked = Trending.rankTopics([
        post(id: 'a', likes: 100),
        post(id: 'b', likes: 2, topic: '   '),
      ], now: now);

      expect(ranked, isEmpty);
    });

    test('热度并列时帖子多的靠前，再一样就按名字定序', () {
      final ranked = Trending.rankTopics([
        post(id: 'a', likes: 5, topic: 'topic_b'),
        post(id: 'b', likes: 5, topic: 'topic_a'),
      ], now: now);

      // 定序是为了"同一次查询两次结果一样"，不是因为它有意义
      expect(ranked.map((item) => item.name), ['topic_a', 'topic_b']);
    });

    test('空数据不炸', () {
      expect(Trending.rankTopics(const [], now: now), isEmpty);
    });
  });

  group('活跃住民', () {
    test('只数窗口里发过动态的人', () {
      final ranked = Trending.rankResidents([
        post(id: 'a', author: 'persona_001'),
        post(id: 'b', author: 'persona_001', age: const Duration(days: 1)),
        post(id: 'c', author: 'persona_002'),
        post(id: 'd', author: 'persona_003', age: const Duration(days: 10)),
      ], now: now, window: const Duration(days: 3));

      expect(ranked.map((item) => item.personaId), ['persona_001', 'persona_002']);
      expect(ranked.first.postCount, 2);
    });

    test('你自己发的帖子不算在住民头上', () {
      final ranked = Trending.rankResidents([
        post(id: 'mine', author: null),
      ], now: now);

      expect(ranked, isEmpty);
    });
  });
}
