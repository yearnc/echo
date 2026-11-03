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
  late ResidentMemoryRepository memories;
  late ActionRegistry actions;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    memories = ResidentMemoryRepository(db);
    actions = ActionRegistry(
      db: db,
      residents: CustomResidentRepository(db),
      memories: memories,
      messages: PrivateMessageRepository(db),
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

  test('同一件事换个说法不会写第二条', () async {
    final first = await actions.writeMemory(
      residentId: 'resident_001',
      summary: '他喜欢喝茉莉花茶',
      sourceId: 'post_1',
      idempotencyKey: 'mem:1',
    );
    expect(first.ok, isTrue);

    final second = await actions.writeMemory(
      residentId: 'resident_001',
      summary: '对方喜欢喝茉莉花茶。',
      sourceId: 'post_2',
      idempotencyKey: 'mem:2',
    );
    expect(second.ok, isTrue);
    expect(second.data['duplicate'], isTrue);
    expect(second.data['memory_id'], first.data['memory_id']);
    expect(await memories.count('resident_001'), 1);
  });

  test('内容不同就照常写', () async {
    await actions.writeMemory(
      residentId: 'resident_001',
      summary: '他喜欢喝茉莉花茶',
      idempotencyKey: 'mem:1',
    );
    final second = await actions.writeMemory(
      residentId: 'resident_001',
      summary: '他在学做菜',
      idempotencyKey: 'mem:2',
    );
    expect(second.data['duplicate'], isNull);
    expect(await memories.count('resident_001'), 2);
  });

  test('写入门挡住寒暄，不落库', () async {
    final blocked = await actions.writeMemory(
      residentId: 'resident_001',
      summary: '晚安',
      idempotencyKey: 'mem:1',
    );
    expect(blocked.ok, isFalse);
    expect(await memories.count('resident_001'), 0);
  });

  test('整理合并是事务：保留一条、软删其余，且能恢复', () async {
    final first = await actions.writeMemory(
      residentId: 'resident_001',
      summary: '他喜欢喝茉莉花茶',
      idempotencyKey: 'mem:1',
    );
    final second = await actions.writeMemory(
      residentId: 'resident_001',
      summary: '他养了一只猫',
      idempotencyKey: 'mem:2',
    );
    await actions.writeMemory(
      residentId: 'resident_001',
      summary: '他下周三要去比赛',
      idempotencyKey: 'mem:3',
    );
    expect(await memories.count('resident_001'), 3);

    final keptId = first.data['memory_id'] as String;
    final mergedId = second.data['memory_id'] as String;
    final result = await actions.consolidateMemories(
      residentId: 'resident_001',
      keepMemoryId: keptId,
      mergeMemoryIds: [mergedId],
      summary: '他喜欢喝茉莉花茶，还养了一只猫',
      idempotencyKey: 'merge:1',
    );
    expect(result.ok, isTrue);
    expect(result.data['merged'], 1);
    expect(await memories.count('resident_001'), 2);
    expect((await memories.recent('resident_001')).first.summary, contains('猫'));

    final deleted = await memories.recentlyDeleted('resident_001');
    expect(deleted.single.id, mergedId);
    await memories.restoreDeleted(mergedId);
    expect(await memories.count('resident_001'), 3);
  });

  test('不能把别人的记忆并进来', () async {
    await CustomResidentRepository(db).upsert(
      CustomResident(
        id: 'resident_002',
        name: '阿岚',
        createdAt: DateTime(2026, 10, 1),
      ),
    );
    final mine = await actions.writeMemory(
      residentId: 'resident_001',
      summary: '他喜欢喝茉莉花茶',
      idempotencyKey: 'mem:1',
    );
    final other = await actions.writeMemory(
      residentId: 'resident_002',
      summary: '他养了一只猫',
      idempotencyKey: 'mem:2',
    );
    final result = await actions.consolidateMemories(
      residentId: 'resident_001',
      keepMemoryId: mine.data['memory_id'] as String,
      mergeMemoryIds: [other.data['memory_id'] as String],
      idempotencyKey: 'merge:1',
    );
    expect(result.ok, isTrue);
    expect(result.data['merged'], 0);
    expect(await memories.count('resident_002'), 1);
  });
}
