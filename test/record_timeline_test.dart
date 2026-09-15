import 'package:echo/domain/models/clear_journal.dart';
import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/services/record_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// 清醒模式"记录"时间线的纯逻辑测试。
///
/// 这段逻辑存在的理由值得留个记录：真机实测时发现记录页分成了两个世界——
/// 周报只数真实行动页打下的点，「最近」只显示发布页写的图文记录。
/// 合并之后，"两类怎么合、窗口怎么算"就都在这里，能直接测。
void main() {
  Post post(String id, String content, DateTime at) =>
      Post(id: id, content: content, createdAt: at);

  RealAction action(String id, String title, DateTime at) => RealAction(
    id: id,
    title: title,
    category: RealActionCategory.sport,
    createdAt: at,
  );

  final now = DateTime(2026, 9, 15, 20);
  final today = now.subtract(const Duration(hours: 2));
  final yesterday = now.subtract(const Duration(days: 1));
  final longAgo = now.subtract(const Duration(days: 30));

  group('buildTimeline', () {
    test('两类记录合成一条线，新的在最前面', () {
      final entries = buildTimeline(
        posts: [post('p1', '今天拍的照片', today)],
        actions: [action('a1', '昨天跑了 3 公里', yesterday)],
      );

      expect(entries.map((e) => e.text), ['今天拍的照片', '昨天跑了 3 公里']);
    });

    test('图文记录带着图片，真实行动带着分类标签', () {
      final entries = buildTimeline(
        posts: [
          Post(
            id: 'p1',
            content: '天空照',
            images: const ['file:/tmp/sky.jpg'],
            createdAt: today,
          ),
        ],
        actions: [action('a1', '跑了 3 公里', today)],
      );

      final fromPost = entries.firstWhere((e) => e.text == '天空照');
      final fromAction = entries.firstWhere((e) => e.text == '跑了 3 公里');

      expect(fromPost.images, ['file:/tmp/sky.jpg']);
      expect(fromPost.category, isNull);
      expect(fromAction.category, '运动');
      expect(fromAction.images, isEmpty);
    });

    test('两边都空时就是一条空线', () {
      expect(buildTimeline(posts: const [], actions: const []), isEmpty);
    });
  });

  group('countEntriesSince', () {
    test('只数窗口内记下的', () {
      final entries = buildTimeline(
        posts: [post('p1', '今天', today)],
        actions: [action('a1', '昨天', yesterday), action('a2', '上个月', longAgo)],
      );

      final weekAgo = now.subtract(const Duration(days: 7));

      expect(countEntriesSince(entries, weekAgo), 2);
      expect(
        countEntriesSince(entries, now.subtract(const Duration(days: 60))),
        3,
      );
    });

    test('窗口边界上的那一条算在里面', () {
      final since = now.subtract(const Duration(days: 7));
      final entries = buildTimeline(
        posts: [post('p1', '正好七天前', since)],
        actions: const [],
      );

      expect(countEntriesSince(entries, since), 1);
    });
  });
}
