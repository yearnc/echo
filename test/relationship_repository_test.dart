import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/relationship_repository.dart';
import 'package:echo/domain/services/relationship_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late RelationshipRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RelationshipRepository(db);

    // 关系表对 ai_personas 有外键，所以住民得先在表里——
    // 线上他们是随 assets 播种进来的（B1），测试里就手工插一个。
    for (final id in ['persona_001', 'persona_002']) {
      await db
          .into(db.aiPersonas)
          .insert(AiPersonasCompanion.insert(id: id, name: '住民$id'));
    }
  });

  tearDown(() async => db.close());

  final t0 = DateTime(2026, 10, 12, 9);
  final t1 = t0.add(const Duration(days: 1));

  test('没打过交道的人读出来是陌生，而不是空', () async {
    final state = await repo.load('persona_001');

    expect(state.personaId, 'persona_001');
    expect(state.level, 0);
    expect(state.tierLabel, '陌生');
    expect(state.intimacy, 0);
    expect(state.interactionCount, 0);
    expect(state.lastInteractionAt, isNull);
  });

  test('记一次互动就落下去了，再读还在', () async {
    await repo.record(
      personaId: 'persona_001',
      event: RelationshipEvent.comment,
      at: t0,
    );

    final state = await repo.load('persona_001');

    expect(state.level, 1);
    expect(state.intimacy, 3);
    expect(state.interactionCount, 1);
    expect(state.lastInteractionAt, t0);
  });

  test('隔天的第二次互动是累加，不是覆盖', () async {
    await repo.record(
      personaId: 'persona_001',
      event: RelationshipEvent.comment,
      at: t0,
    );
    await repo.record(
      personaId: 'persona_001',
      event: RelationshipEvent.comment,
      at: t1,
    );

    final state = await repo.load('persona_001');
    expect(state.intimacy, 6);
    expect(state.interactionCount, 2);
  });

  test('loadAll 只给打过交道的人，没来往的不占位', () async {
    await repo.record(
      personaId: 'persona_001',
      event: RelationshipEvent.like,
      at: t0,
    );

    final all = await repo.loadAll();
    expect(all.keys, ['persona_001']);
  });

  test('先记下的记忆，不会被之后的互动挤掉', () async {
    await repo.updateMemory(personaId: 'persona_001', summary: '他拍过一张天空照');
    await repo.record(
      personaId: 'persona_001',
      event: RelationshipEvent.comment,
      at: t0,
    );

    final state = await repo.load('persona_001');
    expect(state.memorySummary, '他拍过一张天空照');
    expect(state.level, 1);
  });

  test('空摘要不覆盖上一次记住的东西', () async {
    await repo.updateMemory(personaId: 'persona_001', summary: '他拍过一张天空照');
    await repo.updateMemory(personaId: 'persona_001', summary: '   ');

    final state = await repo.load('persona_001');
    expect(state.memorySummary, '他拍过一张天空照');
  });

  test('关注一次，再点一次就取消', () async {
    final followed = await repo.toggleFollow('persona_001');
    expect(followed.followState, 'following');

    final undone = await repo.toggleFollow('persona_001');
    expect(undone.followState, 'none');
  });

  test('他已经关注过你，你这一下就成了互关', () async {
    // 聊两次、够到互关档（十条礼貌回复不该等于一次深夜长谈，这里就是两次私信）
    await repo.record(
      personaId: 'persona_001',
      event: RelationshipEvent.message,
      at: t0,
    );
    await repo.record(
      personaId: 'persona_001',
      event: RelationshipEvent.message,
      at: t0.add(const Duration(hours: 7)),
    );
    expect((await repo.load('persona_001')).followState, 'followed');

    final followed = await repo.toggleFollow('persona_001');
    expect(followed.followState, 'mutual');

    // 再点一次是取消：他还在关注你，所以退回到"他关注了你"
    final undone = await repo.toggleFollow('persona_001');
    expect(undone.followState, 'followed');
  });

  test('重名的人各记各的', () async {
    await repo.record(
      personaId: 'persona_001',
      event: RelationshipEvent.message,
      at: t0,
    );
    await repo.record(
      personaId: 'persona_002',
      event: RelationshipEvent.like,
      at: t0,
    );

    final all = await repo.loadAll();
    expect(all['persona_001']!.intimacy, 5);
    expect(all['persona_002']!.intimacy, 1);
  });

  test('记忆太长会被截断——它每次请求都要跟着走', () async {
    await repo.updateMemory(personaId: 'persona_001', summary: '很长的记忆' * 40);

    final summary = (await repo.load('persona_001')).memorySummary;

    expect(summary.length, lessThanOrEqualTo(RelationshipRepository.maxMemoryLength + 1));
    expect(summary.endsWith('…'), isTrue);
  });

  test('正常长度的记忆一个字都不动', () async {
    await repo.updateMemory(personaId: 'persona_001', summary: '他上次拍过一张天空照');

    expect((await repo.load('persona_001')).memorySummary, '他上次拍过一张天空照');
  });
}
