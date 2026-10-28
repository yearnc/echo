import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/message_time.dart';
import '../../domain/services/voice_playback.dart';
import 'post_image.dart';
import 'user_avatar.dart';

/// 一条聊天消息。
///
/// 聊天气泡。**同一个气泡只有这一份实现**——改一次样式只改一处。
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.content,
    required this.mediaType,
    required this.fromMe,
    required this.senderName,
    required this.createdAt,
    this.avatarRef,
    this.caption = '',
    this.voicePath = '',
    this.transcript = '',
    this.showAvatar = true,
    this.showName = false,
    this.showTime = true,
  });

  final String content;

  /// text / image / sticker / voice
  final String mediaType;

  /// 图片描述 / 表情包语义。只给住民看，聊天界面不铺出来。
  final String caption;

  /// 语音条的文件引用与转写稿。
  final String voicePath;
  final String transcript;
  final bool fromMe;
  final String senderName;
  final DateTime createdAt;
  final String? avatarRef;

  /// 连续同一个人说话时，只有第一条带头像，后面缩进对齐。
  final bool showAvatar;

  /// 是否显示发送者名字。私信里 AppBar 已经写着名字，默认不显示。
  final bool showName;
  final bool showTime;

  static const double _avatarSize = 34;

  @override
  Widget build(BuildContext context) {
    // 通话记录不套气泡：微信也只在会话中间写一行“通话 03:12”。
    if (mediaType == 'call') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.call_outlined,
                size: 12,
                color: EchoColors.textFaint,
              ),
              const SizedBox(width: 5),
              Text(
                content,
                style: TextStyle(
                  color: EchoColors.textFaint,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final media = mediaType == 'image' || mediaType == 'sticker';
    final isImage = mediaType == 'image';

    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: showAvatar ? 8 : 2,
        bottom: 2,
      ),
      child: Row(
        mainAxisAlignment: fromMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!fromMe)
            showAvatar
                ? UserAvatar(
                    name: senderName,
                    avatarRef: avatarRef,
                    size: _avatarSize,
                  )
                : const SizedBox(width: _avatarSize),
          if (!fromMe) const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: fromMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (showName && !fromMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Text(
                      senderName,
                      style: TextStyle(
                        color: EchoColors.textFaint,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                _body(context, media: media, isImage: isImage),
                if (showTime)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                    child: Text(
                      formatMessageTime(createdAt),
                      style: TextStyle(
                        color: EchoColors.textFaint.withValues(alpha: 0.85),
                        fontSize: 9.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context, {
    required bool media,
    required bool isImage,
  }) {
    if (mediaType == 'voice') {
      return _VoiceChip(voicePath: voicePath, transcript: transcript);
    }
    if (media) {
      // 图片和表情包不套气泡——套上像给图加了个相框。
      final width = isImage ? 196.0 : 112.0;
      return GestureDetector(
        onTap: isImage
            ? () => _preview(context)
            : null,
        child: SizedBox(
          width: width,
          height: isImage ? 208 : 112,
          child: Hero(
            tag: 'chat-image-$content-${createdAt.millisecondsSinceEpoch}',
            child: PostImage(
              ref: content,
              height: isImage ? 208 : 112,
              borderRadius: 14,
            ),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: fromMe ? null : EchoColors.surface,
        gradient: fromMe
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  EchoColors.primary,
                  Color.lerp(EchoColors.primary, EchoColors.accent, 0.35) ??
                      EchoColors.primary,
                ],
              )
            : null,
        border: fromMe
            ? null
            : Border.all(color: EchoColors.divider, width: 0.8),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(fromMe ? 16 : 5),
          bottomRight: Radius.circular(fromMe ? 5 : 16),
        ),
        boxShadow: fromMe
            ? [
                BoxShadow(
                  color: EchoColors.primary.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Text(
        content,
        style: TextStyle(
          color: fromMe ? Colors.white : EchoColors.text,
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );
  }

  void _preview(BuildContext context) {
    final tag = 'chat-image-$content-${createdAt.millisecondsSinceEpoch}';
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.of(dialogContext).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: Hero(
                tag: tag,
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: PostImage(ref: content, height: 520),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 聊天里的日期分隔：“今天 / 昨天 / 10月20日”。
class ChatDayDivider extends StatelessWidget {
  const ChatDayDivider({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: EchoColors.surfaceHigh.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            dayLabel(day),
            style: TextStyle(color: EchoColors.textFaint, fontSize: 10.5),
          ),
        ),
      ),
    );
  }

  static String dayLabel(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff < 7) return '${at.month}月${at.day}日';
    if (at.year == now.year) return '${at.month}月${at.day}日';
    return '${at.year}年${at.month}月${at.day}日';
  }

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// 一条语音私信：点一下播，下面留转写稿。
///
/// 住民合成失败的语音不会走到这里——失败时那条消息保持纯文字。
class _VoiceChip extends ConsumerWidget {
  const _VoiceChip({required this.voicePath, required this.transcript});

  final String voicePath;
  final String transcript;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(voicePlaybackProvider);
    final playing = voicePath.isNotEmpty && playback.isPlaying(voicePath);
    final broken = voicePath.isNotEmpty && playback.hasFailed(voicePath);
    final text = transcript.trim();

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        border: Border.all(color: EchoColors.divider, width: 0.8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: voicePath.isEmpty
                ? null
                : () => ref
                      .read(voicePlaybackProvider.notifier)
                      .toggle(voicePath),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 19,
                  color: EchoColors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  '语音',
                  style: TextStyle(
                    color: EchoColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (broken) ...[
            const SizedBox(height: 4),
            Text(
              '这段语音没能读出来',
              style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
            ),
          ],
          if (text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '“$text”',
              style: TextStyle(
                color: EchoColors.textMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
