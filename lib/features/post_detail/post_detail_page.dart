import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_texts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../domain/models/post.dart';
import '../../domain/services/mode_controller.dart';
import '../shared_widgets/comment_tile.dart';
import '../shared_widgets/post_image.dart';
import '../shared_widgets/user_avatar.dart';
import '../shell/app_shell.dart';

/// 帖子详情 + 评论区（规划书 §3.5）。
///
/// 评论区在回响模式里是"逐条延迟出现"的（阶段 B 由调度器驱动），
/// 阶段 A 直接按预置顺序铺开——但每条评论的入场动画保留，
/// 因为那种"一条条冒出来"的节奏正是异化体验的一部分。
class PostDetailPage extends ConsumerWidget {
  const PostDetailPage({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeControllerProvider);
    final postAsync = ref.watch(postByIdProvider(postId));
    final comments =
        ref.watch(commentsProvider(postId)).value ?? const <PostComment>[];

    // 必须是 Scaffold：这个页面不在底部导航骨架里（独立路由），
    // 没有 Material 祖先的话，页面里所有文字都会继承 Flutter 兜底文本样式
    // （app.dart 的 _errorTextStyle，带黄色双下划线），
    // 表现为"点进帖子后到处是横线"。
    return Scaffold(
      backgroundColor: EchoColors.bg,
      body: ComplianceFooter(
        mode: mode,
        child: postAsync.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: EchoColors.primary),
          ),
          error: (error, _) => Center(
            child: Text(
              '帖子加载失败：$error',
              style: TextStyle(color: EchoColors.like, fontSize: 12),
            ),
          ),
          data: (post) => post == null
              ? Center(
                  child: Text(
                    '帖子不存在',
                    style: TextStyle(color: EchoColors.textMuted),
                  ),
                )
              : Column(
                  children: [
                    _TopBar(topicName: post.topicName),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          _PostBody(post: post),
                          const SizedBox(height: 18),
                          _CommentsHeader(count: comments.length),
                          const SizedBox(height: 10),
                          if (mode.isClear)
                            const _ClearModeHint()
                          else if (comments.isEmpty)
                            const _NoCommentsYet()
                          else
                            for (final comment in comments)
                              CommentTile(comment: comment),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// 回响模式下评论不是立刻出现的——0—48 小时内随机到达。
/// 所以空评论区要给一个"还在路上"的说法，而不是"暂无评论"。
class _NoCommentsYet extends StatelessWidget {
  const _NoCommentsYet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(Icons.hourglass_empty, size: 22, color: EchoColors.textFaint),
          SizedBox(height: 10),
          Text(
            '还没有人路过这里。\n反馈会在接下来的 0—48 小时里陆续出现。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: EchoColors.textFaint,
              fontSize: 12,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.topicName});

  final String? topicName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: EchoColors.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back, color: EchoColors.text),
          ),
          Expanded(
            child: Text(
              topicName ?? '帖子',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: EchoColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostBody extends StatelessWidget {
  const _PostBody({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const UserAvatar(
              name: AppTexts.defaultNickname,
              size: 40,
              showRing: true,
            ),
            const SizedBox(width: 10),
            Column(
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
                  RelativeTime.format(post.createdAt),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: EchoColors.textFaint),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          post.content,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: EchoColors.text),
        ),
        if (post.hasImages) ...[
          const SizedBox(height: 12),
          PostImage(ref: post.images.first, height: 240),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.favorite, size: 17, color: EchoColors.like),
            const SizedBox(width: 5),
            Text(
              '${post.likeCount}',
              style: TextStyle(color: EchoColors.like, fontSize: 13),
            ),
            const SizedBox(width: 18),
            Icon(
              Icons.mode_comment_outlined,
              size: 17,
              color: EchoColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              '${post.commentCount}',
              style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}

class _CommentsHeader extends StatelessWidget {
  const _CommentsHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '评论 $count',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(color: EchoColors.text, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Text(
          '按热度',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: EchoColors.textFaint),
        ),
      ],
    );
  }
}

class _ClearModeHint extends StatelessWidget {
  const _ClearModeHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Text(
        '清醒模式下不显示虚拟评论。\n切到「分析」可以看到这条内容的客观分析结果。',
        style: TextStyle(
          color: EchoColors.textMuted,
          height: 1.6,
          fontSize: 13,
        ),
      ),
    );
  }
}
