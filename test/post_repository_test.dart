// 前缀导入：drift 的 isNull/isNotNull 会与 matcher 的同名匹配器冲突
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/domain/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

/// 仓储层测试：用内存数据库，不碰真实文件。
void main() {
  late AppDatabase db;
  late PostRepository posts;
  late InteractionRepository interactions;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    posts = PostRepository(db);
    interactions = InteractionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('PostRepository', () {
    test('新建的帖子能被读出来', () async {
      await posts.create(content: '第一条帖子', scope: 'echo');

      final list = await posts.watchFeed(scope: 'echo').first;

      expect(list, hasLength(1));
      expect(list.first.content, '第一条帖子');
      expect(list.first.scope, 'echo');
    });

    test('scope 过滤生效：echo 与 clear 互不串台', () async {
      await posts.create(content: '回响里的', scope: 'echo');
      await posts.create(content: '清醒里的', scope: 'clear');

      final echoFeed = await posts.watchFeed(scope: 'echo').first;
      final clearFeed = await posts.watchFeed(scope: 'clear').first;
      final all = await posts.watchFeed().first;

      expect(echoFeed.map((p) => p.content), ['回响里的']);
      expect(clearFeed.map((p) => p.content), ['清醒里的']);
      expect(all, hasLength(2));
    });

    test('图片引用能往返（JSON 编解码）', () async {
      await posts.create(
        content: '带图的',
        images: const ['asset:assets/demo/sky_demo.jpg', 'file:/tmp/a.png'],
      );

      final post = (await posts.watchFeed().first).single;

      expect(post.images, hasLength(2));
      expect(post.images.first, startsWith('asset:'));
      expect(post.hasImages, isTrue);
    });

    test('软删除后不再出现在信息流里', () async {
      final id = await posts.create(content: '要被删的');
      await posts.softDelete(id);

      expect(await posts.watchFeed().first, isEmpty);
      expect(await posts.findById(id), isNull);
    });

    test('信息流按时间倒序', () async {
      await posts.create(content: '较早');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await posts.create(content: '较晚');

      final list = await posts.watchFeed().first;

      expect(list.first.content, '较晚');
      expect(list.last.content, '较早');
    });

    test('watchById 能订阅到单条帖子', () async {
      final id = await posts.create(content: '单条');
      final post = await posts.watchById(id).first;

      expect(post, isNotNull);
      expect(post!.content, '单条');
    });
  });

  group('InteractionRepository', () {
    /// 造一条帖子 + 一条已完成的评论，返回互动 id。
    Future<String> seedComment({
      String type = 'comment',
      String status = 'done',
    }) async {
      final postId = await posts.create(content: '被评论的帖子');

      await db.into(db.aiPersonas).insert(
            AiPersonasCompanion.insert(id: 'persona_test', name: '测试住民'),
          );
      await db.into(db.aiInteractions).insert(
            AiInteractionsCompanion.insert(
              id: 'i_1',
              postId: postId,
              personaId: 'persona_test',
              type: type,
              content: const drift.Value('这是一条评论'),
              scheduledAt: DateTime.now().millisecondsSinceEpoch,
              executedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
              status: drift.Value(status),
            ),
          );
      return postId;
    }

    test('只有 done 的评论会进评论区', () async {
      final postId = await seedComment(status: 'pending');

      final visible = await interactions.watchComments(postId).first;

      expect(visible, isEmpty, reason: '未到点的互动不该提前出现');
    });

    test('done 的评论文本与媒体类型解析正确', () async {
      final postId = await seedComment();

      final visible = await interactions.watchComments(postId).first;

      expect(visible, hasLength(1));
      expect(visible.first.content, '这是一条评论');
      expect(visible.first.mediaType, CommentMedia.text);
      expect(visible.first.isAi, isTrue);
    });

    test('点赞类互动不进评论区', () async {
      final postId = await seedComment(type: 'like');

      final visible = await interactions.watchComments(postId).first;

      expect(visible, isEmpty);
    });

    test('同一人格可以对同一帖子评论多次（连续回复/追问）', () async {
      final postId = await posts.create(content: '被连续回复的帖子');
      await db.into(db.aiPersonas).insert(
            AiPersonasCompanion.insert(id: 'persona_chatty', name: '话痨住民'),
          );

      for (var i = 0; i < 3; i++) {
        await db.into(db.aiInteractions).insert(
              AiInteractionsCompanion.insert(
                id: 'chatty_$i',
                postId: postId,
                personaId: 'persona_chatty',
                type: 'comment',
                content: drift.Value('第 ${i + 1} 条'),
                scheduledAt: DateTime.now().millisecondsSinceEpoch,
                executedAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
                status: const drift.Value('done'),
              ),
            );
      }

      final visible = await interactions.watchComments(postId).first;

      expect(visible, hasLength(3),
          reason: '同一住民的多次评论都必须留下——这是"连续回复"效果的前提');
    });

    test('markExecuted 会把排队中的互动转为可见', () async {
      final postId = await seedComment(status: 'pending');
      expect(await interactions.countPending(), 1);

      await interactions.markExecuted('i_1');

      expect(await interactions.countPending(), 0);
      expect(await interactions.watchComments(postId).first, hasLength(1));
    });
  });
}
