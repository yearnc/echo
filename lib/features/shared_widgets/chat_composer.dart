import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/media/media_service.dart';
import '../../domain/models/sticker.dart';
import '../../domain/services/asr_service.dart';
import '../../domain/services/voice_recorder.dart';
import 'image_source_sheet.dart';
import 'sticker_picker_sheet.dart';

/// 聊天输入栏（v4.0 改版）。
///
/// 左边只留「语音」和「表情包」；右边平时是一个 `+`，输入框里有了字才变成
/// 发送按钮。点 `+` 才展开「图片 / 语音通话 / 视频通话」——
/// 常用的是说话，不常用的不该一直占着一行。
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    this.onVoiceCall,
    this.onVideoCall,
    this.hint = '说点什么…',
  });

  final TextEditingController controller;
  final bool sending;
  final Future<void> Function({
    String? text,
    StickerItem? sticker,
    String? imageRef,
    String? voiceRef,
    String? transcript,
    int? voiceDurationMs,
  })
  onSend;

  /// 通话入口（P4 接入实时语音/视频）。为空时仍然显示，但只提示。
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;
  final String hint;

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final VoiceRecorder _recorder = VoiceRecorder();
  Timer? _ticker;
  int _seconds = 0;
  bool _recording = false;
  bool _cancelArmed = false;
  bool _transcribing = false;

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (widget.sending || _transcribing) return;
    final ok = await _recorder.start();
    if (!ok) {
      _toast('没有麦克风权限，去系统设置里打开再试');
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _cancelArmed = false;
      _seconds = 0;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
      if (_seconds >= VoiceRecorder.maxDuration.inSeconds) {
        unawaited(_finishRecording());
      }
    });
  }

  Future<void> _finishRecording() async {
    if (!_recording) return;
    _ticker?.cancel();
    final cancel = _cancelArmed;
    final recorded = await _recorder.stop();
    if (mounted) {
      setState(() {
        _recording = false;
        _cancelArmed = false;
      });
    }
    if (cancel || recorded == null) {
      if (!cancel && recorded == null) _toast('按住时间太短了');
      return;
    }

    setState(() => _transcribing = true);
    try {
      // 录音先搬进应用私有目录：缓存文件随时可能被系统清掉。
      final media = ref.read(mediaServiceProvider);
      final target = await media.newVoiceFile();
      await File(recorded.path).copy(target.path);
      final voiceRef = 'file:${target.path}';

      final result = await ref
          .read(asrServiceProvider)
          .transcribeWav(target.path);
      await widget.onSend(
        voiceRef: voiceRef,
        transcript: result.text,
        voiceDurationMs: result.durationMs,
      );
    } catch (error) {
      _toast('没识别出来：$error');
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  Future<void> _cancelRecording() async {
    _ticker?.cancel();
    await _recorder.cancel();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _cancelArmed = false;
      _seconds = 0;
    });
  }

  Future<void> _openPlus() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: EchoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _SheetAction(
              icon: Icons.image_outlined,
              label: '发送图片',
              onTap: () => Navigator.of(sheet).pop('image'),
            ),
            _SheetAction(
              icon: Icons.call_outlined,
              label: '语音通话',
              onTap: () => Navigator.of(sheet).pop('voice_call'),
            ),
            _SheetAction(
              icon: Icons.videocam_outlined,
              label: '视频通话',
              onTap: () => Navigator.of(sheet).pop('video_call'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'image':
        final imageRef = await pickImageWithSource(context, ref);
        if (imageRef != null) await widget.onSend(imageRef: imageRef);
      case 'voice_call':
        if (widget.onVoiceCall != null) {
          widget.onVoiceCall!();
        } else {
          _toast('语音通话在下一版接入');
        }
      case 'video_call':
        if (widget.onVideoCall != null) {
          widget.onVideoCall!();
        } else {
          _toast('视频通话在下一版接入');
        }
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final showStatus = _recording || _transcribing;
    return Container(
      decoration: BoxDecoration(
        color: EchoColors.surface,
        border: Border(top: BorderSide(color: EchoColors.divider, width: 0.8)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showStatus) _RecordStatus(
            recording: _recording,
            seconds: _seconds,
            cancelArmed: _cancelArmed,
            onCancel: _cancelRecording,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _HoldToTalk(
                enabled: !widget.sending && !_transcribing,
                recording: _recording,
                onLongPressStart: _startRecording,
                onLongPressEnd: _finishRecording,
                onMove: (armed) {
                  if (armed != _cancelArmed) {
                    setState(() => _cancelArmed = armed);
                  }
                },
                onTap: () => _toast('按住说话，松开发送'),
              ),
              _RoundIcon(
                icon: Icons.emoji_emotions_outlined,
                tooltip: '表情包',
                onPressed: widget.sending || _recording
                    ? null
                    : () async {
                        final sticker = await showStickerPicker(context, ref);
                        if (sticker == null) return;
                        await widget.onSend(sticker: sticker);
                      },
              ),
              const SizedBox(width: 2),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !_recording && !_transcribing,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    if (!widget.sending) {
                      widget.onSend(text: widget.controller.text);
                    }
                  },
                  style: TextStyle(color: EchoColors.text, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _recording ? '正在录…' : widget.hint,
                    hintStyle: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: EchoColors.bg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 11,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(
                        color: EchoColors.divider,
                        width: 0.7,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(
                        color: EchoColors.primary.withValues(alpha: 0.65),
                        width: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (context, value, _) {
                    final hasText = value.text.trim().isNotEmpty;
                    if (!hasText && !widget.sending) {
                      return _RoundSendButton(
                        key: const ValueKey('plus'),
                        icon: Icons.add,
                        tooltip: '更多',
                        busy: false,
                        onPressed: _recording || _transcribing
                            ? null
                            : _openPlus,
                      );
                    }
                    return _RoundSendButton(
                      key: const ValueKey('send'),
                      icon: Icons.arrow_upward_rounded,
                      tooltip: '发送',
                      busy: widget.sending,
                      onPressed: widget.sending || _recording
                          ? null
                          : () => widget.onSend(text: widget.controller.text),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HoldToTalk extends StatelessWidget {
  const _HoldToTalk({
    required this.enabled,
    required this.recording,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onMove,
    required this.onTap,
  });

  final bool enabled;
  final bool recording;
  final Future<void> Function() onLongPressStart;
  final Future<void> Function() onLongPressEnd;
  final void Function(bool armed) onMove;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '按住说话',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        onLongPressStart: enabled ? (_) => unawaited(onLongPressStart()) : null,
        onLongPressEnd: enabled ? (_) => unawaited(onLongPressEnd()) : null,
        onLongPressMoveUpdate: enabled
            ? (details) => onMove(details.offsetFromOrigin.dy < -50)
            : null,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: recording
                ? EchoColors.primary.withValues(alpha: 0.16)
                : Colors.transparent,
          ),
          child: Icon(
            recording ? Icons.mic : Icons.mic_none,
            color: recording ? EchoColors.primary : EchoColors.textMuted,
            size: 21,
          ),
        ),
      ),
    );
  }
}

class _RecordStatus extends StatelessWidget {
  const _RecordStatus({
    required this.recording,
    required this.seconds,
    required this.cancelArmed,
    required this.onCancel,
  });

  final bool recording;
  final int seconds;
  final bool cancelArmed;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final text = recording
        ? (cancelArmed ? '松手取消' : '正在录音 ${_clock(seconds)} · 松开发送')
        : '正在识别…';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 4, 7),
      child: Row(
        children: [
          Icon(
            recording ? Icons.circle : Icons.graphic_eq,
            size: 9,
            color: recording ? EchoColors.like : EchoColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: cancelArmed ? EchoColors.like : EchoColors.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          if (recording)
            TextButton(
              onPressed: onCancel,
              child: const Text('取消', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  static String _clock(int seconds) {
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: EchoColors.textMuted, size: 21),
      title: Text(
        label,
        style: TextStyle(color: EchoColors.text, fontSize: 14.5),
      ),
      onTap: onTap,
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: EchoColors.textMuted, size: 21),
    );
  }
}

class _RoundSendButton extends StatelessWidget {
  const _RoundSendButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.busy,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    // `+` 是轻量入口：不填满颜色，免得比真正的发送按钮还抢眼。
    final filled = icon == Icons.arrow_upward_rounded;
    return SizedBox(
      width: 40,
      height: 40,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: !filled
              ? Colors.transparent
              : (busy
                    ? EchoColors.primary.withValues(alpha: 0.45)
                    : (enabled
                          ? EchoColors.primary
                          : EchoColors.primary.withValues(alpha: 0.35))),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      icon,
                      color: filled ? Colors.white : EchoColors.textMuted,
                      size: 22,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
