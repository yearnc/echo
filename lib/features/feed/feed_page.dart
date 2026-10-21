import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/relationship_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../data/repositories/post_voice_repository.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../../domain/models/post.dart';
import '../../domain/models/post_voice.dart';
import '../shared_widgets/like_button.dart';
import '../shared_widgets/post_image_grid.dart';
import '../shared_widgets/user_avatar.dart';

/// 回响模式首页：信息流（规划书 §3.4）。
///
/// 视觉上刻意做成"热闹"的：等级、经验条、勋章、热度标签、点赞头像堆叠——
/// 这些元素本身就是要让用户感到被看见。它们不是装饰，是这个产品的主题。
/// 信息流的两栏（B6）。
///
/// 只有两栏：**推荐**是全部，**关注**是你关注的那些人。
/// 热榜和话题不是"栏"——它们是另外两个去处（点标题旁边那两个图标），
/// 把不同性质的东西塞进同一排标签里，用户会以为它们是同一类筛选。
enum FeedTab { recommend, following }

class FeedTabController extends Notifier<FeedTab> {
  @override
  FeedTab build() => FeedTab.recommend;

  void select(FeedTab tab) => state = tab;
}

final feedTabProvider = NotifierProvider<FeedTabController, FeedTab>(
  FeedTabController.new,
);

class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 首屏只取最近 10 条，底部“加载更多”再加 10 条。
    final limit = ref.watch(feedLimitProvider);
    final posts = ref.watch(feedPagePostsProvider(limit));
    final tab = ref.watch(feedTabProvider);
    final following = ref.watch(followingProvider);

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
        data: (list) {
          // 关注那一栏：只看你关注的人（自己的帖子也在，不然刚发完切过来
          // 会觉得"我发的东西呢"）
          final visible = switch (tab) {
            FeedTab.recommend => list,
            FeedTab.following => [
              for (final post in list)
                if (post.authorPersonaId == null ||
                    following.contains(post.authorPersonaId))
                  post,
            ],
          };

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const _PlazaHeader(),
              const SizedBox(height: 12),
              const _FeedTabs(),
              const SizedBox(height: 14),
              if (visible.isEmpty)
                _EmptyFeed(
                  message: tab == FeedTab.following
                      ? '你关注的人还没发什么。去别人的主页点个关注试试。'
                      : null,
                )
              else
                for (final post in visible) ...[
                  _PostCard(post: post),
                  const SizedBox(height: 14),
                ],
              if (list.length >= limit)
                Center(
                  child: TextButton(
                    onPressed: () =>
                        ref.read(feedLimitProvider.notifier).more(),
                    child: const Text('加载更多'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({this.message});

  /// 关注栏空着时的说法和"社区还空着"不是一回事，所以让调用方给。
  final String? message;

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
            message ?? AppTexts.emptyFeed,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
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
          ),
        ),
        // 搜索（B6 收尾）：找一个人、一句话
        IconButton(
          onPressed: () => context.push(RoutePaths.search),
          tooltip: '搜索',
          icon: Icon(
            Icons.search,
            color: EchoColors.textMuted,
            size: 21,
          ),
        ),
        // 话题入口（B6 收尾）：社区里正在聊什么
        IconButton(
          onPressed: () => context.push(RoutePaths.topics),
          tooltip: '话题',
          icon: Icon(
            Icons.tag,
            color: EchoColors.textMuted,
            size: 21,
          ),
        ),
        // 热榜入口（B6）：今天大家都在看什么
        IconButton(
          onPressed: () => context.push(RoutePaths.trending),
          tooltip: '今天的热榜',
          icon: Icon(
            Icons.local_fire_department_outlined,
            color: EchoColors.hot,
            size: 23,
          ),
        ),
      ],
    );
  }
}

/// 推荐 / 关注两栏。
class _FeedTabs extends ConsumerWidget {
  const _FeedTabs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(feedTabProvider);

    return Row(
      children: [
        for (final tab in FeedTab.values) ...[
          _FeedTabChip(
            label: tab == FeedTab.recommend ? '推荐' : '关注',
            selected: tab == current,
            onTap: () => ref.read(feedTabProvider.notifier).select(tab),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _FeedTabChip extends StatelessWidget {
  const _FeedTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? EchoColors.primary.withValues(alpha: 0.14)
              : EchoColors.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? EchoColors.primaryDim : EchoColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? EchoColors.primary : EchoColors.textMuted,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
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
            // 我自己说的话没有住民身份，堆叠头像里也没有它的位置
            .map((comment) => comment.personaId)
            .whereType<String>()
            .toList(growable: false);
    // 谁发的：固定住民 / 旧住民显示本人，用户自己发的才显示"我"。
    // 三种动态躺在同一张表里，靠两个作者列区分。
    final resident = post.authorResidentId == null
        ? null
        : ref.watch(customResidentByIdProvider(post.authorResidentId!));
    final author = post.authorPersonaId == null
        ? null
        : ref.watch(personaByIdProvider(post.authorPersonaId!));
    final me = ref.watch(userProfileProvider).value;
    final name = resident?.name ??
        author?.name ??
        me?.displayName ??
        AppTexts.defaultNickname;
    final avatarRef =
        resident?.avatarAsset ?? author?.avatar ?? me?.avatarOrNull;
    // 旧住民的头像和名字可以点开——那是"这个账号背后有个人"的入口；
    // 固定住民还没有公开主页，点开不跳。
    final openAuthor = author == null
        ? null
        : () => context.push(RoutePaths.resident(author.id));

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
                GestureDetector(
                  onTap: openAuthor,
                  child: UserAvatar(
                    name: name,
                    avatarRef: avatarRef,
                    size: 38,
                    showRing: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: openAuthor,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
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
              PostImageGrid(images: post.images),
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
    // 评论者可能是临时网民：他们不在 ai_personas 里，查名字会回落成
    // “社区住民”，头像就变成一个“社”字。这里优先读这一帖的
    // post_voices 快照，查不到的人才跳过，不拿兜底名硬画。
    final voices =
        ref.watch(postVoicesProvider(post.id)).value ??
        const <PostVoice>[];
    final voiceById = {for (final voice in voices) voice.id: voice};
    final avatars = <({String name, String? avatarRef})>[];
    for (final id in likerIds) {
      final voice = voiceById[id];
      if (voice != null) {
        avatars.add((
          name: voice.name,
          avatarRef: voice.avatarAsset.trim().isEmpty
              ? null
              : voice.avatarAsset,
        ));
        continue;
      }
      final persona = ref.watch(personaByIdProvider(id));
      if (persona != null) {
        avatars.add((name: persona.name, avatarRef: persona.avatar));
      }
    }

    return Row(
      children: [
        if (avatars.isNotEmpty) ...[
          SizedBox(
            width: 22.0 + (avatars.length - 1) * 15,
            height: 22,
            child: Stack(
              children: [
                for (var i = 0; i < avatars.length; i++)
                  Positioned(
                    left: i * 15.0,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: EchoColors.surface,
                      ),
                      padding: const EdgeInsets.all(1),
                      child: UserAvatar(
                        name: avatars[i].name,
                        avatarRef: avatars[i].avatarRef,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        LikeButton(post: post),
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
