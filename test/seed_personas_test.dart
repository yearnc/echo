import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/db/seed_service.dart';
import 'package:echo/data/repositories/persona_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // rootBundle 要有 binding 才能读 assets
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiPersona 的新字段', () {
    test('圈层与作息都会解析，作息按钟点排好', () {
      final persona = AiPersona.fromJson({
        'id': 'p',
        'name': 'n',
        'circle': '学习',
        'routines': [
          {'hour': 20, 'place': '图书馆', 'activity': '自习'},
          {'hour': 8, 'place': '食堂', 'activity': '早饭'},
        ],
      });

      expect(persona.circle, '学习');
      expect(persona.routines.length, 2);
      expect(persona.routines.first.hour, 8, reason: '播种顺序要跟一天的时间顺序一致');
    });

    test('没有这两个字段时给默认值，不炸', () {
      final persona = AiPersona.fromJson({'id': 'p', 'name': 'n'});
      expect(persona.circle, '');
      expect(persona.routines, isEmpty);
    });

    test('作息缺字段时各自退回空串', () {
      final routine = PersonaRoutine.fromJson({'hour': 9});
      expect(routine.hour, 9);
      expect(routine.place, '');
      expect(routine.activity, '');
    });
  });

  group('住民播种', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async => db.close());

    test('首次启动把所有住民与作息播进来', () async {
      await SeedService(db).seedIfNeeded();

      final rows = await db.select(db.aiPersonas).get();
      final routines = await db.select(db.personaRoutines).get();
      final fromAssets = await const PersonaRepository().loadAll();

      // 人数以 assets 为准，不写死数字——住民还会继续加
      expect(rows.length, fromAssets.length);
      expect(rows.length, greaterThanOrEqualTo(30), reason: '阶段 B 的目标是 30+');
      expect(routines, isNotEmpty);

      // 每个有作息的住民，作息条数要和 assets 里对得上
      for (final persona in fromAssets.where((p) => p.routines.isNotEmpty)) {
        final mine = routines.where((r) => r.personaId == persona.id);
        expect(mine.length, persona.routines.length, reason: persona.name);
      }
    });

    test('重复播种不会插出重复的住民', () async {
      final seed = SeedService(db);
      await seed.seedIfNeeded();
      final first = await db.select(db.aiPersonas).get();

      await seed.seedIfNeeded();
      final second = await db.select(db.aiPersonas).get();

      expect(second.length, first.length);
      expect(second.map((row) => row.id).toSet().length, second.length);
    });

    test('老库缺的住民会被补上', () async {
      // 模拟"库里已经有一个住民、但内容还是上一版的"情形
      await db
          .into(db.aiPersonas)
          .insert(
            AiPersonasCompanion.insert(
              id: 'persona_001',
              name: '上一版的名字',
            ),
          );

      await SeedService(db).seedIfNeeded();

      final rows = await db.select(db.aiPersonas).get();
      final fromAssets = await const PersonaRepository().loadAll();

      expect(rows.length, fromAssets.length, reason: '缺的应该补齐');
    });

    test('内容版本变了，老住民的内容会被刷新成新的', () async {
      // 上一版的住民：名字、圈子、bio 都是旧的
      await db
          .into(db.aiPersonas)
          .insert(
            AiPersonasCompanion.insert(
              id: 'persona_001',
              name: '上一版的名字',
              bio: const Value('上一版的签名'),
              circle: const Value('同校圈'),
            ),
          );

      await SeedService(db).seedIfNeeded();

      final row = (await db.select(db.aiPersonas).get())
          .firstWhere((item) => item.id == 'persona_001');
      final fromAssets = (await const PersonaRepository().loadAll())
          .firstWhere((item) => item.id == 'persona_001');

      expect(row.name, fromAssets.name, reason: '内容资产换代，老库要拿到新的');
      expect(row.circle, fromAssets.circle);
      expect(row.bio, fromAssets.bio);
    });

    test('刷新内容时，运行期的那本账一个字都不动', () async {
      // 有过来往、而且被删掉的住民
      await db
          .into(db.aiPersonas)
          .insert(
            AiPersonasCompanion.insert(
              id: 'persona_001',
              name: '上一版的名字',
            ),
          );
      await db
          .into(db.aiRelationships)
          .insertOnConflictUpdate(
            AiRelationshipsCompanion.insert(
              personaId: 'persona_001',
              relationshipLevel: const Value(2),
              intimacy: const Value(12),
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );

      await SeedService(db).seedIfNeeded();

      final relation = (await db.select(db.aiRelationships).get()).single;
      expect(relation.relationshipLevel, 2, reason: '你们的关系是历史，不是内容');
      expect(relation.intimacy, 12);
    });

    test('老帖子的旧圈子标签会换成新的，但帖子本身不动', () async {
      final postId = await PostRepository(db).create(
        content: '当时发的帖子',
        topicName: '同校圈',
      );

      await SeedService(db).seedIfNeeded();

      final post = await PostRepository(db).findById(postId);
      expect(post!.topicName, '日常', reason: '标签是分类，得跟着世界观换代');
      expect(post.content, '当时发的帖子', reason: '帖子本身是历史，一个字都不动');
    });

    test('重复播种不会把作息插两遍', () async {
      final seed = SeedService(db);
      await seed.seedIfNeeded();

      final before = await db.select(db.personaRoutines).get();
      await seed.seedIfNeeded();
      final after = await db.select(db.personaRoutines).get();

      expect(after.length, before.length);
      expect(
        after.map((row) => '${row.personaId}@${row.hour}').toSet().length,
        after.length,
        reason: '同一个人同一钟点只该有一条',
      );
    });

    test('住民带上圈层', () async {
      await SeedService(db).seedIfNeeded();

      final rows = await db.select(db.aiPersonas).get();
      final withoutCircle = rows.where((row) => row.circle.trim().isEmpty);
      expect(withoutCircle, isEmpty, reason: '每个住民都该有圈层，信息流要靠它分发');
    });
  });
}
