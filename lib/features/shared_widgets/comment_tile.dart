import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/media/voice_wave_store.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../../domain/models/post.dart';
import '../../domain/models/post_voice.dart';
import '../../domain/services/voice_playback.dart';
import '../../domain/services/voice_waveform.dart';
import 'user_avatar.dart';

/// 评论底下那颗心。
///
/// 评论的赞跟帖子的赞分开记：帖子一条一颗心，评论有很多条，
/// 而且这里点的可能是住民的评论、也可能是我自己写的。
class _CommentLikeButton extends ConsumerWidget {
  const _CommentLikeButton({required this.commentId, required this.likeCount});

  final String commentId;
  final int likeCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked =
        ref.watch(likedCommentIdsProvider).value?.contains(commentId) ?? false;
    final color = liked ? EchoColors.like : EchoColors.textFaint;

    return GestureDetector(
      onTap: () => ref
          .read(interactionRepositoryProvider)
          .toggleCommentLike(commentId),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(
            liked ? Icons.favorite : Icons.favorite_border,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${liked ? likeCount + 1 : likeCount}',
            style: TextStyle(color: color, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// 一条 AI 评论。帖子详情与演示模式共用同一个组件——
/// 演示模式要让画面和真实评论区长得**一模一样**，共用是最不容易走样的做法。
class CommentTile extends ConsumerWidget {
  const CommentTile({
    super.key,
    required this.comment,
    this.createdAtOverride,
    this.highlighted = false,
    this.isReply = false,
    this.onReply,
    this.voice,
  });

  final PostComment comment;

  /// 说话的人（v3.0）。临时网民不在固定住民表里，由详情页一次查好传进来；
  /// 为空时退回 `personaByIdProvider`（老数据和固定住民）。
  final PostVoice? voice;

  /// 这条是对楼上那条的回复（B7）：缩进一点、左边带一条细线，
  /// 一眼看得出它接的是哪句话。楼层由 [[CommentThreads]] 算好。
  final bool isReply;

  /// 点"回复"时回调。为空时那个按钮不响应（演示模式用不上）。
  final VoidCallback? onReply;

  /// 演示模式里评论的"到达时间"是刚发生的，而不是脚本里写死的时间。
  final DateTime? createdAtOverride;

  /// 长评高亮（第二幕那条千字评论用）。
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // personaId 为空表示这条是我自己说的
    final personaId = comment.personaId;
    final persona = personaId == null || voice != null
        ? null
        : ref.watch(personaByIdProvider(personaId));
    final me = ref.watch(userProfileProvider).value;
    final name = voice?.name ??
        persona?.name ??
        (personaId == null
            ? (me?.displayName ?? AppTexts.defaultNickname)
            : '路过的网友');
    final avatarRef = voice?.avatarAsset ?? persona?.avatar;
    final createdAt = createdAtOverride ?? comment.createdAt;

    // 点开一个人，看他是谁、平常在哪儿、发过什么——
    // 评论区的"活人感"就落在这一步上（自己那句当然点不开）。
    // 临时网民没有主页，点了不跳。
    void openAuthor() {
      if (personaId == null || voice != null) return;
      context.push(RoutePaths.resident(personaId));
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 16, left: isReply ? 14 : 0),
      child: Container(
        padding: EdgeInsets.only(left: isReply ? 10 : 0),
        decoration: isReply
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(color: EchoColors.divider, width: 2),
                ),
              )
            : null,
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
            GestureDetector(
              onTap: openAuthor,
              child: UserAvatar(
                name: name,
                avatarRef: avatarRef,
                size: 34,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: openAuthor,
                        child: Text(
                          name,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: EchoColors.text,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      if (persona != null && voice == null) ...[
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
                  if ((comment.replyToName ?? '').isNotEmpty) ...[
                    Text(
                      '回复 ${comment.replyToName}',
                      style: TextStyle(
                        color: EchoColors.primary,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                  ],
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
                      _CommentLikeButton(
                        commentId: comment.id,
                        likeCount: comment.likeCount,
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        // 演示模式里没有真实的回复动作，但按钮照样在——
                        // 那个模式要的就是"画面和真实评论区一模一样"
                        onTap: onReply,
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          '回复',
                          style: TextStyle(
                            color: EchoColors.textFaint,
                            fontSize: 11,
                          ),
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
      ),
    );
  }
}

/// 语音评论：波形 + 时长 + 转写稿（规划书 §6.6）。
///
/// 阶段 A 那排竖条是画上去的；现在波形、时长都来自真正合成出来的音频，
/// 点一下就能播（B8）。音频已经落在本机，飞行模式下照样能听。
class VoiceBubble extends ConsumerStatefulWidget {
  const VoiceBubble({super.key, required this.comment});

  final PostComment comment;

  @override
  ConsumerState<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends ConsumerState<VoiceBubble> {
  /// 读不出来时的等高柱子：气泡还在，只是看不出起伏。
  static const double _flatBar = 0.3;

  late Future<List<double>> _bars;

  @override
  void initState() {
    super.initState();
    _bars = _loadBars();
  }

  @override
  void didUpdateWidget(covariant VoiceBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment.voiceAsset != widget.comment.voiceAsset) {
      _bars = _loadBars();
    }
  }

  Future<List<double>> _loadBars() {
    final voiceRef = widget.comment.voiceAsset;
    if (voiceRef == null || voiceRef.isEmpty) {
      return Future.value(
        List<double>.filled(VoiceWaveform.defaultBars, _flatBar),
      );
    }
    return ref.read(voiceWaveStoreProvider).load(voiceRef);
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final voiceRef = comment.voiceAsset;
    final playback = ref.watch(voicePlaybackProvider);
    final playing = voiceRef != null && playback.isPlaying(voiceRef);
    final broken = voiceRef != null && playback.hasFailed(voiceRef);
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
          GestureDetector(
            onTap: voiceRef == null
                ? null
                : () =>
                      ref.read(voicePlaybackProvider.notifier).toggle(voiceRef),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 20,
                  color: EchoColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FutureBuilder<List<double>>(
                    future: _bars,
                    builder: (context, snapshot) {
                      final bars = snapshot.data ??
                          List<double>.filled(
                            VoiceWaveform.defaultBars,
                            _flatBar,
                          );
                      return Row(
                        children: [
                          for (final value in bars)
                            Container(
                              width: 2.5,
                              height: 5 + value * 13,
                              margin: const EdgeInsets.only(right: 2.5),
                              decoration: BoxDecoration(
                                color: playing
                                    ? EchoColors.accent
                                    : EchoColors.accent.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$seconds"',
                  style: TextStyle(color: EchoColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (broken) ...[
            const SizedBox(height: 6),
            Text(
              '这段语音没能读出来',
              style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
            ),
          ],
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
            // 合规文案不允许在业务代码里随手写，统一从常量取（规划书 §6.6）。
            AppTexts.aiVoiceNotice,
            style: TextStyle(color: EchoColors.textFaint, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
