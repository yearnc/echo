import 'dart:math';

import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/media/media_service.dart';
import 'package:echo/data/repositories/custom_resident_repository.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/model_config_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/post_voice_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/domain/models/custom_resident.dart';
import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/models/post_understanding.dart';
import 'package:echo/domain/services/content_generator.dart';
import 'package:echo/domain/services/model_gateway.dart';
import 'package:echo/domain/services/relationship_rules.dart';
import 'package:echo/domain/services/resident_photo.dart';
import 'package:echo/domain/services/world_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
    PostUnderstanding? understanding,
    bool sendImagesDirectly = false,
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
ResidentPhotoService _noPhotoService(AppDatabase db) => ResidentPhotoService(
  db: db,
  posts: PostRepository(db),
  media: const MediaService(),
  gateway: ModelGateway(ModelConfigRepository(db, keyStore: _MemoryKeyStore())),
);

/// 排期仍按 AiPersona 的形状挑人，这里造一批给纯逻辑用例用。
List<AiPersona> _pool(int count) => List.generate(
  count,
  (i) => AiPersona(
    id: 'resident_${i.toString().padLeft(3, '0')}',
    name: '住民$i',
    commentSamples: const ['台词'],
  ),
);

/// 把固定住民写进库——世界 tick 现在只认这一张表。
Future<void> _seedResidents(AppDatabase db, int count) async {
  final repo = CustomResidentRepository(db);
  for (final persona in _pool(count)) {
    await repo.upsert(
      CustomResident(
        id: persona.id,
        name: persona.name,
        description: '住在附近的人',
        createdAt: DateTime(2026, 9, 1),
      ),
    );
  }
}

WorldService _world(
  AppDatabase db, {
  required ContentGenerator generator,
  SampleContentGenerator? sample,
}) => WorldService(
  db: db,
  posts: PostRepository(db),
  people: CustomResidentRepository(db),
  voices: PostVoiceRepository(db),
  photo: _noPhotoService(db),
  interactions: InteractionRepository(db),
  generator: generator,
  sample: sample ?? SampleContentGenerator(random: Random(2)),
  readAllowResidentPosts: () => true,
  random: Random(2),
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
      world = _world(db, generator: SampleContentGenerator(random: Random(1)));
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
      await _seedResidents(db, 6);
      world = _world(db, generator: SampleContentGenerator(random: Random(2)));
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

    test('没有固定住民就什么都不发生', () async {
      final emptyDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(emptyDb.close);
      final emptyWorld = _world(
        emptyDb,
        generator: SampleContentGenerator(random: Random(1)),
      );
      await emptyDb
          .into(emptyDb.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: WorldService.lastTickKey,
              value: '${DateTime.now().subtract(const Duration(hours: 8)).millisecondsSinceEpoch}',
            ),
          );

      expect(await emptyWorld.tick(), 0);
      expect(await emptyDb.select(emptyDb.posts).get(), isEmpty);
    });

    test('隔够久了就补上，时间落在过去，作者是固定住民', () async {
      final now = DateTime.now();
      await setLastTick(now.subtract(const Duration(hours: 8)));

      final written = await world.tick();

      expect(written, greaterThan(0));

      final rows = await db.select(db.posts).get();
      expect(rows.length, written);
      for (final row in rows) {
        expect(row.authorResidentId, isNotNull, reason: '这是固定住民发的');
        expect(row.authorPersonaId, isNull, reason: '旧住民不再长内容');
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
      expect(feed.first.authorResidentId, isNotNull);
    });

    test('住民动态的评论会交给模型重写，接住帖子内容', () async {
      final generator = _ReadingGenerator();
      final readingWorld = _world(db, generator: generator);

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
      for (var round = 0; round < 5; round++) {
        await setLastTick(DateTime.now().subtract(const Duration(hours: 8)));
        await world.tick();
      }

      final replies = await db.select(db.aiInteractions).get();
      expect(replies, isNotEmpty, reason: '五轮下来总该有人路过一次');

      final voices = await db.select(db.postVoices).get();
      final byVoiceId = {for (final voice in voices) voice.id: voice};

      for (final reply in replies) {
        final query = db.select(db.posts)
          ..where((t) => t.id.equals(reply.postId));
        final post = await query.getSingle();

        expect(post.authorResidentId, isNotNull, reason: '回应是给住民动态排的');
        final commenter = byVoiceId[reply.personaId];
        expect(commenter, isNotNull, reason: '评论者必须是这一帖的固定住民快照');
        expect(
          commenter!.residentId,
          isNot(post.authorResidentId),
          reason: '自己不该回自己的帖',
        );
        expect(reply.content, isNotEmpty, reason: '不能有空白评论');
      }
    });

    test('residentAuthorsOf 认固定住民发的帖子', () async {
      final posts = PostRepository(db);
      final mine = await posts.create(content: '我自己发的', scope: 'echo');
      final theirs = await posts.createResidentPost(
        residentId: 'resident_001',
        content: '固定住民发的',
      );

      final authors = await posts.residentAuthorsOf({mine, theirs});

      expect(authors.keys, [theirs]);
      expect(authors[theirs], 'resident_001');
    });

    test('固定住民的动态不算进「我的」统计', () async {
      final posts = PostRepository(db);
      await posts.create(content: '我自己发的', scope: 'echo');
      await posts.createResidentPost(
        residentId: 'resident_001',
        content: '固定住民发的',
      );

      final stats = await posts.watchStats().first;
      expect(stats.postCount, 1);
    });
  });
}
