import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/post_voice_repository.dart';
import 'package:echo/domain/models/post_voice.dart';
import 'package:echo/domain/models/planned_interaction.dart';

void main() {
  late AppDatabase db;
  late PostRepository posts;
  late PostVoiceRepository voices;
  late InteractionRepository interactions;
  late String postId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    posts = PostRepository(db);
    voices = PostVoiceRepository(db);
    interactions = InteractionRepository(db);
    postId = await posts.create(content: '今天抽卡又歪了', scope: 'echo');

    await voices.insertAll([
      PostVoice(
        id: 'voice_1',
        postId: postId,
        kind: PostVoiceKind.ephemeral,
        name: '三楼的灯',
        createdAt: DateTime(2026, 10, 18, 21),
      ),
      PostVoice(
        id: 'voice_2',
        postId: postId,
        kind: PostVoiceKind.ephemeral,
        name: '大肥鱼',
        createdAt: DateTime(2026, 10, 18, 21, 1),
      ),
    ]);
  });

  tearDown(() async => db.close());

  test('排期评论不带“自带赞”，点赞照常计数', () async {
    await interactions.insertPlanned(postId, [
      PlannedInteraction(
        personaId: 'voice_1',
        type: 'comment',
        scheduledAt: DateTime.now().add(const Duration(minutes: 1)),
        content: '这条不该自带赞',
      ),
      PlannedInteraction(
        personaId: 'voice_2',
        type: 'like',
        scheduledAt: DateTime.now().add(const Duration(minutes: 2)),
      ),
    ]);

    final rows = await db.select(db.aiInteractions).get();
    final comment = rows.firstWhere((row) => row.type == 'comment');
    final like = rows.firstWhere((row) => row.type == 'like');
    expect(comment.likeCount, 0);
    expect(like.likeCount, 1);
  });

  test('AI 可以给评论点赞：幂等、计数，且不会被用户取消赞顶掉', () async {
    await interactions.insertPlanned(postId, [
      PlannedInteraction(
        personaId: 'voice_1',
        type: 'comment',
        scheduledAt: DateTime.now().add(const Duration(minutes: 1)),
        content: '这条会被点赞',
      ),
    ]);
    final commentId = (await db.select(db.aiInteractions).getSingle()).id;

    expect(
      await interactions.addAiCommentLike(
        commentId: commentId,
        voiceId: 'voice_1',
      ),
      isTrue,
    );
    expect(
      await interactions.addAiCommentLike(
        commentId: commentId,
        voiceId: 'voice_2',
      ),
      isTrue,
    );
    expect(await interactions.countAiCommentLikes(commentId), 2);

    // 同一个网民重复点只算一次
    expect(
      await interactions.addAiCommentLike(
        commentId: commentId,
        voiceId: 'voice_1',
      ),
      isFalse,
    );

    final row = await db.select(db.aiInteractions).getSingle();
    expect(row.likeCount, 2);

    // 用户点一下再取消，只动 user 那一行，AI 的赞还在
    await interactions.toggleCommentLike(commentId);
    expect(
      await interactions.watchLikedCommentIds().first,
      contains(commentId),
    );
    await interactions.toggleCommentLike(commentId);
    expect(await interactions.countAiCommentLikes(commentId), 2);
  });

  test('AI 接 AI 能计数、能查重，且不预约系统通知', () async {
    await interactions.insertPlanned(postId, [
      PlannedInteraction(
        personaId: 'voice_1',
        type: 'comment',
        scheduledAt: DateTime.now().add(const Duration(minutes: 3)),
        content: '我也是大保底',
      ),
    ]);
    final top = (await db.select(db.aiInteractions).getSingle()).id;

    await interactions.insertFollowUp(
      postId: postId,
      personaId: 'voice_2',
      content: '笑死，我也是',
      parentId: top,
      scheduledAt: DateTime.now().add(const Duration(minutes: 5)),
      source: 'peer_reply',
    );

    expect(await interactions.countPeerReplies(postId), 1);
    expect(
      await interactions.hasPeerReply(parentId: top, personaId: 'voice_2'),
      isTrue,
    );

    // AI 接 AI 不进“会叫醒手机”的待办，但仍是一条正常评论
    final pending = await interactions.pendingComments();
    expect(pending, hasLength(1));
    expect(pending.single.personaId, 'voice_1');
  });
}
