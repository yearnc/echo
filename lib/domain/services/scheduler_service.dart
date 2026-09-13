import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/analysis_repository.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/plan_event_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../models/app_mode.dart';
import '../models/echo_settings.dart';
import '../models/plan_script.dart';
import 'interaction_planner.dart';
import 'mode_switch_service.dart';

/// 切换模式的入口，由 UI 层注入（调度器不该知道自己跑在哪个页面里）。
typedef ModeSwitcher = void Function(AppMode target);

/// 互动调度服务（规划书 §7.3 的"现实方案"）。
///
/// 安卓/iOS 的后台任务都不可靠，所以这里不赌系统调度，
/// 而是**发帖时就把将来要发生的事排好队写进数据库**，
/// 然后在冷启动、回前台、前台心跳时扫一次"到点的"，一次性兑现。
/// 这样即使进程被杀、手机重启，排期也不会丢——它们本来就存在磁盘上。
///
/// 有两条队列，语义不同：
/// - **随机排期**（`ai_interactions`）：普通发帖，0—48 小时摊开，人格随机来点赞/评论
/// - **策划排期**（`plan_events`）：勾了策划模式的帖子，按脚本的秒级时间点精确执行
class SchedulerService {
  SchedulerService({
    required this.interactions,
    required this.planEvents,
    required this.posts,
    required this.notifications,
    required this.personas,
    required this.analyses,
    this.switchMode,
    InteractionPlanner? planner,
  }) : _planner = planner ?? InteractionPlanner();

  final InteractionRepository interactions;
  final PlanEventRepository planEvents;
  final PostRepository posts;
  final NotificationRepository notifications;
  final PersonaRepository personas;
  final AnalysisRepository analyses;
  final ModeSwitcher? switchMode;
  final InteractionPlanner _planner;

  /// 发帖后调用：把这条帖子将来会收到的随机互动排进队列。
  ///
  /// 返回排期条数，方便在 UI 上给一句"反馈会在 0—48 小时内陆续出现"。
  Future<int> planForPost({
    required String postId,
    required EchoSettings settings,
  }) async {
    // 人格是**内容资产**（含样例评论、作息），所以从 assets 读，
    // 数据库里那份只承担运行期状态。
    final pool = await personas.loadAll();
    final planned = _planner.plan(
      now: DateTime.now(),
      personas: pool,
      settings: settings,
    );
    await interactions.insertPlanned(postId, planned);
    return planned.length;
  }

