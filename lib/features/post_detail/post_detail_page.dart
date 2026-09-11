import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_texts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../domain/models/post.dart';
import '../../domain/services/mode_controller.dart';
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

    return Container(
      color: EchoColors.bg,
      child: ComplianceFooter(
        mode: mode,
        child: postAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: EchoColors.primary),
          ),
          error: (error, _) => Center(
            child: Text('帖子加载失败：$error',
                style: const TextStyle(color: EchoColors.like, fontSize: 12)),
          ),
          data: (post) => post == null
              ? const Center(
                  child: Text('帖子不存在',
                      style: TextStyle(color: EchoColors.textMuted)),
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
                              _CommentTile(comment: comment),
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
        children: const [
          Icon(Icons.hourglass_empty, size: 22, color: EchoColors.textFaint),
          SizedBox(height: 10),
          Text(
            '还没有人路过这里。\n反馈会在接下来的 0—48 小时里陆续出现。',
            textAlign: TextAlign.center,
            style: TextStyle(color: EchoColors.textFaint, fontSize: 12, height: 1.7),
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
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: EchoColors.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: EchoColors.text),
          ),
          Expanded(
            child: Text(
              topicName ?? '帖子',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: EchoColors.text, fontWeight: FontWeight.w600),
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
            const UserAvatar(name: AppTexts.defaultNickname, size: 40, showRing: true),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppTexts.defaultNickname,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: EchoColors.text,
                          fontWeight: FontWeight.w600,
                        )),
                const SizedBox(height: 2),
                Text(RelativeTime.format(post.createdAt),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: EchoColors.textFaint)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(post.content,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: EchoColors.text)),
        if (post.hasImages) ...[
          const SizedBox(height: 12),
          PostImage(ref: post.images.first, height: 240),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(Icons.favorite, size: 17, color: EchoColors.like),
            const SizedBox(width: 5),
            Text('${post.likeCount}',
                style: const TextStyle(color: EchoColors.like, fontSize: 13)),
            const SizedBox(width: 18),
            const Icon(Icons.mode_comment_outlined,
                size: 17, color: EchoColors.textMuted),
            const SizedBox(width: 5),
            Text('${post.commentCount}',
                style: const TextStyle(color: EchoColors.textMuted, fontSize: 13)),
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
        Text('评论 $count',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: EchoColors.text,
                  fontWeight: FontWeight.w600,
                )),
        const Spacer(),
        Text('按热度',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: EchoColors.textFaint)),
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
      child: const Text(
        '清醒模式下不显示虚拟评论。\n切到「分析」可以看到这条内容的客观分析结果。',
        style: TextStyle(color: EchoColors.textMuted, height: 1.6, fontSize: 13),
      ),
    );
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({required this.comment});

  final PostComment comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persona = ref.watch(personaByIdProvider(comment.personaId));
    final name = persona?.name ?? '社区住民';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(name: name, avatarRef: persona?.avatar, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: EchoColors.text,
                              fontWeight: FontWeight.w600,
                            )),
                    if (persona != null) ...[
                      const SizedBox(width: 6),
                      Text('Lv.${persona.level}',
                          style: const TextStyle(
                              color: EchoColors.textFaint, fontSize: 10)),
                    ],
                    const Spacer(),
                    Text(RelativeTime.short(comment.createdAt),
                        style: const TextStyle(
                            color: EchoColors.textFaint, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 5),
                if (comment.isVoice)
                  _VoiceBubble(comment: comment)
                else
                  Text(comment.content ?? '',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: EchoColors.text)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.favorite_border,
                        size: 13, color: EchoColors.textFaint),
                    const SizedBox(width: 4),
                    Text('${comment.likeCount}',
                        style: const TextStyle(
                            color: EchoColors.textFaint, fontSize: 11)),
                    const SizedBox(width: 14),
                    const Text('回复',
                        style: TextStyle(
                            color: EchoColors.textFaint, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 语音评论：波形 + 时长 + 转写稿（规划书 §6.6）。
/// 阶段 A 播放预置音频，真实 TTS 在阶段 B。
class _VoiceBubble extends StatelessWidget {
  const _VoiceBubble({required this.comment});

  final PostComment comment;

  @override
  Widget build(BuildContext context) {
    final seconds = ((comment.voiceDurationMs ?? 0) / 1000).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: EchoColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.play_arrow_rounded,
                  size: 20, color: EchoColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 22; i++)
                      Container(
                        width: 2.5,
                        height: 6 + (i % 5) * 3.0,
                        margin: const EdgeInsets.only(right: 2.5),
                        decoration: BoxDecoration(
                          color: EchoColors.accent.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('$seconds"',
                  style: const TextStyle(
                      color: EchoColors.textMuted, fontSize: 11)),
            ],
          ),
          if (comment.transcript != null) ...[
            const SizedBox(height: 8),
            Text('“${comment.transcript}”',
                style: const TextStyle(
                    color: EchoColors.textMuted, fontSize: 12, height: 1.5)),
          ],
          const SizedBox(height: 6),
          const Text('AI 生成语音',
              style: TextStyle(color: EchoColors.textFaint, fontSize: 10)),
        ],
      ),
    );
  }
}
