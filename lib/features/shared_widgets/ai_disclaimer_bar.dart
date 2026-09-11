import 'package:flutter/material.dart';

import '../../core/constants/app_texts.dart';
import '../../core/theme/app_colors.dart';

/// 回响模式所有页面底部的固定小字：「内容由AI生成，仅供参考」。
///
/// 合规要求它是"固定"的——不随滚动消失、不随页面变化，所以它应该被
/// 页面骨架（而不是某个列表的尾部）持有。演示模式下也必须显示。
class AiDisclaimerBar extends StatelessWidget {
  const AiDisclaimerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: EchoColors.bg.withValues(alpha: 0.92),
        border: const Border(top: BorderSide(color: EchoColors.divider)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.smart_toy_outlined, size: 12, color: EchoColors.textFaint),
          const SizedBox(width: 6),
          Text(
            AppTexts.aiDisclaimer,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: EchoColors.textFaint,
                  fontSize: 11,
                ),
          ),
        ],
      ),
    );
  }
}
