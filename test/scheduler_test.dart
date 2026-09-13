import 'dart:math';

import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/analysis_repository.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/notification_repository.dart';
import 'package:echo/data/repositories/persona_repository.dart';
import 'package:echo/data/repositories/plan_event_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/domain/models/echo_settings.dart';
import 'package:echo/domain/services/interaction_planner.dart';
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
      // 项目作者 2026-09-11 的判断：一个账号留两条语气不同的评论会立刻暴露 AI 身份。
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
  });
}
