import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_texts.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/addiction_repository.dart';
import '../../data/repositories/clear_journal_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../data/repositories/usage_repository.dart';

/// 数字关系反思的数据（v31）。
///
/// 全部是可追溯到具体表的数字。这里不做“你该少用一点”的判断，
/// 只把线上投入与线下做过的事并排放着，让用户自己看。
class ReflectionData {
  const ReflectionData({
    required this.weekMinutes,
    required this.feedbackViews,
    required this.waits,
    required this.aiReplies,
    required this.stayMinutes,
    required this.posts,
    required this.records,
    required this.actions,
  });

  final int weekMinutes;
  final int feedbackViews;
  final int waits;
  final int aiReplies;
  final int stayMinutes;
  final int posts;
  final int records;
  final int actions;

  int get onlineTotal => feedbackViews + waits + aiReplies;
  int get offlineTotal => records + actions;
}

final reflectionDataProvider = FutureProvider.autoDispose<ReflectionData>((
  ref,
) async {
  final now = DateTime.now();
  final since = now.subtract(const Duration(days: 7));
  final sinceMs = since.millisecondsSinceEpoch;

  final usage = await ref.watch(usageRepositoryProvider).totalMsSince(since);
  final addiction = ref.watch(addictionRepositoryProvider);
  final dashboard = ref.watch(dashboardRepositoryProvider);
  final interactions = await dashboard.executedInteractions(since: since);
  final posts = await dashboard.myPostTimes(since: since);
  final clearRecords = await ref.watch(feedPostsProvider('clear').future);
  final actions = await ref.watch(realActionsProvider.future);

  final aiReplies = interactions.fold<int>(
    0,
    (sum, item) => sum + (item.isLike ? (item.likeBatch < 1 ? 1 : item.likeBatch) : 1),
  );

  return ReflectionData(
    weekMinutes: (usage / 60000).round(),
    feedbackViews: await addiction.countFeedbackViewsSince(sinceMs),
    waits: await addiction.countEventsSince(
      AddictionEventType.screenWait,
      sinceMs,
    ),
    aiReplies: aiReplies,
    stayMinutes:
        ((await addiction.totalStayMsSince(sinceMs)) / 60000).round(),
    posts: posts.length,
    records: clearRecords.length,
    actions: actions.where((action) => !action.createdAt.isBefore(since)).length,
  );
});

/// 数字关系（规划书 v2.2 第 448 行附近）。
///
/// 线上：打开过多久、回来看过几次、等过几次回应；
/// 线下：写下几条记录、真正做过几件事。
///
/// 两栏并排，不比较、不打分。页脚那句“不是让你内疚”必须留在原地——
/// 这份页面最容易滑向说教，而说教只会让人关掉它。
class ReflectionPage extends ConsumerWidget {
  const ReflectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reflectionDataProvider);

    return Scaffold(
      backgroundColor: ClearColors.bg,
      appBar: AppBar(
        backgroundColor: ClearColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: ClearColors.text),
        title: Text(
          '数字关系',
          style: TextStyle(color: ClearColors.text, fontSize: 16),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            '读取失败：$error',
            style: TextStyle(color: ClearColors.textMuted, fontSize: 12.5),
          ),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              '这 7 天，线上和线下',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: ClearColors.text,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '只列能对上账的数字，不给你打分。',
              style: TextStyle(color: ClearColors.textMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ColumnCard(
                    title: '线上',
                    icon: Icons.phone_iphone,
                    lines: [
                      ('打开 APP', _duration(data.weekMinutes)),
                      ('回来看反馈', '${data.feedbackViews} 次'),
                      ('停留在帖子页', _duration(data.stayMinutes)),
                      ('盯着屏幕等待', '${data.waits} 次'),
                      ('收到 AI 回应', '${data.aiReplies} 次'),
                      ('在社区发的内容', '${data.posts} 条'),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ColumnCard(
                    title: '线下',
                    icon: Icons.directions_walk,
                    lines: [
                      ('写下的记录', '${data.records} 条'),
                      ('真实做过的事', '${data.actions} 件'),
                    ],
                    accent: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ClearColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ClearColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '这些数字从哪来',
                    style: TextStyle(
                      color: ClearColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '打开时长来自前台会话记录；回来看反馈、停留与等待来自防沉迷日志；'
                    'AI 回应来自已兑现的互动；线下数字来自你自己写下的记录与行动。\n'
                    '这里没有一条数字是估算的，也没有一条来自模型。',
                    style: TextStyle(
                      color: ClearColors.textMuted,
                      fontSize: 12,
                      height: 1.8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                AppTexts.permanentNotice,
                textAlign: TextAlign.center,
                style: TextStyle(color: ClearColors.textFaint, fontSize: 10.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _duration(int minutes) {
    if (minutes < 1) return '不到 1 分钟';
    if (minutes < 60) return '$minutes 分钟';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
  }
}

class _ColumnCard extends StatelessWidget {
  const _ColumnCard({
    required this.title,
    required this.icon,
    required this.lines,
    this.accent = false,
  });

  final String title;
  final IconData icon;
  final List<(String, String)> lines;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ClearColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent
              ? ClearColors.primary.withValues(alpha: 0.35)
              : ClearColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: accent ? ClearColors.primary : ClearColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: ClearColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (label, value) in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: accent ? ClearColors.primary : ClearColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    label,
                    style: TextStyle(
                      color: ClearColors.textFaint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
