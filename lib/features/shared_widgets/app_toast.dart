import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 应用内的轻提示（v4.12.3）。
///
/// 以前用 SnackBar：固定在屏幕底部，正压着输入栏和底部导航，录语音、
/// 发表情时很容易被自己挡住。这里改为悬浮在页面顶部（状态栏下方），
/// 自动消失，也可以带一个动作按钮。
///
/// 同一时刻只留一条：新提示会顶掉上一条，避免叠成一列。
OverlayEntry? _entry;
Timer? _timer;

void showAppToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final text = message.trim();
  if (text.isEmpty) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  dismissAppToast();
  final entry = OverlayEntry(
    builder: (_) => _ToastLayer(
      message: text,
      actionLabel: actionLabel,
      onAction: onAction,
      onDismiss: dismissAppToast,
    ),
  );
  _entry = entry;
  overlay.insert(entry);
  _timer = Timer(duration, dismissAppToast);
}

/// 立即收起当前提示（页面退出时也可调用）。
void dismissAppToast() {
  _timer?.cancel();
  _timer = null;
  final entry = _entry;
  _entry = null;
  entry?.remove();
}

class _ToastLayer extends StatelessWidget {
  const _ToastLayer({
    required this.message,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Positioned(
      top: media.padding.top + 10,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * -12),
              child: child,
            ),
          ),
          child: GestureDetector(
            onTap: onDismiss,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
              decoration: BoxDecoration(
                color: EchoColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EchoColors.divider, width: 0.7),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        color: EchoColors.text,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (actionLabel != null && actionLabel!.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        onDismiss();
                        onAction?.call();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        actionLabel!,
                        style: TextStyle(
                          color: EchoColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
