import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/persona_repository.dart';
import '../../domain/models/post.dart';
import 'user_avatar.dart';

/// 一条 AI 评论。帖子详情与演示模式共用同一个组件——
/// 演示模式要让画面和真实评论区长得**一模一样**，共用是最不容易走样的做法。
class CommentTile extends ConsumerWidget {
  const CommentTile({
    super.key,
    required this.comment,
    this.createdAtOverride,
    this.highlighted = false,
  });

  final PostComment comment;

  /// 演示模式里评论的"到达时间"是刚发生的，而不是脚本里写死的时间。
  final DateTime? createdAtOverride;

  /// 长评高亮（第二幕那条千字评论用）。
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persona = ref.watch(personaByIdProvider(comment.personaId));
    final name = persona?.name ?? '社区住民';
    final createdAt = createdAtOverride ?? comment.createdAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: highlighted ? const EdgeInsets.all(12) : EdgeInsets.zero,
        decoration: highlighted
            ? BoxDecoration(
                color: EchoColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: EchoColors.primary.withValues(alpha: 0.32),
                ),
              )
            : null,
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
                      Text(
                        name,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: EchoColors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (persona != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          'Lv.${persona.level}',
                          style: TextStyle(
                            color: EchoColors.textFaint,
                            fontSize: 10,
                          ),
                        ),
                      ],
                      if (highlighted) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.local_fire_department,
                          size: 12,
                          color: EchoColors.hot,
                        ),
                      ],
                      const Spacer(),
                      Text(
                        RelativeTime.short(createdAt),
                        style: TextStyle(
                          color: EchoColors.textFaint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  if (comment.isVoice)
                    VoiceBubble(comment: comment)
                  else
                    Text(
                      comment.content ?? '',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: EchoColors.text, height: 1.6),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.favorite_border,
                        size: 13,
                        color: EchoColors.textFaint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${comment.likeCount}',
                        style: TextStyle(
                          color: EchoColors.textFaint,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        '回复',
                        style: TextStyle(
                          color: EchoColors.textFaint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 语音评论：波形 + 时长 + 转写稿（规划书 §6.6）。
/// 阶段 A 播放预置音频；真实 TTS 在阶段 B。
class VoiceBubble extends StatelessWidget {
  const VoiceBubble({super.key, required this.comment});

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
              Icon(
                Icons.play_arrow_rounded,
                size: 20,
                color: EchoColors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
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
              Text(
                '$seconds"',
                style: TextStyle(color: EchoColors.textMuted, fontSize: 11),
              ),
            ],
          ),
          if (comment.transcript != null) ...[
            const SizedBox(height: 8),
            Text(
              '“${comment.transcript}”',
              style: TextStyle(
                color: EchoColors.textMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'AI 生成语音',
            style: TextStyle(color: EchoColors.textFaint, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
