import 'dart:math';

import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/analysis_repository.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/model_config_repository.dart';
import 'package:echo/data/repositories/notification_repository.dart';
import 'package:echo/data/repositories/persona_repository.dart';
import 'package:echo/data/repositories/plan_event_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/relationship_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/domain/models/echo_settings.dart';
import 'package:echo/domain/services/content_generator.dart';
import 'package:echo/domain/services/interaction_planner.dart';
import 'package:echo/domain/services/memory_summarizer.dart';
import 'package:echo/domain/services/model_gateway.dart';
import 'package:echo/domain/services/relationship_rules.dart';
import 'package:echo/domain/services/scheduler_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一批测试住民：倾向都调高，方便验证"该发生的都发生了"。
List<AiPersona> buildPersonas({int count = 12}) => List.generate(
  count,
  (i) => AiPersona(
    id: 'persona_$i',
    name: '住民$i',
    likeProbability: 0.85,
    commentProbability: 0.7,
    activeHours: const [0, 8, 12, 20, 23],
    personalityType: i == 0 ? '沉默点赞型' : '温和鼓励型',
    commentSamples: const ['示例评论一号', '示例评论二号'],
  ),
);

/// 记忆服务要一个 KeyStore 才构造得出来；这些用例里它一次都不会被用到。
class _NoKeys implements KeyStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

/// 一块坏掉的记忆：它必须坏得无声无息（B4 的后台路径就是这么要求它的）。
class _BoomMemory extends MemorySummarizer {
  _BoomMemory(AppDatabase db)
    : super(
        db: db,
        posts: PostRepository(db),
        relationships: RelationshipRepository(db),
        gateway: ModelGateway(ModelConfigRepository(db, keyStore: _NoKeys())),
      );

  int calls = 0;

