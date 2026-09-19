import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/analysis_repository.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/plan_event_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../models/ai_persona.dart';
import '../models/echo_settings.dart';
import '../models/plan_script.dart';
import 'content_generator.dart';
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
    required this.generator,
    this.readCoolDown,
    InteractionPlanner? planner,
  }) : _planner = planner ?? InteractionPlanner();

  final InteractionRepository interactions;
  final PlanEventRepository planEvents;
  final PostRepository posts;
  final NotificationRepository notifications;
  final PersonaRepository personas;
  final AnalysisRepository analyses;

  /// 住民说什么话由它出：配了模型就是模型写的，没配就是预置台词。
  final ContentGenerator generator;

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

  /// 发帖之后调：把还没兑现的评论交给模型重写一遍。
  ///
  /// 排期那一步已经用预置台词填过内容了，所以这一步**不是必需的**——
  /// 模型写得慢、写挂了、或者用户压根没配模型，排期照常走，社区照样有人说话。
  /// 它做的只是"把台词换成真的"。
  ///
  /// 调用方**不该 await** 它：写五六条评论要好几秒，用户没道理站在发布页等。
  Future<void> upgradeCommentsWithModel(String postId) async {
    try {
      final personaIds = await interactions.pendingCommentPersonaIds(postId);
      if (personaIds.isEmpty) return;

      final post = await posts.findById(postId);
      if (post == null) return;

      final pool = await personas.loadAll();
      final byId = {for (final persona in pool) persona.id: persona};
      final targets = personaIds
          .map((id) => byId[id])
          .whereType<AiPersona>()
          .toList(growable: false);
      if (targets.isEmpty) return;

      final generated = await generator.comments(
        personas: targets,
        post: post,
      );
      await interactions.updatePendingComments(postId, generated);
    } catch (error) {
      // 这一步失败无所谓——库里已经有台词了。留个痕是为了排查
      // "为什么住民说的话一直是那几句"。
      debugPrint('[内容生成] 评论没能换成模型写的：$error');
    }
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

    // 这些帖子里哪些是住民自己发的。住民动态下面也会来人——那是社区
    // 自己的动静，不是"有人回应了你"，所以照样记数、不通知用户。
    final peersPosts = await posts.residentAuthorsOf(
      due.map((item) => item.postId).toSet(),
    );

    for (final item in due) {
      await interactions.markExecuted(item.id);

      final name = nameById[item.personaId] ?? '社区住民';
      final isMyPost = !peersPosts.containsKey(item.postId);

      if (item.isLike) {
        await posts.addCounters(item.postId, likes: item.likeBatch);
        if (!isMyPost) continue;
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
        if (!isMyPost) continue;
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
    generator: ref.watch(contentSourceProvider),
    readCoolDown: () => ref.read(safetyControllerProvider).coolDownMode,
  ),
);
