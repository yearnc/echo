import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/analysis_repository.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/notification_repository.dart';
import 'package:echo/data/repositories/persona_repository.dart';
import 'package:echo/data/repositories/plan_event_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/relationship_repository.dart';
import 'package:echo/domain/services/content_generator.dart';
import 'package:echo/domain/services/interaction_planner.dart';
import 'package:echo/domain/services/scheduler_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 收下"推到通知栏"的那些条。
class _Pushed {
  final List<(String, String, String)> items = [];

  void call(String key, String title, String body) =>
      items.add((key, title, body));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('系统通知（B10）', () {
    late AppDatabase db;
    late PostRepository posts;
    late InteractionRepository interactions;
    late NotificationRepository notifications;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      posts = PostRepository(db);
      interactions = InteractionRepository(db);
      notifications = NotificationRepository(db);

      final real = await const PersonaRepository().loadAll();
      await db.batch((batch) {
        batch.insertAll(
          db.aiPersonas,
          real
              .map((p) => AiPersonasCompanion.insert(id: p.id, name: p.name))
              .toList(growable: false),
        );
      });
    });

    tearDown(() => db.close());

    /// 排一条到点的互动，然后扫一次队列。
    ///
    /// [notified] 传了就是"后台补发"那条路（要推通知栏），
    /// 不传就是前台（只写应用内通知）。
    Future<void> flush({
      required String type,
      _Pushed? notified,
      int likeBatch = 1,
    }) async {
      final postId = await posts.create(content: '楼下桂花开了', scope: 'echo');
      await interactions.insertPlanned(postId, [
        PlannedInteraction(
          personaId: 'persona_001',
          type: type,
          scheduledAt: DateTime.now().subtract(const Duration(minutes: 1)),
          content: type == 'comment' ? '桂花一开，整条街都是甜的。' : null,
          likeBatch: likeBatch,
        ),
      ]);

      final scheduler = SchedulerService(
        interactions: interactions,
        planEvents: PlanEventRepository(db),
        posts: posts,
        notifications: notifications,
        personas: const PersonaRepository(),
        analyses: AnalysisRepository(db),
        generator: SampleContentGenerator(),
        relationships: RelationshipRepository(db),
        notify: notified?.call,
        planner: InteractionPlanner(random: Random(3)),
      );
      await scheduler.flushDue();
    }

    test('后台补发时，补上的评论会推到通知栏', () async {
      final pushed = _Pushed();
      await flush(type: 'comment', notified: pushed);

      expect(pushed.items, hasLength(1));
      final (key, title, body) = pushed.items.single;
      expect(key, startsWith('n_sched_'), reason: '通知 id 由互动派生，重复补发不会刷屏');
      expect(title, contains('评论了你的帖子'));
      expect(body, '桂花一开，整条街都是甜的。');
    });

    test('补上的点赞也会推，人数写进标题', () async {
      final pushed = _Pushed();
      await flush(type: 'like', notified: pushed, likeBatch: 12);

      expect(pushed.items, hasLength(1));
      expect(pushed.items.single.$2, contains('12 人赞了你的帖子'));
    });

    test('前台那条路上不弹系统通知，应用内通知照写', () async {
      // 不传 notify 就是前台：用户正看着屏幕，红点已经够了。
      await flush(type: 'comment', notified: null);

      final rows = await db.select(db.notificationLogs).get();
      expect(rows, hasLength(1), reason: '应用内那条不能少');
      expect(rows.single.title, contains('评论了你的帖子'));
    });

    test('住民之间互相评论不打扰用户', () async {
      final pushed = _Pushed();
      // 帖子是住民发的（authorPersonaId 非空）→ 那不是"回应你"
      const postId = 'p_resident';
      await db
          .into(db.posts)
          .insert(
            PostsCompanion.insert(
              id: postId,
              content: const Value('今天值夜班'),
              createdAt: DateTime.now().millisecondsSinceEpoch,
              authorPersonaId: const Value('persona_001'),
            ),
          );
      await interactions.insertPlanned(postId, [
        PlannedInteraction(
          personaId: 'persona_002',
          type: 'comment',
          scheduledAt: DateTime.now().subtract(const Duration(minutes: 1)),
          content: '辛苦啦',
        ),
      ]);

      final scheduler = SchedulerService(
        interactions: interactions,
        planEvents: PlanEventRepository(db),
        posts: posts,
        notifications: notifications,
        personas: const PersonaRepository(),
        analyses: AnalysisRepository(db),
        generator: SampleContentGenerator(),
        relationships: RelationshipRepository(db),
        notify: pushed.call,
        planner: InteractionPlanner(random: Random(3)),
      );
      await scheduler.flushDue();

      expect(pushed.items, isEmpty);
      expect(await db.select(db.notificationLogs).get(), isEmpty);
    });
  });
}
