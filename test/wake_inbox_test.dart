import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/custom_resident_repository.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/notification_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/private_message_repository.dart';
import 'package:echo/data/repositories/resident_inbox_repository.dart';
import 'package:echo/domain/models/custom_resident.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ResidentInboxRepository inbox;
  late PostRepository posts;
  late InteractionRepository interactions;
  late PrivateMessageRepository messages;
  late NotificationRepository notifications;

  const residentId = 'resident_001';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    inbox = ResidentInboxRepository(db);
    posts = PostRepository(db);
    interactions = InteractionRepository(db);
    messages = PrivateMessageRepository(db);
    notifications = NotificationRepository(db);

    await CustomResidentRepository(db).upsert(
      CustomResident(id: residentId, name: '小满', createdAt: DateTime.now()),
    );
  });

  tearDown(() async => db.close());

  test('别人在我帖子下评论，会进收件箱；处理过就不再出现', () async {
    final postId = await posts.createResidentPost(
      residentId: residentId,
      content: '今天桂花开了',
    );
    final commentId = await interactions.addMyComment(
      postId: postId,
      content: '闻起来是什么味道',
    );

    final added = await inbox.sync(residentId);
    final pending = await inbox.pending(residentId);

    expect(added, 1);
    expect(pending, hasLength(1));
    expect(pending.first.kind, ResidentInboxRepository.kindCommentOnPost);
    expect(pending.first.refId, commentId);
    expect(pending.first.summary, contains('闻起来'));

    await inbox.markHandled([pending.first.id], decision: 'replied');

    expect(await inbox.pending(residentId), isEmpty);
    // 重复 sync 不会写第二条（确定 id + insertOrIgnore）
    await inbox.sync(residentId);
    expect(await inbox.pending(residentId), isEmpty);
    expect(
      await db.select(db.residentInboxItems).get(),
      hasLength(1),
    );
  });

  test('用户发来的私信，在他还没回之前一直是一条待办', () async {
    await messages.send(personaId: residentId, content: '在吗');

    await inbox.sync(residentId);
    final pending = await inbox.pending(residentId);

    expect(pending, hasLength(1));
    expect(pending.first.kind, ResidentInboxRepository.kindDm);

    // 他回了一句之后，这条私信不该再算“没处理”。
    await messages.scheduleIncoming(
      personaId: residentId,
      content: '在的',
      at: DateTime.now().add(const Duration(seconds: 1)),
    );
    await inbox.markAllHandled(residentId, decision: 'replied');
    await inbox.sync(residentId);

    expect(await inbox.pending(residentId), isEmpty);
  });

  test('排到未来的回复，不会挡住用户新发的话', () async {
    await messages.send(personaId: residentId, content: '在吗');
    // 住民先排了一句“过一会儿才出现”的回复。
    await messages.scheduleIncoming(
      personaId: residentId,
      content: '在的',
      at: DateTime.now().add(const Duration(minutes: 1)),
    );

    // 用户在等待窗口里又补了一句：在它真正出现之前，仍算没回过。
    await messages.send(personaId: residentId, content: '怎么不理我');

    await inbox.sync(residentId);
    final pending = await inbox.pending(residentId);
    final dms = pending
        .where((item) => item.kind == ResidentInboxRepository.kindDm)
        .toList();

    expect(dms, hasLength(2), reason: '两条用户消息都应该被看到');
    expect(dms.map((item) => item.summary), containsAll(['在吗', '怎么不理我']));
  });

  test('点赞通知合并成一行，人数累加', () async {
    final postId = await posts.create(content: '今天很累');

    final first = await notifications.mergeLike(
      postId: postId,
      actorName: '半盏茶',
      count: 1,
    );
    expect(first, '半盏茶 赞了你的帖子');

    final second = await notifications.mergeLike(
      postId: postId,
      actorName: '第七码头',
      count: 2,
    );
    expect(second, contains('等 3 人'));

    final rows = await db.select(db.notificationLogs).get();
    expect(rows, hasLength(1), reason: '同一条帖子只剩一行通知');
    expect(rows.single.actorCount, 3);
    expect(rows.single.actorNames, contains('半盏茶'));
  });

  test('图片评论也能带一句话', () async {
    final postId = await posts.create(content: '随手拍的天空');

    final id = await interactions.addMyComment(
      postId: postId,
      content: 'file:/tmp/sticker.png',
      caption: '这个表情太合适了',
      mediaType: 'image',
    );

    final comments = await interactions.watchComments(postId).first;
    final mine = comments.firstWhere((item) => item.id == id);

    expect(mine.caption, '这个表情太合适了');
    expect(mine.content, 'file:/tmp/sticker.png');
  });
}
