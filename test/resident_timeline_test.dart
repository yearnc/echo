import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/model_config_repository.dart';
import 'package:echo/data/repositories/private_message_repository.dart';
import 'package:echo/domain/models/model_config.dart';
import 'package:echo/domain/services/model_gateway.dart';
import 'package:echo/domain/services/resident_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PrivateMessageRepository messages;
  late ResidentTimeline timeline;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    messages = PrivateMessageRepository(db);
    timeline = ResidentTimeline(
      db,
      messages,
      ModelGateway(ModelConfigRepository(db)),
    );
  });

  tearDown(() async => db.close());

  test('私信全部进时间线，不再只取最近 10 句', () async {
    for (var i = 0; i < 15; i++) {
      await messages.send(personaId: 'a', content: '我第 $i 句');
      await messages.scheduleIncoming(
        personaId: 'a',
        content: '对方第 $i 句',
        at: DateTime.now(),
      );
    }
    await timeline.syncMessages('a');
    final list = await timeline.messages('a');
    expect(list.length, 30);
    expect(list.where((item) => item['role'] == 'user').length, 15);
    expect(list.where((item) => item['role'] == 'assistant').length, 15);
    // 住民视角：用户发来的是“对方”，住民自己说的是“你”。
    final users = list.where((item) => item['role'] == 'user');
    final assistants = list.where((item) => item['role'] == 'assistant');
    expect(users.every((item) => '${item['content']}'.contains('对方')), isTrue);
    expect(
      assistants.every((item) => '${item['content']}'.contains('你：')),
      isTrue,
    );
  });

  test('重复同步幂等；新事件只追加，旧前缀逐字节不变', () async {
    await messages.send(personaId: 'a', content: '第一句');
    await messages.send(personaId: 'a', content: '第二句');
    await timeline.syncMessages('a');
    await timeline.syncMessages('a');

    final before = await timeline.messages('a');
    expect(before.length, 2);

    await timeline.appendScreen(
      'a',
      content: '[10:00] 你看了屏幕：编辑器',
      at: DateTime.now(),
    );
    final after = await timeline.messages('a');

    expect(after.length, 3);
    expect(after.sublist(0, before.length), before);
    expect(after.last['content'], contains('编辑器'));
  });

  test('不同住民的上下文互不串味', () async {
    await messages.send(personaId: 'a', content: '只给 A');
    await messages.send(personaId: 'b', content: '只给 B');
    await timeline.syncMessages('a');
    await timeline.syncMessages('b');

    final a = await timeline.messages('a');
    final b = await timeline.messages('b');
    expect(a.map((item) => item['content']).join(), contains('只给 A'));
    expect(a.map((item) => item['content']).join(), isNot(contains('只给 B')));
    expect(b.map((item) => item['content']).join(), contains('只给 B'));
  });

  test('删掉私信时对应事件也离开上下文，屏幕记录保留', () async {
    await messages.send(personaId: 'a', content: '会被删掉');
    await timeline.syncMessages('a');
    await timeline.appendScreen(
      'a',
      content: '[10:00] 你看了屏幕：窗外',
      at: DateTime.now(),
    );

    await timeline.deleteDmEvents('a');
    final list = await timeline.messages('a');
    expect(list.length, 1);
    expect(list.single['content'], contains('窗外'));
  });

  test('清空上下文不会把旧私信重新灌回来', () async {
    await messages.send(personaId: 'a', content: '旧话');
    await timeline.syncMessages('a');
    await timeline.clearContext('a');
    expect(await timeline.messages('a'), isEmpty);

    await timeline.syncMessages('a');
    expect(await timeline.messages('a'), isEmpty);

    await messages.send(personaId: 'a', content: '新话');
    await timeline.syncMessages('a');
    final list = await timeline.messages('a');
    expect(list.length, 1);
    expect(list.single['content'], contains('新话'));
  });

  test('上下文窗口与 token 粗估', () {
    const config = ModelConfig(
      id: 'x',
      provider: 'custom',
      label: 'x',
      baseUrl: 'https://example.com/v1',
      model: 'my-model',
      contextWindow: 32 * 1024,
    );
    expect(ResidentTimeline.contextWindowFor(config), 32 * 1024);
    const defaulted = ModelConfig(
      id: 'y',
      provider: 'custom',
      label: 'y',
      baseUrl: 'https://example.com/v1',
      model: 'my-model-32k',
    );
    expect(defaulted.contextWindow, 1000000);
    expect(ResidentTimeline.contextWindowFor(defaulted), 1000000);
    expect(ResidentTimeline.estimateTokens('你好'), 2);
    expect(ResidentTimeline.estimateTokens('hello'), 2);
  });
}
