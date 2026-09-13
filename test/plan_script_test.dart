import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/analysis_repository.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/notification_repository.dart';
import 'package:echo/data/repositories/persona_repository.dart';
import 'package:echo/data/repositories/plan_event_repository.dart';
import 'package:echo/data/repositories/plan_script_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/seed/builtin_plan_scripts.dart';
import 'package:echo/domain/models/app_mode.dart';
import 'package:echo/domain/models/plan_script.dart';
import 'package:echo/domain/services/scheduler_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlanStep 时间解析（秒级）', () {
    test('写单个秒数就取那一秒', () {
      const step = PlanStep(at: '30', type: PlanStepType.comment);
      expect(step.rangeMs, (30000, 30000));
      expect(step.resolveMs(Random(1)), 30000);
    });

    test('第 1 秒就是第 1 秒（不因为心跳粒度被推后）', () {
      const step = PlanStep(at: '1', type: PlanStepType.likeBurst, delta: 3);
      expect(step.resolveMs(Random(7)), 1000);
    });

    test('支持小数秒', () {
      const step = PlanStep(at: '1.2', type: PlanStepType.comment);
      expect(step.resolveMs(Random(1)), 1200);
    });

    test('区间里随机取一个时刻，且始终落在区间内', () {
      const step = PlanStep(at: '30~90', type: PlanStepType.comment);
      for (var seed = 0; seed < 30; seed++) {
        expect(step.resolveMs(Random(seed)), inInclusiveRange(30000, 90000));
      }
    });

    test('写法不合法时能被识别出来', () {
      expect(
        const PlanStep(at: 'abc', type: PlanStepType.comment).isValid,
        isFalse,
      );
      expect(
        const PlanStep(at: '', type: PlanStepType.comment).isValid,
        isFalse,
      );
      expect(
        const PlanStep(at: '-5', type: PlanStepType.comment).isValid,
        isFalse,
      );
      expect(
        const PlanStep(at: '30', type: PlanStepType.comment).isValid,
        isTrue,
      );
    });
  });

  group('PlanScript 序列化', () {
    test('JSON 往返不丢字段', () {
      const script = PlanScript(
        id: 'x',
        name: '测试脚本',
        postContent: '正文',
        postImages: ['asset:a.jpg'],
        topicName: '日常',
        steps: [
          PlanStep(
            at: '5',
            type: PlanStepType.comment,
            personaId: 'persona_001',
            content: '你好',
          ),
          PlanStep(at: '10~20', type: PlanStepType.likeBurst, delta: 12),
          PlanStep(at: '30', type: PlanStepType.mode, toMode: 'clear'),
        ],
      );

      final restored = PlanScript.fromJson(
        jsonDecode(jsonEncode(script.toJson())) as Map<String, dynamic>,
      );

      expect(restored.name, '测试脚本');
      expect(restored.topicName, '日常');
      expect(restored.steps.length, 3);
      expect(restored.steps[1].delta, 12);
      expect(restored.steps[2].toMode, 'clear');
    });

    test('兼容旧脚本的 atMs（毫秒）写法', () {
      final step = PlanStep.fromJson(<String, dynamic>{
        'atMs': 1500,
        'type': 'comment',
        'content': '旧格式',
      });
      expect(step.at, '1.5');
      expect(step.resolveMs(Random(1)), 1500);
    });
  });

  group('三幕脚本转成内置策划脚本', () {
    test('转换后只剩会真实发生的事件，且第三幕复用第一幕的开局内容', () async {
      final scripts = await BuiltinPlanScripts.load();

      expect(scripts.length, 3);
      expect(scripts.every((s) => s.isBuiltIn), isTrue);
      expect(
        scripts.first.steps.any((s) => s.type == PlanStepType.comment),
        isTrue,
        reason: '第一幕应该有评论',
      );

      // 第三幕的关键是"同一张天空照"，所以它的开局内容必须与第一幕一致
      expect(scripts[2].postContent, scripts[0].postContent);
      expect(
        scripts[2].steps.any((s) => s.type == PlanStepType.analysis),
        isTrue,
      );

      // 拍摄专用装饰不该被带进策划模式
      const banned = {
        'overlay',
        'end_card',
        'caption_suggestion',
        'confirm_dialog',
        'rebuild_guide',
        'weekly_report_preview',
      };
      for (final script in scripts) {
        for (final step in script.steps) {
          expect(
            banned.contains(step.type),
            isFalse,
            reason: '混进了 ${step.type}',
          );
        }
      }
    });
  });

  group('内置策划脚本', () {
    late AppDatabase db;
    late PlanScriptRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = PlanScriptRepository(db);
    });

    tearDown(() async => db.close());

    test('首次启动播种三个，删掉之后还能恢复', () async {
      final builtIns = await BuiltinPlanScripts.load();

      await repo.seedIfEmpty(builtIns);
      expect(await repo.count(), 3, reason: '三幕应该都播下去');

      // 内置脚本是可以删的
      await repo.delete(builtIns.first.id);
      expect(await repo.count(), 2);

      expect(await repo.restoreBuiltIns(builtIns), 1, reason: '补回被删的那个');
      expect(await repo.count(), 3);

      // 都在的时候不该重复插
      expect(await repo.restoreBuiltIns(builtIns), 0);
      expect(await repo.count(), 3);
    });
  });

  group('SchedulerService（策划排期与兑现）', () {
    late AppDatabase db;
    late PostRepository posts;
    late SchedulerService scheduler;
    AppMode? switched;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      posts = PostRepository(db);
      scheduler = SchedulerService(
        interactions: InteractionRepository(db),
        planEvents: PlanEventRepository(db),
        posts: posts,
        notifications: NotificationRepository(db),
        personas: const PersonaRepository(),
        analyses: AnalysisRepository(db),
        switchMode: (mode) => switched = mode,
      );
      switched = null;

      await db
          .into(db.aiPersonas)
          .insert(AiPersonasCompanion.insert(id: 'persona_0', name: '住民0'));
    });

    tearDown(() async => db.close());

    /// 把还没执行的策划事件全部挪到过去，模拟"时间走过了那些秒"。
    Future<void> rewindSchedule() async {
      await db
          .update(db.planEvents)
          .write(
            PlanEventsCompanion(
              scheduledAt: Value(DateTime.now().millisecondsSinceEpoch - 1000),
            ),
          );
    }

    test('按脚本排期后在到点前什么都不该发生', () async {
      final postId = await posts.create(content: '天空照', scope: 'echo');
      const script = PlanScript(
        id: 's1',
        name: '测试',
        steps: [
          PlanStep(at: '600', type: PlanStepType.likeBurst, delta: 7),
          PlanStep(
            at: '900',
            type: PlanStepType.comment,
            personaId: 'persona_0',
            content: '好看',
          ),
        ],
      );

      expect(await scheduler.planFromScript(postId: postId, script: script), 2);
      expect(await scheduler.pendingPlanCount(), 2);

      expect(await scheduler.flushPlanEvents(), 0);
      final post = await posts.findById(postId);
      expect(post!.likeCount, 0);
      expect(post.commentCount, 0);
    });

    test('到点后点赞与评论逐条兑现，评论进评论区', () async {
      final postId = await posts.create(content: '天空照', scope: 'echo');
      const script = PlanScript(
        id: 's2',
        name: '测试',
        steps: [
          PlanStep(at: '5', type: PlanStepType.likeBurst, delta: 7),
          PlanStep(
            at: '10',
            type: PlanStepType.comment,
            personaId: 'persona_0',
            content: '好看',
          ),
        ],
      );

      await scheduler.planFromScript(postId: postId, script: script);
      await rewindSchedule();

      expect(await scheduler.flushPlanEvents(), 2);
      expect(await scheduler.pendingPlanCount(), 0);

      final post = await posts.findById(postId);
      expect(post!.likeCount, 7);
      expect(post.commentCount, 1);

      final comments = await db.select(db.aiInteractions).get();
      expect(comments.length, 1);
      expect(comments.first.content, '好看');
      expect(comments.first.status, 'done');
      expect(comments.first.postId, postId);

      // 通知要能指回原帖，否则点通知跳不过去
      final notices = await db.select(db.notificationLogs).get();
      expect(notices.length, 2);
      expect(notices.every((n) => n.postId == postId), isTrue);
    });

    test('设定数据事件直接把计数设成脚本里的值', () async {
      final postId = await posts.create(content: '深夜垃圾桶', scope: 'echo');
      const script = PlanScript(
        id: 's3',
        name: '测试',
        steps: [
          PlanStep(at: '1', type: PlanStepType.stats, likes: 203, comments: 11),
        ],
      );

      await scheduler.planFromScript(postId: postId, script: script);
      await rewindSchedule();
      await scheduler.flushPlanEvents();

      final post = await posts.findById(postId);
      expect(post!.likeCount, 203);
      expect(post.commentCount, 11);
      expect(post.isHot, isTrue);
    });

    test('切模式与展示分析各自走自己的通道', () async {
      final postId = await posts.create(content: '天空照', scope: 'echo');
      const script = PlanScript(
        id: 's4',
        name: '测试',
        steps: [
          PlanStep(at: '5', type: PlanStepType.mode, toMode: 'clear'),
          PlanStep(
            at: '11',
            type: PlanStepType.analysis,
            analysis: PlanAnalysis(
              imageDescription: '一片云',
              suggestions: '补上时间',
            ),
          ),
        ],
      );

      await scheduler.planFromScript(postId: postId, script: script);
      await rewindSchedule();
      await scheduler.flushPlanEvents();

      expect(switched, AppMode.clear);

      final saved = await AnalysisRepository(db).findByPost(postId);
      expect(saved, isNotNull);
      expect(saved!.imageDescription, '一片云');
      expect(saved.suggestions, '补上时间');
    });

    test('写法不合法的事件不会进队列', () async {
      final postId = await posts.create(content: '天空照', scope: 'echo');
      const script = PlanScript(
        id: 's5',
        name: '测试',
        steps: [
          PlanStep(at: 'abc', type: PlanStepType.likeBurst, delta: 5),
          PlanStep(at: '8', type: PlanStepType.likeBurst, delta: 5),
        ],
      );

      expect(await scheduler.planFromScript(postId: postId, script: script), 1);
    });
  });
}
