import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/analysis_repository.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/plan_event_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../models/echo_settings.dart';
import '../models/plan_script.dart';
import 'interaction_planner.dart';
import 'safety_controller.dart';

// 策划脚本只安排"这条帖子会收到什么回应"，所以这里没有"切模式""跳页面"的
// 入口：那些动作在拍摄时由人手动完成，不由脚本代劳。

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
    this.readCoolDown,
    InteractionPlanner? planner,
  }) : _planner = planner ?? InteractionPlanner();

  final InteractionRepository interactions;
  final PlanEventRepository planEvents;
  final PostRepository posts;
  final NotificationRepository notifications;
  final PersonaRepository personas;
  final AnalysisRepository analyses;

  /// 冷静模式是否开启。用回调注入而不是直接读设置，
  /// 是为了让调度器仍然可以被单独测试（传 null 就是"从不冷静"）。
  final bool Function()? readCoolDown;

  final InteractionPlanner _planner;

  /// 冷静模式下，新帖的第一条反馈至少要等这么久（规划书 §6.9）。
  static const Duration coolDownDelay = Duration(minutes: 10);

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
    final delay = (readCoolDown?.call() ?? false)
        ? coolDownDelay
        : Duration.zero;
    final planned = _planner.plan(
      now: DateTime.now(),
      personas: pool,
      settings: settings,
      delay: delay,
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
            voiceDurationMs: event.voiceDurationMs,
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
    readCoolDown: () => ref.read(safetyControllerProvider).coolDownMode,
  ),
);