  @override
  Future<int> refresh({required List<AiPersona> personas}) async {
    calls += 1;
    throw StateError('记忆这块坏了');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InteractionPlanner', () {
    final now = DateTime(2026, 9, 11, 20);

    test('排期全部落在 0—48 小时窗口内', () {
      final planned = InteractionPlanner(random: Random(7)).plan(
        now: now,
        personas: buildPersonas(),
        settings: EchoSettings.defaults,
      );

      expect(planned, isNotEmpty);
      for (final item in planned) {
        expect(item.scheduledAt.isBefore(now), isFalse, reason: '不能排到过去');
        expect(
          item.scheduledAt.isAfter(now.add(InteractionPlanner.defaultWindow)),
          isFalse,
          reason: '不能超出 48 小时窗口',
        );
      }
    });

    test('最早发生的一定是点赞（不能让人干等几小时）', () {
      final planned = InteractionPlanner(random: Random(3)).plan(
        now: now,
        personas: buildPersonas(),
        settings: EchoSettings.defaults,
      );

      expect(planned.first.isLike, isTrue);
      expect(planned.first.scheduledAt.difference(now).inMinutes, lessThan(60));
    });

    test('点赞总量严格落在档位区间内', () {
      for (final level in LikeLevel.values) {
        final planned = InteractionPlanner(random: Random(5)).plan(
          now: now,
          personas: buildPersonas(),
          settings: EchoSettings(density: ReplyDensity.high, likeLevel: level),
        );

        final total = planned
            .where((item) => item.isLike)
            .fold<int>(0, (sum, item) => sum + item.likeBatch);
        final (min, max) = level.totalRange;

        expect(
          total,
          greaterThanOrEqualTo(min),
          reason: '${level.label} 档点赞不足',
        );
        expect(total, lessThanOrEqualTo(max), reason: '${level.label} 档点赞超出');
      }
    });

    test('匿名人群批次统一挂在一个住民头像下（不做假人）', () {
      final planned = InteractionPlanner(random: Random(4)).plan(
        now: now,
        personas: buildPersonas(),
        settings: const EchoSettings(likeLevel: LikeLevel.high),
      );

      final crowd = planned.where((item) => item.isLike && item.likeBatch > 1);

      expect(crowd, isNotEmpty, reason: '高点赞档必须有人群批次');
      expect(
        crowd.map((item) => item.personaId).toSet(),
        hasLength(1),
        reason: '所有人群批次共用一个已存在的住民头像，避免凭空造人',
      );
    });

    test('频率档位越高，说话的人越多', () {
      final low = InteractionPlanner(random: Random(13)).plan(
        now: now,
        personas: buildPersonas(),
        settings: const EchoSettings(density: ReplyDensity.low),
      );
      final high = InteractionPlanner(random: Random(13)).plan(
        now: now,
        personas: buildPersonas(),
        settings: const EchoSettings(density: ReplyDensity.high),
      );

      final lowSpeakers = low.where((i) => i.isComment).length;
      final highSpeakers = high.where((i) => i.isComment).length;
      expect(highSpeakers, greaterThan(lowSpeakers));
    });

    test('同一人格不会对同一条帖子评论两次（人设一致性）', () {
      // 2026-09-11 定下的规则：一个账号留两条语气不同的评论会立刻暴露 AI 身份。
      // 真正的"追问"要等阶段 B 的楼中楼（需要对话上下文），不是并列两条顶层评论。
      for (final density in ReplyDensity.values) {
        final planned = InteractionPlanner(random: Random(2)).plan(
          now: now,
          personas: buildPersonas(),
          settings: EchoSettings(
            density: density,
            humanLevel: const HumanLevel(5),
          ),
        );

        final perPersona = <String, int>{};
        for (final item in planned.where((i) => i.isComment)) {
          perPersona[item.personaId] = (perPersona[item.personaId] ?? 0) + 1;
        }

        expect(
          perPersona.values.every((count) => count == 1),
          isTrue,
          reason: '${density.label} 档出现了同一个人格的重复评论：$perPersona',
        );
      }
    });

    test('人格为空时返回空排期，不崩', () {
      final planned = InteractionPlanner(random: Random(1))
          .plan(now: now, personas: const [], settings: EchoSettings.defaults);

      expect(planned, isEmpty);
    });

    test('关系越近，越可能真的开口', () {
      final persona = buildPersonas(count: 1).first;

      expect(
        InteractionPlanner.commentChance(persona, 0),
        persona.commentProbability,
        reason: '陌生人不该有任何加成',
      );
      expect(
        InteractionPlanner.commentChance(persona, 4),
        greaterThan(persona.commentProbability),
      );
      expect(
        InteractionPlanner.commentChance(persona, 99),
        0.95,
        reason: '再熟也有不想说话的时候',
      );
    });

    test('熟人更容易出现在你的帖子里，但不会被钉在每一条上', () {
      final personas = buildPersonas(count: 12);
      final at = DateTime(2026, 10, 12, 20);

      int attendances({required bool withRelation}) {
        final planner = InteractionPlanner(random: Random(7));
        final relations = withRelation
            ? const {
                'persona_0': RelationshipState(
                  personaId: 'persona_0',
                  level: 4,
                ),
              }
            : const <String, RelationshipState>{};

        var times = 0;
        for (var i = 0; i < 200; i++) {
          final planned = planner.plan(
            now: at,
            personas: personas,
            settings: EchoSettings.defaults,
            relations: relations,
          );
          if (planned.any((item) => item.personaId == 'persona_0')) times++;
        }
        return times;
      }

      final withRelation = attendances(withRelation: true);
      final without = attendances(withRelation: false);

      expect(withRelation, greaterThan(without));
      expect(withRelation, lessThan(200), reason: '好友也不是每条必到');
    });
  });

  group('SchedulerService（冷启动补发）', () {
    late AppDatabase db;
    late PostRepository posts;
    late InteractionRepository interactions;
    late NotificationRepository notifications;
    late SchedulerService scheduler;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      posts = PostRepository(db);
      interactions = InteractionRepository(db);
      notifications = NotificationRepository(db);
      scheduler = SchedulerService(
        interactions: interactions,
        planEvents: PlanEventRepository(db),
        posts: posts,
        notifications: notifications,
        personas: const PersonaRepository(),
        analyses: AnalysisRepository(db),
        generator: SampleContentGenerator(),
        relationships: RelationshipRepository(db),
        planner: InteractionPlanner(random: Random(9)),
      );

      // 住民必须先入库：ai_interactions.persona_id 有外键指向 ai_personas，
      // 而排期用的是 assets 里那批真实住民（persona_001~012）。
      // 这里复刻 SeedService 的播种动作，保证两端 id 一致。
      final realPersonas = await const PersonaRepository().loadAll();
      await db.batch((batch) {
        batch.insertAll(
          db.aiPersonas,
          realPersonas
              .map((p) => AiPersonasCompanion.insert(id: p.id, name: p.name))
              .toList(growable: false),
        );
      });

      final seeded = (await db.select(db.aiPersonas).get()).length;
      expect(seeded, realPersonas.length, reason: '住民播种失败');
    });

    tearDown(() async => db.close());

    /// v3.0 起排期不再预填台词，评论内容由模型在发帖后写入。
    /// 测试里直接补上内容，模拟"模型写完了"。
    Future<void> fillPendingComments(String postId) async {
      final ids = await interactions.pendingCommentPersonaIds(postId);
      await interactions.updatePendingComments(postId, {
        for (final id in ids) id: '这条评论接住了帖子里的内容',
      });
    }

    /// 模拟"关掉 APP 两天"：把所有待办的时间挪到过去。
    Future<void> rewindPending() async {
      await db.customStatement(
        "UPDATE ai_interactions SET scheduled_at = ? WHERE status = 'pending'",
        [
          DateTime.now()
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        ],
      );
    }

    test('发帖后队列里出现待兑现的排期，且此刻不该兑现', () async {
      final postId = await posts.create(content: '刚发的帖子', scope: 'echo');

      final count = await scheduler.planForPost(
        postId: postId,
        settings: EchoSettings.defaults,
      );

      expect(count, greaterThan(0));
      expect(await scheduler.pendingCount(), count);
      expect(await scheduler.flushDue(), 0, reason: '刚发完还没到点');
    });

    test('时间到了以后补发：计数增加、通知产生', () async {
      final postId = await posts.create(content: '两天前发的帖子', scope: 'echo');
      await scheduler.planForPost(
        postId: postId,
        settings: const EchoSettings(
          density: ReplyDensity.high,
          likeLevel: LikeLevel.high,
        ),
      );
      await fillPendingComments(postId);
      await rewindPending();

      final flushed = await scheduler.flushDue();

      expect(flushed, greaterThan(0));
      expect(await scheduler.pendingCount(), 0, reason: '兑现后不该再有待办');

      final post = await posts.findById(postId);
      expect(post!.likeCount, greaterThan(0), reason: '点赞应被累加');
      expect(post.commentCount, greaterThan(0), reason: '评论数应被累加');

      final list = await notifications.watchRecent().first;
      expect(list, isNotEmpty, reason: '每兑现一条互动都该留下通知');
    });

    test('补发的通知记在本该发生的时间上，不是补发那一刻', () async {
      final postId = await posts.create(content: '两天前发的帖子', scope: 'echo');
      await scheduler.planForPost(
        postId: postId,
        settings: EchoSettings.defaults,
      );
      await rewindPending();

      await scheduler.flushDue();

      final rows = await db.select(db.notificationLogs).get();
      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(row.deliveredAt, row.scheduledAt, reason: '离线积压的互动不该全挤在"刚刚"');
      }
    });

    test('排期时把将来的评论交给系统闹钟，兑现时撤掉预约', () async {
      final scheduled = <String, DateTime>{};
      final cancelled = <String>[];
      final withAlarms = SchedulerService(
        interactions: interactions,
        planEvents: PlanEventRepository(db),
        posts: posts,
        notifications: notifications,
        personas: const PersonaRepository(),
        analyses: AnalysisRepository(db),
        generator: SampleContentGenerator(),
        relationships: RelationshipRepository(db),
        planner: InteractionPlanner(random: Random(9)),
        scheduleNotification: (key, at, title, body) => scheduled[key] = at,
        cancelScheduledNotification: cancelled.add,
      );

      final postId = await posts.create(content: '帖子', scope: 'echo');
      await withAlarms.planForPost(
        postId: postId,
        settings: EchoSettings.defaults,
      );
      // 内容写出来之后才预约：空评论不值得叫醒手机。
      await fillPendingComments(postId);
      await withAlarms.rescheduleNotifications();

      expect(scheduled, isNotEmpty, reason: '评论要在 APP 关着时也能提醒');

      await rewindPending();
      await withAlarms.flushDue();

      expect(
        cancelled,
        containsAll(scheduled.keys),
        reason: '已经兑现的预约不撤掉，过一会儿会重复弹',
      );
    });

    test('重复补发不会重复计数（幂等）', () async {
      final postId = await posts.create(content: '帖子', scope: 'echo');
      await scheduler.planForPost(
        postId: postId,
        settings: EchoSettings.defaults,
      );
      await rewindPending();

      await scheduler.flushDue();
      final afterFirst = await posts.findById(postId);
      await scheduler.flushDue();
      final afterSecond = await posts.findById(postId);

      expect(afterSecond!.likeCount, afterFirst!.likeCount);
      expect(afterSecond.commentCount, afterFirst.commentCount);
    });

    test('未读通知数随补发增长，标记已读后归零', () async {
      final postId = await posts.create(content: '帖子', scope: 'echo');
      await scheduler.planForPost(
        postId: postId,
        settings: EchoSettings.defaults,
      );
      await rewindPending();
      await scheduler.flushDue();

      expect(await notifications.watchUnreadCount().first, greaterThan(0));

      await notifications.markAllRead();

      expect(await notifications.watchUnreadCount().first, 0);
    });

    test('点赞过百自动标热（热榜是外部评价的产物）', () async {
      final postId = await posts.create(content: '爆款帖子', scope: 'echo');

      await posts.addCounters(postId, likes: 120);

      final post = await posts.findById(postId);
      expect(post!.likeCount, 120);
      expect(post.isHot, isTrue);
    });

    test('住民动态底下的互动兑现时不通知用户', () async {
      // 这条帖子不是你的——是社区里另一个人的动态。
      // 底下有人来评论，那是社区自己的热闹，没有理由弹到你手机上。
      final postId = await posts.createResidentPost(
        personaId: 'persona_001',
        content: '在图书馆，今天的位子很好。',
      );

      await interactions.insertPlanned(postId, [
        PlannedInteraction(
          personaId: 'persona_002',
          type: 'comment',
          content: '我去的时候就没位子了',
          scheduledAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ]);

      await scheduler.flushDue();

      expect(await db.select(db.notificationLogs).get(), isEmpty);
      // 但计数照加：评论区要看得见有人来过
      final post = await posts.findById(postId);
      expect(post!.commentCount, 1);
    });

    test('兑现之后，住民和你的关系往前挪了一步', () async {
      final postId = await posts.create(content: '我的帖子', scope: 'echo');
      await scheduler.planForPost(
        postId: postId,
        settings: const EchoSettings(
          density: ReplyDensity.high,
          likeLevel: LikeLevel.high,
        ),
      );
      await rewindPending();
      await scheduler.flushDue();

      final relations = await RelationshipRepository(db).loadAll();

      expect(relations, isNotEmpty, reason: '有人来过，关系就该有记录');
      expect(
        relations.values.every((relation) => relation.interactionCount > 0),
        isTrue,
      );
      expect(
        relations.values.any((relation) => relation.intimacy > 0),
        isTrue,
        reason: '第一次互动总该长一点亲近度',
      );
    });

    test('住民彼此之间的互动，不该让你和谁变熟', () async {
      // 跟上面几条一样：这是别人和别人的事，跟你没关系。
      final postId = await posts.createResidentPost(
        personaId: 'persona_001',
        content: '食堂今天有糖醋排骨。',
      );
      await interactions.insertPlanned(postId, [
        PlannedInteraction(
          personaId: 'persona_002',
          type: 'comment',
          content: '我也去了，没抢到',
          scheduledAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ]);

      await scheduler.flushDue();

      expect(await RelationshipRepository(db).loadAll(), isEmpty);
    });

    test('住民动态底下的评论，作者可能回一句（住民之间的楼中楼）', () async {
      final postId = await posts.createResidentPost(
        personaId: 'persona_001',
        content: '今天在河边坐了一会儿。',
      );

      // 一大批邻居来评论：作者不会条条都回，但总得回几句
      await interactions.insertPlanned(postId, [
        for (var i = 2; i <= 21; i++)
          PlannedInteraction(
            personaId: 'persona_${i.toString().padLeft(3, '0')}',
            type: 'comment',
            content: '我上周也去了',
            scheduledAt: DateTime.now().subtract(const Duration(minutes: 1)),
          ),
      ]);

      await scheduler.flushDue();
      await pumpEventQueue();

      final followUps = (await db.select(db.aiInteractions).get())
          .where((row) => row.parentId != null)
          .toList();

      expect(followUps, isNotEmpty, reason: '总该有人接一句');
      expect(followUps.length, lessThan(20), reason: '但不是条条都回——那像客服');
      expect(
        followUps.every((row) => row.personaId == 'persona_001'),
        isTrue,
        reason: '接话的是动态的作者本人',
      );
    });

    test('记忆那块坏掉了，兑现和通知照样走完', () async {
      // 这条路径跑在 unawaited 里：它抛出去就是没人接的异常，
      // 而这个测试会因为"未捕获的异步错误"直接失败——这就是它守的东西。
      final boom = _BoomMemory(db);
      final withMemory = SchedulerService(
        interactions: interactions,
        planEvents: PlanEventRepository(db),
        posts: posts,
        notifications: notifications,
        personas: const PersonaRepository(),
        analyses: AnalysisRepository(db),
        generator: SampleContentGenerator(),
        relationships: RelationshipRepository(db),
        memory: boom,
        planner: InteractionPlanner(random: Random(9)),
      );

      final postId = await posts.create(content: '帖子', scope: 'echo');
      await withMemory.planForPost(
        postId: postId,
        settings: const EchoSettings(
          density: ReplyDensity.high,
          likeLevel: LikeLevel.high,
        ),
      );
      await rewindPending();

      final flushed = await withMemory.flushDue();
      await pumpEventQueue();

      expect(flushed, greaterThan(0), reason: '兑现照常');
      expect(boom.calls, greaterThan(0), reason: '记忆确实被叫过，只是它坏了');
      expect((await posts.findById(postId))!.likeCount, greaterThan(0));
      expect(await notifications.watchRecent().first, isNotEmpty);
    });
  });
}
