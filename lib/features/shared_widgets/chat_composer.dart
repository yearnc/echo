import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/sticker.dart';
import 'image_source_sheet.dart';
import 'sticker_picker_sheet.dart';

/// 聊天输入栏。
///
/// 图片入口统一走 [pickImageWithSource]：拍照或相册，两个地方行为一致；
/// 表情包走全项目同一个选择器，不在各页面重复实现。
class ChatComposer extends ConsumerWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    this.hint = '说点什么…',
  });

  final TextEditingController controller;
  final bool sending;
  final Future<void> Function({
    String? text,
    StickerItem? sticker,
    String? imageRef,
  })
  onSend;
  final String hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: EchoColors.surface,
        border: Border(top: BorderSide(color: EchoColors.divider, width: 0.8)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _RoundIcon(
            icon: Icons.image_outlined,
            tooltip: '图片',
            onPressed: sending
                ? null
                : () async {
                    final imageRef = await pickImageWithSource(context, ref);
                    if (imageRef == null) return;
                    await onSend(imageRef: imageRef);
                  },
          ),
          _RoundIcon(
            icon: Icons.emoji_emotions_outlined,
            tooltip: '表情包',
            onPressed: sending
                ? null
                : () async {
                    final sticker = await showStickerPicker(context, ref);
                    if (sticker == null) return;
                    await onSend(sticker: sticker);
                  },
          ),
          const SizedBox(width: 2),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (!sending) onSend(text: controller.text);
              },
              style: TextStyle(color: EchoColors.text, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: TextStyle(color: EchoColors.textFaint, fontSize: 14),
                filled: true,
                fillColor: EchoColors.bg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 11,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: EchoColors.divider, width: 0.7),
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
            child: _SendButton(
              sending: sending,
              onPressed: () => onSend(text: controller.text),
            ),
          ),
        ],
      ),
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

class _SendButton extends StatelessWidget {
  const _SendButton({required this.sending, required this.onPressed});

  final bool sending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: sending
            ? EchoColors.primary.withValues(alpha: 0.45)
            : EchoColors.primary,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: sending ? null : onPressed,
          customBorder: const CircleBorder(),
          child: Center(
            child: sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.arrow_upward_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
          ),
        ),
      ),
    );
  }
}
