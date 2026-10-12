import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/services/comment_thread.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = DateTime(2026, 10, 12, 20);

  PostComment comment(
    String id, {
    String? parentId,
    int minutes = 0,
    String? personaId = 'persona_001',
  }) => PostComment(
    id: id,
    postId: 'p1',
    personaId: personaId,
    content: '评论 $id',
    parentId: parentId,
    createdAt: base.add(Duration(minutes: minutes)),
  );

  List<String> order(List<ThreadedComment> threaded) =>
      [for (final item in threaded) item.comment.id];

  test('回复跟在被回复的那条后面', () {
    final threaded = CommentThreads.build([
      comment('a'),
      comment('b', minutes: 10),
      comment('a1', parentId: 'a', minutes: 5),
    ]);

    expect(order(threaded), ['a', 'a1', 'b']);
    expect(threaded[1].depth, 1);
    expect(threaded[1].isReply, isTrue);
  });

  test('三层楼会被压到两层，但一条都不丢', () {
    final threaded = CommentThreads.build([
      comment('a'),
      comment('a1', parentId: 'a', minutes: 1),
      comment('a2', parentId: 'a1', minutes: 2),
    ]);

    expect(order(threaded), ['a', 'a1', 'a2']);
    expect(threaded.map((item) => item.depth), [0, 1, 1], reason: '缩进到头了');
  });

  test('父评论不在这批里时，它自己当顶层——不能让它消失', () {
    final threaded = CommentThreads.build([
      comment('孤', parentId: '被删掉的'),
    ]);

    expect(order(threaded), ['孤']);
    expect(threaded.single.depth, 0);
  });

  test('数据坏了绕成环也不会转不出来', () {
    final threaded = CommentThreads.build([
      PostComment(
        id: 'x',
        postId: 'p1',
        content: '我回我自己',
        parentId: 'y',
        createdAt: base,
      ),
      PostComment(
        id: 'y',
        postId: 'p1',
        content: '它回我',
        parentId: 'x',
        createdAt: base.add(const Duration(minutes: 1)),
      ),
    ]);

    expect(threaded.length, 2, reason: '两条都还在，只是当顶层排');
  });

  test('空评论区不炸', () {
    expect(CommentThreads.build(const []), isEmpty);
  });

  test('顺序：顶层按时间，回复跟着自己的父走', () {
    final threaded = CommentThreads.build([
      comment('早'),
      comment('中', minutes: 5),
      comment('中1', parentId: '中', minutes: 6),
      comment('晚', minutes: 10),
    ]);

    expect(order(threaded), ['早', '中', '中1', '晚']);
  });
}
