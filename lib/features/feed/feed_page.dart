import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/post_repository.dart';
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
    final posts = ref.watch(feedPostsProvider('echo'));

    return Container(
      color: EchoColors.bg,
      child: posts.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: EchoColors.primary)),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '信息流加载失败：$error',
              textAlign: TextAlign.center,
              style: TextStyle(color: EchoColors.like, fontSize: 12),
            ),
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const _PlazaHeader(),
            const SizedBox(height: 16),
            if (list.isEmpty)
              const _EmptyFeed()
            else
              for (final post in list) ...[
                _PostCard(post: post),
                const SizedBox(height: 14),
              ],
          ],
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 30,
            color: EchoColors.textFaint,
          ),
          const SizedBox(height: 14),
          Text(
            AppTexts.emptyFeed,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: EchoColors.textMuted,
              height: 1.8,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// 社区头部。
class _PlazaHeader extends StatelessWidget {
  const _PlazaHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '回响广场',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: EchoColors.text, fontSize: 26),
        ),
        const SizedBox(height: 3),
        Text(
          '说点什么，会有人回应你的。',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: EchoColors.textMuted),
        ),
      ],
    );
  }
}

class _PostCard extends ConsumerWidget {
  const _PostCard({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 点赞头像堆叠：用这条帖子已有评论的人格头像拼出"有人在这里"的感觉
    final likerIds =
        (ref.watch(commentsProvider(post.id)).value ?? const <PostComment>[])
            .take(3)
            .map((comment) => comment.personaId)
            .toList(growable: false);

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
                const UserAvatar(
                  name: AppTexts.defaultNickname,
                  size: 38,
                  showRing: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppTexts.defaultNickname,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: EchoColors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${post.topicName ?? '日常'} · ${RelativeTime.short(post.createdAt)}',
                        style: Theme.of(context).textTheme.labelSmall
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
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: EchoColors.text),
            ),
            if (post.hasImages) ...[
              const SizedBox(height: 10),
              PostImage(ref: post.images.first),
            ],
            const SizedBox(height: 12),
            _PostFooter(post: post, likerIds: likerIds),
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
        children: [
          Icon(Icons.local_fire_department, size: 12, color: EchoColors.hot),
          SizedBox(width: 3),
          Text(
            '热',
            style: TextStyle(
              color: EchoColors.hot,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostFooter extends ConsumerWidget {
  const _PostFooter({required this.post, required this.likerIds});

  final Post post;
  final List<String> likerIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: EchoColors.surface,
                      ),
                      padding: const EdgeInsets.all(1),
                      child: UserAvatar(
                        name: ref.watch(personaNameProvider(likerIds[i])),
                        avatarRef: ref
                            .watch(personaByIdProvider(likerIds[i]))
                            ?.avatar,
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
        Icon(Icons.more_horiz, size: 18, color: EchoColors.textFaint),
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
