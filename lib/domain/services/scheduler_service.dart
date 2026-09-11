import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../models/echo_settings.dart';
import 'interaction_planner.dart';

/// 互动调度服务（规划书 §7.3 的"现实方案"）。
///
/// 安卓/iOS 的后台任务都不可靠，所以这里不赌系统调度：
/// **发帖时就把 0—48 小时的互动排好队写进数据库**，
/// 然后在冷启动、回前台时扫一次"到点的"，一次性兑现。
/// 这样即使进程被杀、手机重启，排期也不会丢——它们本来就存在磁盘上。
class SchedulerService {
  SchedulerService({
    required this.interactions,
    required this.posts,
    required this.notifications,
    required this.personas,
    InteractionPlanner? planner,
  }) : _planner = planner ?? InteractionPlanner();

  final InteractionRepository interactions;
  final PostRepository posts;
  final NotificationRepository notifications;
  final PersonaRepository personas;
  final InteractionPlanner _planner;

  /// 发帖后调用：把这条帖子将来会收到的互动排进队列。
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

  /// 冷启动 / 回前台时调用：把到期的排期兑现成真实的互动与通知。
  ///
  /// 返回兑现条数（0 表示暂时没有新的）。
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
          type: 'comment',
          title: '$name 评论了你的帖子',
          body: item.content ?? '',
        );
      }
    }

    return due.length;
  }

  /// 还剩多少条没到点（调试与"预告"用）。
  Future<int> pendingCount() => interactions.countPending();
}

final schedulerServiceProvider = Provider<SchedulerService>(
  (ref) => SchedulerService(
    interactions: ref.watch(interactionRepositoryProvider),
    posts: ref.watch(postRepositoryProvider),
    notifications: ref.watch(notificationRepositoryProvider),
    personas: ref.watch(personaRepositoryProvider),
  ),
);
