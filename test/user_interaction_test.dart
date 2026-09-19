import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/domain/services/interaction_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PostRepository posts;
  late InteractionRepository interactions;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    posts = PostRepository(db);
    interactions = InteractionRepository(db);

    await db
        .into(db.aiPersonas)
        .insert(AiPersonasCompanion.insert(id: 'persona_001', name: '住民'));
  });

  tearDown(() async => db.close());

  group('点赞', () {
    test('点一下赞，再点一下取消', () async {
      final postId = await posts.create(content: '帖子', scope: 'echo');

      expect((await posts.findById(postId))!.likedByMe, isFalse);
      expect((await posts.findById(postId))!.likeCount, 0);

      expect(await posts.toggleLike(postId), isTrue);
      var post = await posts.findById(postId);
      expect(post!.likedByMe, isTrue);
      expect(post.likeCount, 1);

      expect(await posts.toggleLike(postId), isFalse);
      post = await posts.findById(postId);
      expect(post!.likedByMe, isFalse);
      expect(post.likeCount, 0);
    });

    test('住民的动态也能点', () async {
      final postId = await posts.createResidentPost(
        personaId: 'persona_001',
        content: '住民的动态',
      );

      await posts.toggleLike(postId);

      final post = await posts.findById(postId);
      expect(post!.likedByMe, isTrue);
      expect(post.likeCount, 1);
    });

    test('计数不会被减成负数', () async {
      // 理论上不该出现（没点过就取消不了），但真出现时也不该在界面上
      // 显示一个负数的赞
      final postId = await posts.create(content: '帖子', scope: 'echo');
      await posts.setCounters(postId, likes: 0);

      await posts.toggleLike(postId);
      await posts.toggleLike(postId);

      expect((await posts.findById(postId))!.likeCount, 0);
    });

    test('帖子不存在时安静返回', () async {
      expect(await posts.toggleLike('没有这条帖子'), isFalse);
    });
  });

  group('评论', () {
    test('我说的话进评论区，而且没有住民身份', () async {
      final postId = await posts.create(content: '帖子', scope: 'echo');

      await interactions.addMyComment(postId: postId, content: '沙发');

      final comments = await interactions.watchComments(postId).first;
      expect(comments.length, 1);
      expect(comments.single.content, '沙发');
      expect(
        comments.single.personaId,
        isNull,
        reason: '这条是本机用户说的，不是一个住民',
      );
      expect(comments.single.isAi, isFalse);
    });

    test('评论数跟着涨', () async {
      final postId = await posts.create(content: '帖子', scope: 'echo');

      await interactions.addMyComment(postId: postId, content: '一');
      await interactions.addMyComment(postId: postId, content: '二');

      expect((await posts.findById(postId))!.commentCount, 2);
    });

    test('住民的和我的合成一条时间线，按先后排好', () async {
      final postId = await posts.create(content: '帖子', scope: 'echo');

      await interactions.insertExecutedComment(
        id: 'c1',
        postId: postId,
        personaId: 'persona_001',
        content: '住民的评论',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await interactions.addMyComment(postId: postId, content: '我的回复');

      final comments = await interactions.watchComments(postId).first;

      expect(comments.map((c) => c.content), ['住民的评论', '我的回复']);
      expect(comments.first.personaId, 'persona_001');
      expect(comments.last.personaId, isNull);
    });

    test('还没到点的住民评论不会提前出现', () async {
      final postId = await posts.create(content: '帖子', scope: 'echo');
      await interactions.insertPlanned(postId, [
        PlannedInteraction(
          personaId: 'persona_001',
          type: 'comment',
          content: '几小时后才到',
          scheduledAt: DateTime.now().add(const Duration(hours: 3)),
        ),
      ]);

      final comments = await interactions.watchComments(postId).first;
      expect(comments, isEmpty, reason: '排队里的东西不该剧透');
    });

    test('别的帖子的评论不会串进来', () async {
      final mine = await posts.create(content: '我的帖子', scope: 'echo');
      final other = await posts.create(content: '别的帖子', scope: 'echo');

      await interactions.addMyComment(postId: other, content: '在别处说的');

      expect(await interactions.watchComments(mine).first, isEmpty);
    });
  });

  group('评论的赞', () {
    test('点一下赞，再点一下取消', () async {
      final postId = await posts.create(content: '帖子', scope: 'echo');
      await interactions.addMyComment(postId: postId, content: '我发的');
      final commentId = (await interactions.watchComments(
        postId,
      ).first).single.id;

      expect(await interactions.watchLikedCommentIds().first, isEmpty);

      expect(await interactions.toggleCommentLike(commentId), isTrue);
      expect(await interactions.watchLikedCommentIds().first, {commentId});

      expect(await interactions.toggleCommentLike(commentId), isFalse);
      expect(await interactions.watchLikedCommentIds().first, isEmpty);
    });

    test('住民的评论也能赞', () async {
      final postId = await posts.create(content: '帖子', scope: 'echo');
      await interactions.insertExecutedComment(
        id: 'c1',
        postId: postId,
        personaId: 'persona_001',
        content: '住民的评论',
      );

      expect(await interactions.toggleCommentLike('c1'), isTrue);
      expect(await interactions.watchLikedCommentIds().first, {'c1'});
    });
  });

  group('回复评论', () {
    test('回复带上父评论和被回复的人', () async {
      final postId = await posts.create(content: '帖子', scope: 'echo');
      await interactions.insertExecutedComment(
        id: 'c1',
        postId: postId,
        personaId: 'persona_001',
        content: '住民的评论',
      );

      await interactions.addMyComment(
        postId: postId,
        content: '我也这么觉得',
        parentId: 'c1',
        replyToName: '住民',
      );

      final mine = (await interactions.watchComments(postId).first).last;
      expect(mine.content, '我也这么觉得');
      expect(mine.parentId, 'c1');
      expect(mine.replyToName, '住民');
    });

    test('普通发言没有回复对象', () async {
      final postId = await posts.create(content: '帖子', scope: 'echo');
      await interactions.addMyComment(postId: postId, content: '随便说一句');

      final mine = (await interactions.watchComments(postId).first).single;
      expect(mine.parentId, isNull);
      expect(mine.replyToName, isNull);
    });
  });
}
