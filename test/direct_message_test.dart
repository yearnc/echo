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
import 'package:echo/domain/models/custom_resident.dart';
import 'package:echo/domain/models/resident_memory.dart';
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

  group('固定住民', () {
    Future<void> seedResident({
      String id = 'resident_001',
      String? opening,
    }) async {
      await CustomResidentRepository(db).upsert(
        CustomResident(
          id: id,
          name: '小满',
          description: '住楼下，喜欢拍照',
          firstMessage: opening ?? '',
          createdAt: DateTime(2026, 10, 1),
        ),
      );
    }

    test('不需要关系门槛，配了开场白就用原话开口', () async {
      await seedResident(opening: '今天楼下桂花开了，你闻到没有');

      expect(await service.tick(), 1);

      final rows = await db.select(db.privateMessages).get();
      expect(rows, hasLength(1));
      expect(rows.single.direction, 'in');
      expect(rows.single.content, '今天楼下桂花开了，你闻到没有');
      expect(
        rows.single.createdAt,
        greaterThan(DateTime.now().millisecondsSinceEpoch),
        reason: '先搁一会儿再送到，不秒发',
      );
    });

    test('没写开场白，也会按人设起个头', () async {
      await seedResident();

      expect(await service.tick(), 1);

      final rows = await db.select(db.privateMessages).get();
      expect(rows.single.direction, 'in');
      expect(rows.single.content, isNotEmpty);
    });

    test('用户说了一句，固定住民会接住', () async {
      await seedResident();
      await db.delete(db.privateMessages).go();
      await messages.send(personaId: 'resident_001', content: '我在楼下');

      expect(await service.tick(), 1);

      final rows = await db.select(db.privateMessages).get();
      rows.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      expect(rows.last.direction, 'in');
      expect(rows.last.content, isNotEmpty);
    });

    test('接话时带上记忆摘要', () async {
      await seedResident();
      await ResidentMemoryRepository(db).add(
        ResidentMemory(
          id: 'mem_1',
          residentId: 'resident_001',
          source: 'post',
          summary: '他最近在学做菜',
          content: '最近在学做菜',
          createdAt: DateTime(2026, 10, 18),
          updatedAt: DateTime(2026, 10, 18),
        ),
      );
      await messages.send(personaId: 'resident_001', content: '今天又做饭了');

      final recording = _RecordingGenerator();
      final withMemory = DirectMessageService(
        db: db,
        messages: messages,
        relationships: relations,
        personas: _FixedPersonas(personas),
        residents: CustomResidentRepository(db),
        memories: ResidentMemoryRepository(db),
        generator: recording,
        random: Random(3),
      );

      await withMemory.tick();

      expect(
        recording.lastRelations['resident_001']?.memorySummary,
        contains('学做菜'),
      );
    });
  });

  test('开场白只出现一次，重复进聊天页不会再说一遍', () async {
    final residents = CustomResidentRepository(db);
    await residents.upsert(
      CustomResident(
        id: 'resident_opening',
        name: '小满',
        firstMessage: '你来啦。',
        createdAt: DateTime(2026, 10, 1),
      ),
    );

    expect(await service.ensureOpening('resident_opening'), isTrue);
    expect(await service.ensureOpening('resident_opening'), isFalse);

    final thread = await messages.watchThread('resident_opening').first;
    expect(
      thread.where((message) => message.content == '你来啦。').length,
      1,
    );
  });
}

/// 记录 `relations` 的生成器：用来验证记忆有没有真的进到提示词上下文。
class _RecordingGenerator extends SampleContentGenerator {
  _RecordingGenerator() : super(random: Random(1));

  Map<String, RelationshipState> lastRelations = const {};

  @override
  Future<Map<String, String>> directMessages({
    required List<DirectThread> threads,
    Map<String, RelationshipState> relations = const {},
  }) async {
    lastRelations = relations;
    return {
      for (final thread in threads) thread.persona.id: '嗯，我在听。',
    };
  }
}
