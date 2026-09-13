import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/plan_event_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/domain/models/app_mode.dart';
import 'package:echo/domain/services/interaction_planner.dart';
import 'package:echo/domain/services/mode_switch_service.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seedPersona(AppDatabase db, String id) async {
  await db
      .into(db.aiPersonas)
      .insert(AiPersonasCompanion.insert(id: id, name: '住民'));
}

void main() {
  late AppDatabase db;
  late ModeSwitchService service;
  late AppMode current;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    current = AppMode.echo;
    service = ModeSwitchService(
      db: db,
      readMode: () => current,
      persistMode: (target) async => current = target,
      interactions: InteractionRepository(db),
      planEvents: PlanEventRepository(db),
    );
    await _seedPersona(db, 'persona_0');
  });

  tearDown(() async => db.close());

  group('回响 → 清醒（规划书 §2.4.1）', () {
    test('停掉待发队列，把已有的虚拟反馈归档，并留一条日志', () async {
      final posts = PostRepository(db);
      final interactions = InteractionRepository(db);
      final postId = await posts.create(content: '一条帖子', scope: 'echo');

      // 一条已经兑现的评论
      await interactions.insertExecutedComment(
        id: 'c1',
        postId: postId,
        personaId: 'persona_0',
        content: '好看',
      );
      // 一条还没到点的排期
      await interactions.insertPlanned(postId, [
        PlannedInteraction(
          personaId: 'persona_0',
          type: 'like',
          scheduledAt: DateTime.now().add(const Duration(hours: 3)),
        ),
      ]);

      await service.switchTo(AppMode.clear);

      expect(current, AppMode.clear);
      expect(await interactions.countPending(), 0, reason: '待发队列必须停下来');

      final rows = await db.select(db.aiInteractions).get();
      final executed = rows.where((row) => row.status == 'done').toList();
      final cancelled = rows.where((row) => row.status == 'cancelled').toList();

      expect(executed.single.scope, 'archived', reason: '已兑现的互动要归档');
      expect(cancelled, hasLength(1), reason: '没到点的排期要被取消');

      final logs = await db.select(db.modeSwitchLogs).get();
      expect(logs.single.fromMode, 'echo');
      expect(logs.single.toMode, 'clear');
      expect(logs.single.archiveAction, 'archived');
    });

    test('切过去之后该显示一次重建引导，关掉就不再显示', () async {
      await service.switchTo(AppMode.clear);
      expect(await service.shouldShowRebuildGuide(), isTrue);

      await service.markRebuildGuideShown();
      expect(await service.shouldShowRebuildGuide(), isFalse);
    });
  });

  test('已经在目标模式时不会重复写日志', () async {
    current = AppMode.clear;
    await service.switchTo(AppMode.clear);

    expect(await db.select(db.modeSwitchLogs).get(), isEmpty);
  });
}
