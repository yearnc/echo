import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/clear_journal_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../domain/models/clear_journal.dart';
import '../../domain/models/post.dart';
import '../../domain/services/clear_data_service.dart';
import '../../domain/services/mode_switch_service.dart';
import '../../domain/services/record_timeline.dart';
import '../shared_widgets/post_image.dart';

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

/// 清醒模式的「记录」页（规划书 §4 / §5.1）。
///
/// 与回响模式首页的对照是刻意的：**没有点赞、没有评论、没有热度标签**。
/// 唯一的数字是"这周记了几件"，而那是用户自己数出来的。
///
/// 「最近」是**一条时间线**：发布页写下的图文记录，和真实行动页打下的点，
/// 合成同一条往下走。它们本来就是同一件事的两种记法——一个能配图、成段，
/// 一个带分类、够快——分成两个列表只让人觉得"功能散了"（2026-09-15 实测反馈）。
class RecordsPage extends ConsumerWidget {
  const RecordsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records =
        ref.watch(feedPostsProvider('clear')).value ?? const <Post>[];
    final actions =
        ref.watch(realActionsProvider).value ?? const <RealAction>[];
    final entries = buildTimeline(posts: records, actions: actions);
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
            route: RoutePaths.values,
          ),
          const SizedBox(height: 10),
          const _EntryCard(
            icon: Icons.directions_walk,
            title: '真实行动',
            subtitle: '记录今天做过的一件线下小事',
            route: RoutePaths.actions,
          ),
          const SizedBox(height: 10),
          const _EntryCard(
            icon: Icons.photo_library_outlined,
            title: '真实生活相册',
            subtitle: '只收你主动选的、真实拍下的照片',
            route: RoutePaths.album,
          ),
          const SizedBox(height: 10),
          const _EntryCard(
            icon: Icons.compare_arrows,
            title: '数字关系',
            subtitle: '线上投入与线下做过的事，并排看',
            route: RoutePaths.reflection,
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
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                AppTexts.emptyRecords,
                textAlign: TextAlign.center,
                style: TextStyle(color: ClearColors.textMuted, height: 1.7),
              ),
            )
          else
            for (final entry in entries) _EntryTile(entry: entry),
          const SizedBox(height: 20),
          const _PrivacyCard(),
        ],
      ),
    );
  }
}

/// 清醒数据的导出与删除（v31）。
///
/// 隐私要求不是一句声明：用户得真的能把东西带走、也能真的删掉。
/// 导出只含清醒侧记录；删除也只碰清醒侧，回响数据一条不动。
class _PrivacyCard extends ConsumerStatefulWidget {
  const _PrivacyCard();

  @override
  ConsumerState<_PrivacyCard> createState() => _PrivacyCardState();
}

class _PrivacyCardState extends ConsumerState<_PrivacyCard> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await ref.read(clearDataServiceProvider).export();
      if (!mounted) return;

      // 先给系统分享面板：文件存在应用私有目录里，用户自己很难找到。
      // 分享失败（比如没有可用的分享目标）不影响导出本身，下面仍显示路径。
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(path)],
            text: '回响 · 清醒数据导出（只含本机真实记录）',
          ),
        );
      } catch (error) {
        debugPrint('[导出] 分享面板没打开：$error');
      }
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: ClearColors.surface,
          title: Text(
            '已导出',
            style: TextStyle(color: ClearColors.text, fontSize: 15),
          ),
          content: SelectableText(
            '文件保存在：\n$path\n\n'
            '内容只有清醒侧的真实记录，不含任何 AI 互动。',
            style: TextStyle(
              color: ClearColors.textMuted,
              fontSize: 12.5,
              height: 1.7,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出没成：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAll() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ClearColors.surface,
        title: Text(
          '清除清醒数据？',
          style: TextStyle(color: ClearColors.text, fontSize: 15),
        ),
        content: Text(
          '会删掉价值澄清、真实行动、清醒记录、相册照片、分析快照和使用时长。\n'
          '这一步不可撤销；回响侧的内容不受影响。',
          style: TextStyle(
            color: ClearColors.textMuted,
            fontSize: 13,
            height: 1.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('取消', style: TextStyle(color: ClearColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('全部清除', style: TextStyle(color: ClearColors.like)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(clearDataServiceProvider).deleteAllClearData();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('清醒数据已清除')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清除没成：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
            '数据与隐私',
            style: TextStyle(
              color: ClearColors.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '清醒数据只在你这台设备上。可以随时导出，也可以随时删干净。',
            style: TextStyle(
              color: ClearColors.textMuted,
              fontSize: 11.5,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.ios_share, size: 16),
                label: const Text('导出'),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: _busy ? null : _clearAll,
                icon: Icon(Icons.delete_outline, size: 17, color: ClearColors.like),
                label: Text(
                  '清除清醒数据',
                  style: TextStyle(color: ClearColors.like, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeeklyCard extends ConsumerWidget {
  const _WeeklyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionCount = ref.watch(weeklyRecordCountProvider).value;

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
            children: [
              _WeeklyStat(
                value: actionCount == null ? '—' : '$actionCount',
                // 两种记法一起数，所以标签不能再写"真实行动"——那是其中一个入口的名字
                label: '件你亲手记下的',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _MoodStrip(),
          const SizedBox(height: 12),
          Text(
            '这份周报不统计点赞和评论，只统计你真实做过的事——'
            '包括你顺手记下的心情。',
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

/// 周报里的情绪维度（B11）。
///
/// 一条按比例分的横条 + 一行数字：一眼能看出这周大致是什么滋味。
/// 没记过心情时不说"暂无数据"——那句话像在催人填表；
/// 这里只是告诉用户那个选项在哪。
class _MoodStrip extends ConsumerWidget {
  const _MoodStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moods =
        ref.watch(weeklyMoodsProvider).value ?? const <RealActionMood>[];
    final tally = tallyMoods(moods);

    if (tally.isEmpty) {
      return Text(
        '记一件事的时候顺手选个心情，这里就能看出这周大概是什么滋味。',
        style: TextStyle(
          color: ClearColors.textFaint,
          fontSize: 12,
          height: 1.6,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '这周记得最多的是「${tally.first.$1.label}」',
          style: TextStyle(color: ClearColors.text, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: [
              for (var i = 0; i < tally.length; i++)
                Expanded(
                  flex: tally[i].$2,
                  child: Container(
                    height: 8,
                    color: ClearColors.primary.withValues(
                      alpha: (0.9 - i * 0.16).clamp(0.25, 0.9),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          [
            for (final (mood, count) in tally) '${mood.label} $count',
          ].join(' · '),
          style: TextStyle(color: ClearColors.textMuted, fontSize: 11.5),
        ),
      ],
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
      // push 而不是 go：这两页是沉浸式的，退回来还在记录页
      onTap: () => context.push(route),
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

/// 时间线上的一条。两种记法在这里长得一样，只有分类标签和图片会区分它们。
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final category = entry.category;

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
          if (category != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: ClearColors.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                category,
                style: TextStyle(color: ClearColors.accent, fontSize: 10.5),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            entry.text,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: ClearColors.text),
          ),
          if (entry.detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              entry.detail,
              style: TextStyle(
                color: ClearColors.textMuted,
                fontSize: 12.5,
                height: 1.6,
              ),
            ),
          ],
          if (entry.images.isNotEmpty) ...[
            const SizedBox(height: 10),
            PostImage(ref: entry.images.first, height: 180),
          ],
          const SizedBox(height: 8),
          Text(
            RelativeTime.format(entry.at),
            style: TextStyle(color: ClearColors.textFaint, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
