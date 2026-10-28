import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/services/voice_playback.dart';

/// “来自 XX 的语音”（v4.0）。
///
/// 帖子/评论的正文始终是转写后的文字；这个小标只回答两件事：
/// 这句话是**说**出来的，以及是谁说的。有原始音频时点它就能听。
class SpokenBadge extends ConsumerWidget {
  const SpokenBadge({
    super.key,
    required this.label,
    this.voicePath = '',
    this.durationMs,
  });

  final String label;
  final String voicePath;
  final int? durationMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(voicePlaybackProvider);
    final hasAudio = voicePath.isNotEmpty;
    final playing = hasAudio && playback.isPlaying(voicePath);
    final failed = hasAudio && playback.hasFailed(voicePath);
    final color = failed ? EchoColors.like : EchoColors.textMuted;

    return InkWell(
      onTap: hasAudio
          ? () => ref.read(voicePlaybackProvider.notifier).toggle(voicePath)
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: EchoColors.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasAudio
                  ? (playing ? Icons.stop_circle_outlined : Icons.play_circle_outline)
                  : Icons.mic_none,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              failed ? '音频播不出来' : label,
              style: TextStyle(color: color, fontSize: 11),
            ),
            if (durationMs != null && durationMs! > 0) ...[
              const SizedBox(width: 4),
              Text(
                '${(durationMs! / 1000).round()}″',
                style: TextStyle(color: EchoColors.textFaint, fontSize: 10.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 把 `speechBy` 翻成人话。`me` 是用户自己，其余是住民 id。
String spokenLabel(String speechBy, {String? residentName}) {
  if (speechBy.trim().isEmpty) return '';
  if (speechBy == 'me') return '来自我的语音';
  final name = (residentName ?? '').trim();
  return name.isEmpty ? '来自一条语音' : '来自 $name 的语音';
}
