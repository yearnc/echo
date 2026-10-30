import 'package:drift/drift.dart' show TableUpdate;
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/private_message_repository.dart';
import 'package:echo/domain/models/custom_resident.dart';
import 'package:echo/domain/services/dm_voice_service.dart';
import 'package:echo/domain/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTts extends TtsService {
  String? capturedVoiceModel;

  @override
  Future<VoiceClip?> speak({
    required String text,
    required String personaId,
    String voiceModel = '',
    String voiceDescription = '',
    bool wantsDescription = false,
    String referenceAudioPath = '',
    String referenceText = '',
    bool preferLocalClone = false,
  }) async {
    capturedVoiceModel = voiceModel;
    return VoiceClip(
      ref: 'file:/fake.wav',
      transcript: text,
      durationMs: 1200,
      waveform: const [],
    );
  }
}

void main() {
  late AppDatabase db;
  late PrivateMessageRepository messages;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    messages = PrivateMessageRepository(db);

  });

  tearDown(() async => db.close());

  test('我发出去的话，立刻就在会话里', () async {
    await messages.send(personaId: 'persona_001', content: '在吗');

    final thread = await messages.watchThread('persona_001').first;

    expect(thread.length, 1);
    expect(thread.first.fromMe, isTrue);
    expect(thread.first.content, '在吗');
  });

  test('A 的唤醒历史里不会出现 B 的私信', () async {
    await messages.send(personaId: 'resident_a', content: '只给 A 的话');
    await messages.send(personaId: 'resident_b', content: '只给 B 的话');

    final a = await messages.recentTurns('resident_a');
    final b = await messages.recentTurns('resident_b');

    expect(a.map((item) => item.content), ['只给 A 的话']);
    expect(b.map((item) => item.content), ['只给 B 的话']);
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
    // customStatement 不告诉 Drift 哪张表变了；手动通知一次，
    // 等同于“时间到了”触发了一次读取。
    db.notifyUpdates({TableUpdate.onTable(db.privateMessages)});

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

  test('排期消息到点自己冒出来，不用退出重进', () async {
    await messages.scheduleIncoming(
      personaId: 'persona_001',
      content: '我刚忙完',
      at: DateTime.now().add(const Duration(seconds: 1)),
    );

    final emissions = await messages
        .watchThread('persona_001')
        .take(2)
        .toList()
        .timeout(const Duration(seconds: 5));

    expect(emissions.first, isEmpty);
    expect(emissions.last.length, 1);
    expect(emissions.last.first.content, '我刚忙完');
  });

  test('图片描述和表情包语义跟着消息一起存', () async {
    final id = await messages.send(
      personaId: 'persona_001',
      content: 'file:///pic.jpg',
      mediaType: 'image',
    );
    await messages.attachCaption(id, '桌上有一碗热汤面');

    final thread = await messages.watchThread('persona_001').first;
    expect(thread.single.mediaType, 'image');
    expect(thread.single.caption, '桌上有一碗热汤面');
  });

  test('语音合成好了再挂上去，文字不会丢', () async {
    final id = await messages.send(
      personaId: 'persona_001',
      content: '今天风挺大的',
    );
    await messages.attachVoice(
      messageId: id,
      voicePath: 'file:/voice.wav',
      transcript: '今天风挺大的',
    );

    final thread = await messages.watchThread('persona_001').first;
    expect(thread.single.mediaType, 'voice');
    expect(thread.single.voicePath, 'file:/voice.wav');
    expect(thread.single.transcript, '今天风挺大的');
  });

  test('合成语音时用住民自己的音色，失败不会落一条假文字', () async {
    final tts = _FakeTts();
    final service = DmVoiceService(tts: tts);
    final resident = CustomResident(
      id: 'persona_001',
      name: '小满',
      voiceEnabled: true,
      voiceRef: 'local:42',
      createdAt: DateTime(2026, 10, 1),
    );

    final result = await service.synthesize(
      resident: resident,
      text: '今天风挺大的',
    );

    expect(result.clip, isNotNull);
    expect(result.clip!.transcript, '今天风挺大的');
    expect(tts.capturedVoiceModel, 'local:42');
  });

  test('没开语音的住民不会被偷偷换成语音', () async {
    final tts = _FakeTts();
    final service = DmVoiceService(tts: tts);
    final resident = CustomResident(
      id: 'persona_001',
      name: '小满',
      createdAt: DateTime(2026, 10, 1),
    );

    final result = await service.synthesize(
      resident: resident,
      text: '普通一句话',
    );
    expect(result.clip, isNull);
    expect(result.error, isNotEmpty);
    expect(tts.capturedVoiceModel, isNull);
  });

  test('语音消息一开始就是语音，不会先以文字出现', () async {
    await messages.scheduleIncoming(
      personaId: 'persona_001',
      content: '今天风挺大的',
      mediaType: 'voice',
      voicePath: 'file:/voice.wav',
      transcript: '今天风挺大的',
      at: DateTime.now().subtract(const Duration(seconds: 1)),
    );

    final thread = await messages.watchThread('persona_001').first;
    expect(thread.single.mediaType, 'voice');
    expect(thread.single.content, '今天风挺大的');
    expect(thread.single.voicePath, 'file:/voice.wav');
  });

  test('删掉会话之后，列表和会话里都不再出现', () async {
    await messages.scheduleIncoming(
      personaId: 'persona_001',
      content: '再见啦',
      at: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    await messages.deleteThread('persona_001');

    expect(await messages.watchThread('persona_001').first, isEmpty);
    expect(await messages.watchConversations().first, isEmpty);
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
