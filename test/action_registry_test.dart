import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/media/media_service.dart';
import 'package:echo/data/repositories/custom_resident_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/private_message_repository.dart';
import 'package:echo/data/repositories/resident_memory_repository.dart';
import 'package:echo/data/repositories/sticker_repository.dart';
import 'package:echo/domain/models/custom_resident.dart';
import 'package:echo/domain/services/action_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ActionRegistry actions;
  late PrivateMessageRepository messages;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    messages = PrivateMessageRepository(db);
    actions = ActionRegistry(
      db: db,
      residents: CustomResidentRepository(db),
      memories: ResidentMemoryRepository(db),
      messages: messages,
      posts: PostRepository(db),
      stickers: StickerRepository(db, const MediaService()),
    );

    await CustomResidentRepository(db).upsert(
      CustomResident(
        id: 'resident_001',
        name: '小满',
        createdAt: DateTime(2026, 10, 1),
      ),
    );
  });

  tearDown(() async => db.close());

  test('同一个幂等键只发一次', () async {
    final first = await actions.sendDirectMessage(
      residentId: 'resident_001',
      content: '在吗',
      idempotencyKey: 'dm:1',
    );
    final second = await actions.sendDirectMessage(
      residentId: 'resident_001',
      content: '在吗',
      idempotencyKey: 'dm:1',
    );

    expect(first.ok, isTrue);
    expect(second.ok, isTrue);
    expect(second.data['replayed'], isTrue);
    expect(await db.select(db.privateMessages).get(), hasLength(1));
  });

  test('私信不再有每日额度', () async {
    // 用户发来的消息要能被正常接住；额度只该防刷屏，
    // 不该让住民回一句“今天额度满了”。
    for (var i = 0; i < 20; i++) {
      final result = await actions.sendDirectMessage(
        residentId: 'resident_001',
        content: '第 $i 句',
        idempotencyKey: 'dm:$i',
      );
      expect(result.ok, isTrue);
    }
  });

  test('固定住民发动态不再受每天一条的频率限制', () async {
    final first = await actions.createResidentPost(
      residentId: 'resident_001',
      content: '今天桂花开了',
      idempotencyKey: 'post:1',
    );
    final second = await actions.createResidentPost(
      residentId: 'resident_001',
      content: '第二条',
      idempotencyKey: 'post:2',
    );

    expect(first.ok, isTrue);
    expect(second.ok, isTrue);
    expect(await db.select(db.posts).get(), hasLength(2));
  });

  test('记忆写入后能检索到，并且重复来源不写第二次', () async {
    final wrote = await actions.writeMemory(
      residentId: 'resident_001',
      summary: '他最近在学做菜',
      sourceId: 'post_1',
      idempotencyKey: 'mem:1',
    );
    expect(wrote.ok, isTrue);

    final again = await actions.writeMemory(
      residentId: 'resident_001',
      summary: '他最近在学做菜',
      sourceId: 'post_1',
      idempotencyKey: 'mem:2',
    );
    expect(again.message, contains('已经记过'));

    final found = await actions.searchMemories(
      residentId: 'resident_001',
      query: '做菜',
    );
    final list = found.data['memories'] as List;
    expect(list, hasLength(1));
    expect((list.single as Map)['summary'], contains('做菜'));
  });

  test('固定住民能自己改、自己删记忆', () async {
    final repo = ResidentMemoryRepository(db);
    await actions.writeMemory(
      residentId: 'resident_001',
      summary: '他喜欢喝热可可',
      idempotencyKey: 'mem:1',
    );
    final original = (await repo.recent('resident_001')).single;

    final updated = await actions.updateMemory(
      residentId: 'resident_001',
      memoryId: original.id,
      summary: '他更喜欢茉莉花茶，热可可是备选',
      idempotencyKey: 'memup:1',
    );
    expect(updated.ok, isTrue);
    expect((await repo.recent('resident_001')).single.summary, contains('茉莉花茶'));

    final deleted = await actions.deleteMemory(
      residentId: 'resident_001',
      memoryId: original.id,
      idempotencyKey: 'memdel:1',
    );
    expect(deleted.ok, isTrue);
    expect(await repo.recent('resident_001'), isEmpty);
  });

  test('不能改别人的记忆', () async {
    await CustomResidentRepository(db).upsert(
      CustomResident(
        id: 'resident_002',
        name: '阿岚',
        createdAt: DateTime(2026, 10, 1),
      ),
    );
    final repo = ResidentMemoryRepository(db);
    await actions.writeMemory(
      residentId: 'resident_002',
      summary: '他养了一只猫',
      idempotencyKey: 'mem:1',
    );
    final item = (await repo.recent('resident_002')).single;

    final outcome = await actions.updateMemory(
      residentId: 'resident_001',
      memoryId: item.id,
      summary: '被改掉了',
      idempotencyKey: 'memup:1',
    );
    expect(outcome.ok, isFalse);
    expect((await repo.recent('resident_002')).single.summary, contains('猫'));
  });

  test('关掉记忆的人不写也不查', () async {
    await CustomResidentRepository(db).upsert(
      CustomResident(
        id: 'resident_001',
        name: '小满',
        memoryEnabled: false,
        createdAt: DateTime(2026, 10, 1),
      ),
    );

    final wrote = await actions.writeMemory(
      residentId: 'resident_001',
      summary: '记住了什么',
      idempotencyKey: 'mem:off',
    );
    final found = await actions.searchMemories(
      residentId: 'resident_001',
      query: '什么',
    );

    expect(wrote.ok, isFalse);
    expect(found.ok, isFalse);
  });
}
