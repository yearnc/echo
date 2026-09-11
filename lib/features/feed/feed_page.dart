import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/seed/demo_posts.dart';
import '../../domain/models/post.dart';
import '../shared_widgets/post_image.dart';
import '../shared_widgets/user_avatar.dart';

/// 回响模式首页：信息流（规划书 §3.4）。
///
/// 视觉上刻意做成"热闹"的：等级、经验条、勋章、热度标签、点赞头像堆叠——
/// 这些元素本身就是要让用户感到被看见。它们不是装饰，是这个产品的主题。
class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = DemoPosts.feedEcho;
    final comments = DemoPosts.comments;

    return Container(
      color: EchoColors.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const _PlazaHeader(),
          const SizedBox(height: 14),
          const _MeCard(),
          const SizedBox(height: 16),
          const _FilterChips(),
          const SizedBox(height: 12),
          for (final post in posts) ...[
            _PostCard(post: post, comments: comments[post.id] ?? const []),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

/// 社区头部。长按标题 3 秒进入演示模式（规划书 §3.12 的隐藏入口）。
class _PlazaHeader extends StatelessWidget {
  const _PlazaHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onLongPress: () => context.push(RoutePaths.demo),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '回响广场',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: EchoColors.text,
                        fontSize: 26,
                      ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: EchoColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '回响大学 · 平行校园社区',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: EchoColors.textMuted,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: () => context.push(RoutePaths.demo),
          icon: const Icon(Icons.science_outlined, color: EchoColors.textMuted),
          tooltip: '演示模式',
        ),
      ],
    );
  }
}

/// 顶部个人卡片（规划书 §3.4）：等级、经验条、勋章、连续签到。
class _MeCard extends StatelessWidget {
  const _MeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF231C42), Color(0xFF17142B)],
        ),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const UserAvatar(name: AppTexts.defaultNickname, size: 46, showRing: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          AppTexts.defaultNickname,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: EchoColors.text,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(width: 8),
                        const _LevelChip(level: 3),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const _ExpBar(value: 0.42),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('连续签到',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: EchoColors.textFaint)),
                  const SizedBox(height: 2),
                  Text('7 天',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: EchoColors.hot,
                            fontWeight: FontWeight.w700,
                          )),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              _Stat(label: '帖子', value: '2'),
              _Stat(label: '获赞', value: '284'),
              _Stat(label: '评论', value: '9'),
              _Stat(label: '粉丝', value: '2'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: EchoColors.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EchoColors.primary.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Lv.$level',
        style: const TextStyle(
          color: EchoColors.primary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ExpBar extends StatelessWidget {
  const _ExpBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 5,
        backgroundColor: EchoColors.overlay,
        valueColor: const AlwaysStoppedAnimation(EchoColors.primary),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: EchoColors.text,
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 2),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: EchoColors.textFaint)),
        ],
      ),
    );
  }
}

class _FilterChips extends StatefulWidget {
  const _FilterChips();

  @override
  State<_FilterChips> createState() => _FilterChipsState();
}

class _FilterChipsState extends State<_FilterChips> {
  static const List<String> _filters = ['推荐', '关注', '同校', '热榜'];
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == _selected;
          return GestureDetector(
            onTap: () => setState(() => _selected = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? EchoColors.primary.withValues(alpha: 0.16)
                    : EchoColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? EchoColors.primary.withValues(alpha: 0.5)
                      : EchoColors.divider,
                ),
              ),
              child: Text(
                _filters[index],
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? EchoColors.primary : EchoColors.textMuted,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.comments});

  final Post post;
  final List<PostComment> comments;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(RoutePaths.post(post.id)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: EchoColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: EchoColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const UserAvatar(name: AppTexts.defaultNickname, size: 38, showRing: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppTexts.defaultNickname,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                color: EchoColors.text,
                                fontWeight: FontWeight.w600,
                              )),
                      const SizedBox(height: 2),
                      Text(
                        '${post.topicName ?? '日常'} · ${RelativeTime.short(post.createdAt)}',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: EchoColors.textFaint),
                      ),
                    ],
                  ),
                ),
                if (post.isHot) const _HotBadge(),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              post.content,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: EchoColors.text),
            ),
            if (post.hasImages) ...[
              const SizedBox(height: 10),
              PostImage(ref: post.images.first),
            ],
            const SizedBox(height: 12),
            _PostFooter(post: post, comments: comments),
          ],
        ),
      ),
    );
  }
}

class _HotBadge extends StatelessWidget {
  const _HotBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: EchoColors.hot.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.local_fire_department, size: 12, color: EchoColors.hot),
          SizedBox(width: 3),
          Text('热',
              style: TextStyle(
                color: EchoColors.hot,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

class _PostFooter extends ConsumerWidget {
  const _PostFooter({required this.post, required this.comments});

  final Post post;
  final List<PostComment> comments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 点赞头像堆叠：用评论过的人格头像拼出"有人在这里"的感觉
    final likerIds = comments.take(3).map((c) => c.personaId).toList();

    return Row(
      children: [
        if (likerIds.isNotEmpty) ...[
          SizedBox(
            width: 22.0 + (likerIds.length - 1) * 15,
            height: 22,
            child: Stack(
              children: [
                for (var i = 0; i < likerIds.length; i++)
                  Positioned(
                    left: i * 15.0,
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: EchoColors.surface,
                      ),
                      padding: const EdgeInsets.all(1),
                      child: UserAvatar(
                        name: ref.watch(personaNameProvider(likerIds[i])),
                        avatarRef:
                            ref.watch(personaByIdProvider(likerIds[i]))?.avatar,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        _IconStat(
          icon: Icons.favorite_border,
          label: '${post.likeCount}',
          color: EchoColors.like,
        ),
        const SizedBox(width: 14),
        _IconStat(
          icon: Icons.mode_comment_outlined,
          label: '${post.commentCount}',
          color: EchoColors.textMuted,
        ),
        const Spacer(),
        const Icon(Icons.more_horiz, size: 18, color: EchoColors.textFaint),
      ],
    );
  }
}

class _IconStat extends StatelessWidget {
  const _IconStat({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12.5)),
      ],
    );
  }
}
