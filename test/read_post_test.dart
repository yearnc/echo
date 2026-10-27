import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/models/post_voice.dart';
import 'package:echo/domain/services/resident_wake_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final post = Post(
    id: 'p1',
    content: '很长的正文' * 600,
    topicName: '生活',
    createdAt: DateTime(2026, 10, 27, 20),
    likeCount: 5,
    commentCount: 4,
    images: const ['file:a.png', 'file:b.png'],
  );

  final residentVoice = PostVoice(
    id: 'v1',
    postId: 'p1',
    kind: PostVoiceKind.custom,
    residentId: 'r1',
    name: '小满',
    createdAt: DateTime(2026, 10, 27, 19),
  );
  final ephemeralVoice = PostVoice(
    id: 'v2',
    postId: 'p1',
    kind: PostVoiceKind.ephemeral,
    name: '路过的灯',
    createdAt: DateTime(2026, 10, 27, 19),
  );

  final comments = [
    PostComment(
      id: 'c1',
      postId: 'p1',
      personaId: 'v1',
      content: '写得好',
      createdAt: DateTime(2026, 10, 27, 20, 1),
      likeCount: 2,
    ),
    PostComment(
      id: 'c2',
      postId: 'p1',
      personaId: 'v2',
      content: '+1',
      createdAt: DateTime(2026, 10, 27, 20, 2),
      parentId: 'c1',
      replyToName: '小满',
    ),
    PostComment(
      id: 'c3',
      postId: 'p1',
      content: '我也觉得',
      createdAt: DateTime(2026, 10, 27, 20, 3),
      parentId: 'c1',
    ),
    PostComment(
      id: 'c4',
      postId: 'p1',
      content: '另一条顶层',
      createdAt: DateTime(2026, 10, 27, 20, 4),
    ),
  ];

  Map<String, dynamic> detail({int limit = 20}) =>
      ResidentWakeService.postDetail(
        post: post,
        comments: comments,
        voices: [residentVoice, ephemeralVoice],
        viewCount: 9,
        authorName: '你',
        commentsLimit: limit,
      );

  test('完整正文、赞/评论/浏览和图片数都在', () {
    final data = detail();
    expect(data['id'], 'p1');
    expect(data['author'], '你');
    expect(data['author_type'], '用户');
    expect(data['content_truncated'], isTrue);
    expect((data['content'] as String).length, lessThanOrEqualTo(2001));
    expect(data['likes'], 5);
    expect(data['comments'], 4);
    expect(data['views'], 9);
    expect(data['images'], 2);
  });

  test('评论区带作者类型和楼中楼', () {
    final list = detail()['comments_list'] as List;
    expect(list, hasLength(2), reason: '只看顶层评论');

    final first = list.first as Map;
    expect(first['author'], '小满');
    expect(first['author_type'], '固定住民');
    expect(first['content'], '写得好');
    expect(first['likes'], 2);
    final replies = first['replies'] as List;
    expect(replies, hasLength(2));
    expect((replies.first as Map)['author_type'], '临时网民');
    expect((replies.last as Map)['author'], '你');
    expect((replies.last as Map)['author_type'], '用户');

    final second = list.last as Map;
    expect(second['author'], '你');
    expect(second['content'], '另一条顶层');
  });

  test('comments_limit 只取最近的几条顶层，仍按时序展示', () {
    final list = detail(limit: 1)['comments_list'] as List;
    expect(list, hasLength(1));
    expect((list.single as Map)['id'], 'c4');
  });
}
