import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/private_message_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PrivateMessageRepository messages;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    messages = PrivateMessageRepository(db);

    // 私信表对 ai_personas 有外键，住民得先在表里
    for (final id in ['persona_001', 'persona_002']) {
      await db
          .into(db.aiPersonas)
          .insert(AiPersonasCompanion.insert(id: id, name: '住民$id'));
    }
  });

  tearDown(() async => db.close());

  test('我发出去的话，立刻就在会话里', () async {
    await messages.send(personaId: 'persona_001', content: '在吗');

    final thread = await messages.watchThread('persona_001').first;

    expect(thread.length, 1);
    expect(thread.first.fromMe, isTrue);
    expect(thread.first.content, '在吗');
  });

  test('还没到点的话不在会话里，到点了才出现', () async {
    await messages.scheduleIncoming(
      personaId: 'persona_001',
      content: '刚看到你那条，想问问后来怎么样了',
      at: DateTime.now().add(const Duration(minutes: 10)),
    );

    expect(await messages.watchThread('persona_001').first, isEmpty);

    // 把时间戳挪到过去，等于"时间到了"
    await db.customStatement(
      'UPDATE private_messages SET created_at = ?',
      [
        DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      ],
    );

    final thread = await messages.watchThread('persona_001').first;
    expect(thread.length, 1);
    expect(thread.first.fromMe, isFalse);
  });

  test('会话列表按最后一句排，未读数只算收到的', () async {
    await messages.scheduleIncoming(
      personaId: 'persona_001',
      content: '第一条',
      at: DateTime.now().subtract(const Duration(hours: 2)),
    );
    await messages.send(personaId: 'persona_002', content: '我发的');
    await messages.scheduleIncoming(
      personaId: 'persona_001',
      content: '第二条',
      at: DateTime.now().subtract(const Duration(minutes: 5)),
    );

    final list = await messages.watchConversations().first;

    expect(list.length, 2);
    expect(list.first.personaId, 'persona_002', reason: '刚刚说过话的排前面');
    expect(list.last.personaId, 'persona_001');
    expect(list.last.lastMessage, '第二条');
    expect(list.last.unreadCount, 2);
    expect(list.first.unreadCount, 0, reason: '自己发的不算未读');
    expect(list.first.lastFromMe, isTrue);
  });

  test('进会话把它标成已读，红点就没了', () async {
    await messages.scheduleIncoming(
      personaId: 'persona_001',
      content: '在吗',
      at: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    expect(await messages.watchUnreadCount().first, 1);

    await messages.markThreadRead('persona_001');

    expect(await messages.watchUnreadCount().first, 0);
  });

  test('表情包和语音在列表上不铺路径出来', () async {
    await messages.scheduleIncoming(
      personaId: 'persona_001',
      content: 'file:///stickers/开心.png',
      mediaType: 'sticker',
      at: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    final list = await messages.watchConversations().first;
    expect(list.first.lastMessage, '[表情包]');
  });

  test('我最后说的一句还没人接——调度靠它决定要不要让他回一句', () async {
    expect(await messages.hasUnansweredFromMe('persona_001'), isFalse);

    await messages.send(personaId: 'persona_001', content: '那我先回去了');
    expect(await messages.hasUnansweredFromMe('persona_001'), isTrue);

    await messages.scheduleIncoming(
      personaId: 'persona_001',
      content: '好，路上小心',
      at: DateTime.now().add(const Duration(minutes: 3)),
    );
    expect(
      await messages.hasUnansweredFromMe('persona_001'),
      isFalse,
      reason: '已经排上了回应，就算还没到点也不该再排一条',
    );
  });

  test('lastAt 看得见还没到点的那一条', () async {
    await messages.send(personaId: 'persona_001', content: '你好');
    final soon = DateTime.now().add(const Duration(minutes: 5));
    await messages.scheduleIncoming(
      personaId: 'persona_001',
      content: '你好呀',
      at: soon,
    );

    final last = await messages.lastAt('persona_001');
    expect(last!.isAfter(DateTime.now()), isTrue);
  });

  test('从来没聊过的人没有时间戳', () async {
    expect(await messages.lastAt('persona_002'), isNull);
  });
}
