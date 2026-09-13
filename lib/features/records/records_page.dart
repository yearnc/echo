import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/post_repository.dart';
import '../../domain/models/post.dart';
import '../../domain/services/mode_switch_service.dart';

/// 是否该显示一次"重建引导"（切到清醒模式之后）。
final rebuildGuideProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(modeSwitchServiceProvider).shouldShowRebuildGuide(),
);

/// 切到清醒模式后显示一次的"重建引导"（规划书 §2.4.1）。
///
/// 只提示一次：用户看过就关掉，之后不再打扰——引导的意义是"扶一把"，
/// 不是每天提醒他"你刚戒掉了什么"。
class _RebuildGuideBanner extends ConsumerWidget {
  const _RebuildGuideBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ClearColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ClearColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wb_twilight, size: 17, color: ClearColors.primary),
              const SizedBox(width: 7),
              Text(
                '从这里开始',
                style: TextStyle(
                  color: ClearColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  await ref
                      .read(modeSwitchServiceProvider)
                      .markRebuildGuideShown();
                  ref.invalidate(rebuildGuideProvider);
                },
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: ClearColors.textFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '虚拟互动已经停了，那些点赞和评论不会再增加。\n'
            '建议先做一次价值澄清——写下你真正重视的事，再挑一件今天真的做过的小事记下来。',
            style: TextStyle(
              color: ClearColors.textMuted,
              fontSize: 12.5,
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// 清醒模式的"记录"页（规划书 §4 / §5.1）。
///
/// 与回响模式首页的对照是刻意的：**没有点赞、没有评论、没有热度标签**。
/// 唯一的数字是"这周真实行动了几次"，而那是用户自己数出来的。
class RecordsPage extends ConsumerWidget {
  const RecordsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(feedPostsProvider('clear'));
    final records = recordsAsync.value ?? const <Post>[];
    final showRebuildGuide = ref.watch(rebuildGuideProvider).value ?? false;

    return Container(
      color: ClearColors.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '记录',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: ClearColors.text, fontSize: 24),
          ),
          const SizedBox(height: 4),
          Text(
            '这里只有你写下的东西，没有人为你打分。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: ClearColors.textMuted),
          ),
          const SizedBox(height: 16),
          if (showRebuildGuide) ...[
            const _RebuildGuideBanner(),
            const SizedBox(height: 14),
          ],
          const _WeeklyCard(),
          const SizedBox(height: 14),
          const _EntryCard(
            icon: Icons.psychology_alt_outlined,
            title: '价值澄清',
            subtitle: '写下你真正重视的 5 件事',
            route: RoutePaths.analysis,
          ),
          const SizedBox(height: 10),
          const _EntryCard(
            icon: Icons.directions_walk,
            title: '真实行动',
            subtitle: '记录今天做过的一件线下小事',
            route: RoutePaths.analysis,
          ),
          const SizedBox(height: 20),
          Text(
            '最近',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: ClearColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                AppTexts.emptyRecords,
                textAlign: TextAlign.center,
                style: TextStyle(color: ClearColors.textMuted, height: 1.7),
              ),
            )
          else
            for (final record in records) _RecordTile(record: record),
        ],
      ),
    );
  }
}

class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ClearColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ClearColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 15,
                color: ClearColors.primary,
              ),
              const SizedBox(width: 7),
              Text(
                '本周',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: ClearColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              _WeeklyStat(value: '4', label: '真实行动'),
              _WeeklyStat(value: '5', label: '情绪平稳（天）'),
              _WeeklyStat(value: '0', label: '展示的点赞数'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '这份周报不统计点赞和评论，只统计你真实做过的事。',
            style: TextStyle(
              color: ClearColors.textMuted,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyStat extends StatelessWidget {
  const _WeeklyStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: ClearColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: ClearColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(route),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ClearColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ClearColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: ClearColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: ClearColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: ClearColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: ClearColors.textFaint, size: 20),
          ],
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final Post record;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
            record.content,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: ClearColors.text),
          ),
          const SizedBox(height: 8),
          Text(
            RelativeTime.format(record.createdAt),
            style: TextStyle(color: ClearColors.textFaint, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