  /// 策划模式发帖时调用：按脚本把事件排成**秒级**队列。
  ///
  /// `at` 支持 `"30"`（第 30 秒）与 `"30~90"`（区间内随机取一个时刻），
  /// 区间在排期时就算成确定的时间点——这样队列里存的是绝对时间，
  /// 每次心跳只需要比较大小，不必重算。
  Future<int> planFromScript({
    required String postId,
    required PlanScript script,
    Random? random,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rng = random ?? Random();

    final events = <PlannedPlanEvent>[];
    for (final step in script.steps) {
      if (!step.isValid) continue;
      events.add(PlannedPlanEvent(step: step, atMs: now + step.resolveMs(rng)));
    }
    events.sort((a, b) => a.atMs.compareTo(b.atMs));

    await planEvents.insertAll(
      postId: postId,
      scriptId: script.id,
      events: events,
    );
    return events.length;
  }

  /// 冷启动 / 回前台 / 心跳时调用：把到期的随机排期兑现成真实互动与通知。
  Future<int> flushDue() async {
    final due = await interactions.duePending(DateTime.now());
    if (due.isEmpty) return 0;

    final pool = await personas.loadAll();
    final nameById = {for (final p in pool) p.id: p.name};

    for (final item in due) {
      await interactions.markExecuted(item.id);

      final name = nameById[item.personaId] ?? '社区住民';

      if (item.isLike) {
        await posts.addCounters(item.postId, likes: item.likeBatch);
        await notifications.insert(
          id: 'n_${item.id}',
          postId: item.postId,
          type: 'like',
          title: item.likeBatch > 1
              ? '$name 等 ${item.likeBatch} 人赞了你的帖子'
              : '$name 赞了你的帖子',
          body: '你有一条社区互动通知',
        );
      } else if (item.isComment) {
        await posts.addCounters(item.postId, comments: 1);
        await notifications.insert(
          id: 'n_${item.id}',
          postId: item.postId,
          type: 'comment',
          title: '$name 评论了你的帖子',
          body: item.content ?? '',
        );
      }
    }

    return due.length;
  }

  /// 兑现到点的策划事件。
  ///
  /// 评论会额外写一条已完成的互动（评论区用的还是同一套查询），
  /// 点赞与"设定数据"直接改帖子计数，切模式与分析各自走自己的通道。
  Future<int> flushPlanEvents() async {
    final due = await planEvents.duePending(DateTime.now());
    if (due.isEmpty) return 0;

    final pool = await personas.loadAll();
    final nameById = {for (final p in pool) p.id: p.name};

    for (final event in due) {
      await planEvents.markExecuted(event.id);

      switch (event.type) {
        case PlanStepType.comment:
          final personaId = event.personaId;
          if (personaId == null) break;
          await interactions.insertExecutedComment(
            id: 'evt_${event.id}',
            postId: event.postId,
            personaId: personaId,
            mediaType: event.mediaType,
            content: event.content,
            voicePath: event.voiceAsset,
            transcript: event.transcript,
          );
          await posts.addCounters(event.postId, comments: 1);
          await notifications.insert(
            id: 'n_${event.id}',
            postId: event.postId,
            type: 'comment',
            title: '${nameById[personaId] ?? '社区住民'} 评论了你的帖子',
            body: event.content ?? '',
          );

        case PlanStepType.likeBurst:
          final delta = event.delta ?? 0;
          if (delta <= 0) break;
          await posts.addCounters(event.postId, likes: delta);
          await notifications.insert(
            id: 'n_${event.id}',
            postId: event.postId,
            type: 'like',
            title: delta > 1 ? '有 $delta 人赞了你的帖子' : '有人赞了你的帖子',
            body: '你有一条社区互动通知',
          );

        case PlanStepType.stats:
          await posts.setCounters(
            event.postId,
            likes: event.likes,
            comments: event.comments,
          );

        case PlanStepType.mode:
          switchMode?.call(AppMode.fromScope(event.toMode));

        case PlanStepType.analysis:
          final raw = event.analysisJson;
          if (raw == null || raw.isEmpty) break;
          await analyses.insertFromPlan(
            postId: event.postId,
            analysis: PlanAnalysis.fromJson(
              jsonDecode(raw) as Map<String, dynamic>,
            ),
          );
      }
    }

    return due.length;
  }

  /// 还剩多少条随机排期没到点（调试与"预告"用）。
  Future<int> pendingCount() => interactions.countPending();

  /// 还剩多少条策划事件没执行（心跳靠它决定要不要跑秒级）。
  Future<int> pendingPlanCount() => planEvents.countPending();
}

final schedulerServiceProvider = Provider<SchedulerService>(
  (ref) => SchedulerService(
    interactions: ref.watch(interactionRepositoryProvider),
    planEvents: ref.watch(planEventRepositoryProvider),
    posts: ref.watch(postRepositoryProvider),
    notifications: ref.watch(notificationRepositoryProvider),
    personas: ref.watch(personaRepositoryProvider),
    analyses: ref.watch(analysisRepositoryProvider),
    switchMode: (target) {
      // 脚本里的"切模式"走完整切换规则：该归档的归档、该留痕的留痕。
      // 冷却期不在这里拦——脚本演出是显式意图，不是用户随手点。
      ref.read(modeSwitchServiceProvider).switchTo(target);
    },
  ),
);
