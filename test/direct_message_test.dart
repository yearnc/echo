import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/custom_resident_repository.dart';
import 'package:echo/data/repositories/persona_repository.dart';
import 'package:echo/data/repositories/private_message_repository.dart';
import 'package:echo/data/repositories/relationship_repository.dart';
import 'package:echo/data/repositories/resident_memory_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/domain/services/content_generator.dart';
import 'package:echo/domain/services/direct_message_service.dart';
import 'package:echo/domain/services/relationship_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固定的一批住民，不去读 assets——这一层要测的是"谁来找你、什么时候来"。
class _FixedPersonas implements PersonaRepository {
  _FixedPersonas(this.pool);

  final List<AiPersona> pool;

  @override
  Future<List<AiPersona>> loadAll() async => pool;
}

void main() {
  late AppDatabase db;
  late PrivateMessageRepository messages;
  late RelationshipRepository relations;
  late DirectMessageService service;

  const personas = [
    AiPersona(id: 'persona_000', name: '住民0', commentSamples: ['台词']),
    AiPersona(id: 'persona_001', name: '住民1', commentSamples: ['台词']),
  ];

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    messages = PrivateMessageRepository(db);
    relations = RelationshipRepository(db);
    service = DirectMessageService(
      db: db,
      messages: messages,
      relationships: relations,
      personas: _FixedPersonas(personas),
      residents: CustomResidentRepository(db),
      memories: ResidentMemoryRepository(db),
      generator: SampleContentGenerator(random: Random(3)),
      random: Random(3),
    );

    for (final persona in personas) {
      await db
          .into(db.aiPersonas)
          .insert(AiPersonasCompanion.insert(id: persona.id, name: persona.name));
    }
  });

  tearDown(() async => db.close());

  Future<void> setLevel(String personaId, int level) async {
    await db
        .into(db.aiRelationships)
        .insertOnConflictUpdate(
          AiRelationshipsCompanion.insert(
            personaId: personaId,
            relationshipLevel: Value(level),
            intimacy: Value(RelationshipRules.thresholds[level]),
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> enterClearMode() async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'app.mode',
            value: 'clear',
            scope: const Value('shared'),
          ),
        );
  }

  test('还只是眼熟的人，不会来敲你的门', () async {
    await setLevel('persona_000', 1);

    expect(await service.tick(), 0);
    expect(await messages.lastAt('persona_000'), isNull);
  });

  test('到了互关，他会发来第一句——但先搁一会儿才送到', () async {
    await setLevel('persona_000', DirectMessageService.proactiveTier);

    expect(await service.tick(), 1);

    // 还没到点：会话列表里暂时看不见
    expect(await messages.watchThread('persona_000').first, isEmpty);

    final at = await messages.lastAt('persona_000');
    expect(at, isNotNull);
    expect(at!.isAfter(DateTime.now()), isTrue, reason: '该落在几分钟之后');
  });

  test('二十小时内不会再来敲一次', () async {
    await setLevel('persona_000', DirectMessageService.proactiveTier);
    await setLevel('persona_001', DirectMessageService.proactiveTier);

    expect(await service.tick(), 1);

    final second = await service.tick();
    expect(second, 0, reason: '一开 APP 收到一串"在吗"，那就不像人了');
  });

  test('说过话的人，不会再被当成"第一次来找你"', () async {
    await setLevel('persona_000', DirectMessageService.proactiveTier);
    await messages.scheduleIncoming(
      personaId: 'persona_000',
      content: '在吗？上次你那事儿后来怎么样了',
      at: DateTime.now().subtract(const Duration(hours: 3)),
    );

    expect(await service.tick(), 0, reason: '已经开了场，就不该再"第一次找你"');
  });

  test('你说了话，他会回一句（落在几分钟之后）', () async {
    await messages.send(personaId: 'persona_000', content: '那我先回去了');

    expect(await service.tick(), 1);

    expect(
      await messages.hasUnansweredFromMe('persona_000'),
      isFalse,
      reason: '已经排上回应了',
    );
  });

  test('已经排上回应的，不会被排第二条', () async {
    await messages.send(personaId: 'persona_000', content: '在吗');

    expect(await service.tick(), 1);
    expect(await service.tick(), 0);
  });

  test('清醒模式里不长出虚拟私信', () async {
    await enterClearMode();
    await setLevel('persona_000', DirectMessageService.proactiveTier);
    await messages.send(personaId: 'persona_000', content: '在吗');

    expect(await service.tick(), 0);
  });

}
