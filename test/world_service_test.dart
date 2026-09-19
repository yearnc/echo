import 'dart:math';

import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/persona_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/domain/services/content_generator.dart';
import 'package:echo/domain/services/world_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固定的一批住民，不去读 assets——这一层要测的是"挑谁、什么时候发"，
/// 不是"assets 里有什么"。
class _FixedPersonas implements PersonaRepository {
  _FixedPersonas(this.pool);

  final List<AiPersona> pool;

  @override
  Future<List<AiPersona>> loadAll() async => pool;
}

List<AiPersona> _pool(int count) => List.generate(
  count,
  (i) => AiPersona(
    id: 'persona_${i.toString().padLeft(3, '0')}',
    name: '住民$i',
    circle: '同校圈',
    commentSamples: const ['台词'],
  ),
);

void main() {
  group('该补几条', () {
    test('按时间跨度算', () {
      expect(WorldService.countFor(const Duration(hours: 1)), 1);
      expect(WorldService.countFor(const Duration(hours: 6)), 2);
      expect(WorldService.countFor(const Duration(hours: 9)), 3);
      expect(WorldService.countFor(const Duration(hours: 12)), 4);
    });

    test('有上限：走了再久也不会一口气灌进来', () {
      expect(
        WorldService.countFor(const Duration(days: 7)),
        WorldService.maxPerTick,
      );
    });
  });

  group('挑人与排时间', () {
    late AppDatabase db;
    late WorldService world;
    late List<AiPersona> pool;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      pool = _pool(12);
      world = WorldService(
        db: db,
        posts: PostRepository(db),
        personas: _FixedPersonas(pool),
        interactions: InteractionRepository(db),
        generator: SampleContentGenerator(random: Random(1)),
        sample: SampleContentGenerator(random: Random(1)),
        random: Random(1),
      );
    });

    tearDown(() async => db.close());

    test('挑出来的人不重复', () {
      final moments = world.planMoments(
        pool: pool,
        count: 5,
        from: DateTime(2026, 9, 19, 8),
        to: DateTime(2026, 9, 19, 20),
      );

      expect(moments.length, 5);
      expect(moments.map((m) => m.persona.id).toSet().length, 5);
    });

    test('时间落在给定区间内，且按先后排好', () {
      final from = DateTime(2026, 9, 19, 8);
      final to = DateTime(2026, 9, 19, 20);

      final moments = world.planMoments(
        pool: pool,
        count: 4,
        from: from,
        to: to,
      );

      for (final moment in moments) {
        expect(moment.at.isBefore(from), isFalse);
        expect(moment.at.isAfter(to), isFalse);
      }
      for (var i = 1; i < moments.length; i++) {
        expect(
          moments[i].at.isBefore(moments[i - 1].at),
          isFalse,
          reason: '落库顺序要与信息流顺序一致',
        );
      }
    });

    test('人多的时候也不会超池子', () {
      final moments = world.planMoments(
        pool: _pool(3),
        count: 10,
        from: DateTime(2026, 9, 19, 8),
        to: DateTime(2026, 9, 19, 20),
      );
      expect(moments.length, 3);
    });

    test('时间跨度为零时什么也不排', () {
      final at = DateTime(2026, 9, 19, 8);
      expect(
        world.planMoments(pool: pool, count: 3, from: at, to: at),
        isEmpty,
      );
    });
  });

  group('世界 tick', () {
    late AppDatabase db;
    late WorldService world;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      final pool = _pool(6);

      // 住民先入库：posts.author_persona_id 有外键指着 ai_personas
      for (final persona in pool) {
        await db
            .into(db.aiPersonas)
            .insert(AiPersonasCompanion.insert(id: persona.id, name: persona.name));
      }

      world = WorldService(
        db: db,
        posts: PostRepository(db),
        personas: _FixedPersonas(pool),
        interactions: InteractionRepository(db),
        generator: SampleContentGenerator(random: Random(2)),
        sample: SampleContentGenerator(random: Random(2)),
        random: Random(2),
      );
    });

    tearDown(() async => db.close());

    Future<void> setLastTick(DateTime at) async {
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: WorldService.lastTickKey,
              value: '${at.millisecondsSinceEpoch}',
            ),
          );
    }

    Future<String?> lastTickValue() async {
      final query = db.select(db.appSettings)
        ..where((t) => t.key.equals(WorldService.lastTickKey));
      return (await query.getSingleOrNull())?.value;
    }

    test('第一次只记时间，不生成', () async {
      expect(await world.tick(), 0);
      expect(await db.select(db.posts).get(), isEmpty);
      expect(await lastTickValue(), isNotNull, reason: '下次好从这里算起');
    });

    test('隔得不够久就不生成', () async {
      await setLastTick(DateTime.now().subtract(const Duration(minutes: 30)));

      expect(await world.tick(), 0);
      expect(await db.select(db.posts).get(), isEmpty);
    });

    test('隔够久了就补上，时间落在过去', () async {
      final now = DateTime.now();
      await setLastTick(now.subtract(const Duration(hours: 8)));

      final written = await world.tick();

      expect(written, greaterThan(0));

      final rows = await db.select(db.posts).get();
      expect(rows.length, written);
      for (final row in rows) {
        expect(row.authorPersonaId, isNotNull, reason: '这是住民发的，不是用户发的');
        expect(row.content, isNotEmpty, reason: '不能有空白动态');
        expect(row.scope, 'echo');
        expect(
          row.createdAt,
          lessThan(now.millisecondsSinceEpoch),
          reason: '动态该落在过去那几个小时里，不是"刚刚"',
        );
        expect(
          row.createdAt,
          greaterThanOrEqualTo(
            now
                .subtract(const Duration(hours: 8))
                .millisecondsSinceEpoch,
          ),
        );
      }
    });

    test('生成完把水位推到当下，不会连着再生成一次', () async {
      await setLastTick(DateTime.now().subtract(const Duration(hours: 8)));

      await world.tick();
      final afterFirst = (await db.select(db.posts).get()).length;

      expect(await world.tick(), 0);
      expect((await db.select(db.posts).get()).length, afterFirst);
    });

    test('清醒模式里不长出新动态', () async {
      await setLastTick(DateTime.now().subtract(const Duration(hours: 8)));
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: 'app.mode', value: 'clear'),
          );

      expect(await world.tick(), 0);
      expect(await db.select(db.posts).get(), isEmpty);
    });

    test('住民动态会进信息流（和用户的帖子同一张表）', () async {
      await setLastTick(DateTime.now().subtract(const Duration(hours: 6)));
      await world.tick();

      final feed = await PostRepository(db).watchFeed(scope: 'echo').first;
      expect(feed, isNotEmpty);
      expect(feed.first.isByResident, isTrue);
    });

    test('住民动态下面会有人来串门，而且不是帖主自己', () async {
      // 多跑几轮：每条动态来几个人是随机的（0—2），一轮可能一个都没来
      for (var round = 0; round < 5; round++) {
        await setLastTick(DateTime.now().subtract(const Duration(hours: 8)));
        await world.tick();
      }

      final replies = await db.select(db.aiInteractions).get();
      expect(replies, isNotEmpty, reason: '五轮下来总该有人路过一次');

      for (final reply in replies) {
        final query = db.select(db.posts)
          ..where((t) => t.id.equals(reply.postId));
        final post = await query.getSingle();

        expect(post.authorPersonaId, isNotNull, reason: '回应是给住民动态排的');
        expect(
          reply.personaId,
          isNot(post.authorPersonaId),
          reason: '自己不该回自己的帖',
        );
        expect(reply.content, isNotEmpty, reason: '不能有空白评论');
      }
    });

    test('residentAuthorsOf 只认住民发的帖子', () async {
      final posts = PostRepository(db);
      final mine = await posts.create(content: '我自己发的', scope: 'echo');
      final theirs = await posts.createResidentPost(
        personaId: 'persona_001',
        content: '住民发的',
      );

      final authors = await posts.residentAuthorsOf({mine, theirs});

      expect(authors.keys, [theirs]);
      expect(authors[theirs], 'persona_001');
    });
  });
}
