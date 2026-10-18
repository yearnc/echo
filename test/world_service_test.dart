import 'dart:math';

// like 是 drift 的扩展方法，没法单独 show；isNotNull 与 matcher 重名，藏掉 drift 那份
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/media/media_service.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/model_config_repository.dart';
import 'package:echo/data/repositories/persona_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/services/content_generator.dart';
import 'package:echo/domain/services/relationship_rules.dart';
import 'package:echo/domain/services/model_gateway.dart';
import 'package:echo/domain/services/resident_photo.dart';
import 'package:echo/domain/services/resident_signature.dart';
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

/// 一个"真的读了帖子"的生成器：评论内容里带上帖子正文，
/// 用来验证住民动态底下的评论确实交给了模型，而不是随机台词。
class _ReadingGenerator extends SampleContentGenerator {
  _ReadingGenerator() : super(random: Random(2));

  int commentCalls = 0;

  @override
  Future<Map<String, String>> comments({
    required List<AiPersona> personas,
    required Post post,
    Map<String, RelationshipState> relations = const {},
  }) async {
    commentCalls++;
    return {
      for (final persona in personas) persona.id: '看过你这条：${post.content}',
    };
  }
}

class _MemoryKeyStore implements KeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// 住民图文帖：这些用例都不谈出图，配一个"没配文生图"的服务。
///
/// 它走的是真实代码路径（真去查有没有图片配置），只是每次都走到
/// "没配就只发文字"那一支——这比塞一个假对象更接近线上的样子。
ResidentPhotoService _noPhotoService(AppDatabase db) => ResidentPhotoService(
  db: db,
  posts: PostRepository(db),
  media: const MediaService(),
  gateway: ModelGateway(ModelConfigRepository(db, keyStore: _MemoryKeyStore())),
);

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
        residents: PersonaStateRepository(db, _FixedPersonas(pool)),
        photo: _noPhotoService(db),
        interactions: InteractionRepository(db),
        generator: SampleContentGenerator(random: Random(1)),
        sample: SampleContentGenerator(random: Random(1)),
        readAllowResidentPosts: () => true,
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
            .insert(
              AiPersonasCompanion.insert(id: persona.id, name: persona.name),
            );
      }

      world = WorldService(
        db: db,
        posts: PostRepository(db),
        personas: _FixedPersonas(pool),
        residents: PersonaStateRepository(db, _FixedPersonas(pool)),
        photo: _noPhotoService(db),
        interactions: InteractionRepository(db),
        generator: SampleContentGenerator(random: Random(2)),
        sample: SampleContentGenerator(random: Random(2)),
        readAllowResidentPosts: () => true,
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
            now.subtract(const Duration(hours: 8)).millisecondsSinceEpoch,
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

    test('住民动态的评论会交给模型重写，接住帖子内容', () async {
      final generator = _ReadingGenerator();
      final readingWorld = WorldService(
        db: db,
        posts: PostRepository(db),
        personas: _FixedPersonas(_pool(6)),
        residents: PersonaStateRepository(db, _FixedPersonas(_pool(6))),
        photo: _noPhotoService(db),
        interactions: InteractionRepository(db),
        generator: generator,
        sample: SampleContentGenerator(random: Random(2)),
        readAllowResidentPosts: () => true,
        random: Random(2),
      );

      await setLastTick(DateTime.now().subtract(const Duration(hours: 8)));
      await readingWorld.tick();
      // 评论是"先排期、后换内容"的，等后台那条异步写完
      await pumpEventQueue();

      expect(generator.commentCalls, greaterThan(0), reason: '评论该走模型');

      final comments = (await db.select(db.aiInteractions).get())
          .where((row) => row.type == 'comment')
          .toList();
      expect(comments, isNotEmpty, reason: '一条动态至少该有人来串门');
      for (final comment in comments) {
        expect(
          comment.content,
          startsWith('看过你这条：'),
          reason: '评论要接住帖子，不能还是住民的随身台词',
        );
      }
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

    Future<int> changedBios() async {
      final rows = await db.select(db.aiPersonas).get();
      return rows.where((row) => row.bio.isNotEmpty).length;
    }

    test('住民会顺手换个签名，一次 tick 只换一个', () async {
      var before = 0;
      var total = 0;

      // 多跑几轮：改签名有概率打折，一轮可能一个都不改
      for (var round = 0; round < 20; round++) {
        await setLastTick(DateTime.now().subtract(const Duration(hours: 8)));
        await world.tick();

        final after = await changedBios();
        expect(
          after - before,
          lessThanOrEqualTo(ResidentSignature.maxPerTick),
          reason: '一轮下来冒出好几个人同时换签名，就是程序在动了',
        );
        before = after;
        total = after;
      }

      expect(total, greaterThan(0), reason: '二十轮下来总该有人换过一次');

      final rows = await db.select(db.aiPersonas).get();
      for (final row in rows.where((r) => r.bio.isNotEmpty)) {
        expect(row.bio.length, lessThanOrEqualTo(ResidentSignature.maxLength));
      }
    });

    test('水位记在换过的那个人头上，签名才有冷却可言', () async {
      for (var round = 0; round < 20; round++) {
        await setLastTick(DateTime.now().subtract(const Duration(hours: 8)));
        await world.tick();
      }

      final changed = (await db.select(db.aiPersonas).get())
          .where((row) => row.bio.isNotEmpty)
          .toList();
      final marks = await (db.select(
        db.appSettings,
      )..where((t) => t.key.like('${WorldService.bioWatermarkPrefix}%'))).get();

      expect(
        marks.map((m) => m.key).toSet(),
        changed.map((r) => '${WorldService.bioWatermarkPrefix}${r.id}').toSet(),
      );
    });

    test('同一个住民短期内不会被换第二次', () async {
      // 池子里只留一个人：候选永远是他，冷却一旦生效就再没人可换
      final solo = _pool(1);
      final world = WorldService(
        db: db,
        posts: PostRepository(db),
        personas: _FixedPersonas(solo),
        residents: PersonaStateRepository(db, _FixedPersonas(solo)),
        photo: _noPhotoService(db),
        interactions: InteractionRepository(db),
        generator: SampleContentGenerator(random: Random(3)),
        sample: SampleContentGenerator(random: Random(3)),
        readAllowResidentPosts: () => true,
        random: Random(3),
      );
      final key = '${WorldService.bioWatermarkPrefix}${solo.single.id}';

      Future<String?> mark() async {
        final query = db.select(db.appSettings)
          ..where((t) => t.key.equals(key));
        return (await query.getSingleOrNull())?.value;
      }

      final seen = <String>{};
      for (var round = 0; round < 20; round++) {
        await setLastTick(DateTime.now().subtract(const Duration(hours: 8)));
        await world.tick();
        final value = await mark();
        if (value != null) seen.add(value);
      }

      expect(seen.length, 1, reason: '水位更新过一次之后就该待在冷却里');
    });

    test('换完签名会叫界面重读一次', () async {
      var notified = 0;
      final pool = _pool(6);
      final world = WorldService(
        db: db,
        posts: PostRepository(db),
        personas: _FixedPersonas(pool),
        residents: PersonaStateRepository(db, _FixedPersonas(pool)),
        photo: _noPhotoService(db),
        interactions: InteractionRepository(db),
        generator: SampleContentGenerator(random: Random(2)),
        sample: SampleContentGenerator(random: Random(2)),
        readAllowResidentPosts: () => true,
        random: Random(2),
        onResidentsChanged: () => notified++,
      );

      for (var round = 0; round < 20 && notified == 0; round++) {
        await setLastTick(DateTime.now().subtract(const Duration(hours: 8)));
        await world.tick();
      }

      expect(notified, 1, reason: '没人换签名就不必让界面白重读');
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
