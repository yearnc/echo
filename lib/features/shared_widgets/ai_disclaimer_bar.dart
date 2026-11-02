import 'package:flutter/material.dart';

import '../../core/constants/app_texts.dart';
import '../../core/theme/app_colors.dart';

/// 回响模式所有页面底部的固定小字：「内容由AI生成，仅供参考」。
///
/// 合规要求它是"固定"的——不随滚动消失、不随页面变化，所以它应该被
/// 页面骨架（而不是某个列表的尾部）持有。演示模式下也必须显示。
class AiDisclaimerBar extends StatelessWidget {
  const AiDisclaimerBar({super.key, this.dark = false});

  /// 狼人杀这类深色沉浸页面用自己的底色；其余页面走 EchoColors。
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final background = dark ? const Color(0xF004060C) : EchoColors.bg;
    final border = dark ? const Color(0x22FFFFFF) : EchoColors.divider;
    final text = dark ? const Color(0xFFA8A090) : EchoColors.textFaint;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.smart_toy_outlined, size: 12, color: text),
          const SizedBox(width: 6),
          Text(
            AppTexts.aiDisclaimer,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: text, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
