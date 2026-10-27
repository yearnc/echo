import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/services/resident_wake_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('刷帖返回的标签', () {
    test('用户帖：作者是「你」，带时间、话题和计数', () {
      final entry = ResidentWakeService.feedEntry(
        Post(
          id: 'p1',
          content: '今天楼下桂花开了',
          topicName: '生活',
          createdAt: DateTime(2026, 10, 27, 18, 5),
          likeCount: 3,
          commentCount: 2,
          images: const ['file:a.png', 'file:b.png'],
        ),
      );

      expect(entry['author'], '你');
      expect(entry['author_type'], '用户');
      expect(entry['time'], contains('18:05'));
      expect(entry['topic'], '生活');
      expect(entry['likes'], 3);
      expect(entry['comments'], 2);
      expect(entry['images'], 2);
    });

    test('住民帖带名字和类型', () {
      final entry = ResidentWakeService.feedEntry(
        Post(
          id: 'p2',
          content: '值夜班刚下班',
          createdAt: DateTime(2026, 10, 27, 7, 20),
          authorResidentId: 'r1',
        ),
        authorName: '小满',
      );
      expect(entry['author'], '小满');
      expect(entry['author_type'], '固定住民');
    });

    test('长内容截断，但保留开头', () {
      final entry = ResidentWakeService.feedEntry(
        Post(
          id: 'p3',
          content: '很长的帖子' * 40,
          createdAt: DateTime(2026, 10, 27),
        ),
      );
      final content = entry['content'] as String;
      expect(content.length, lessThanOrEqualTo(121));
      expect(content, endsWith('…'));
    });
  });
}
