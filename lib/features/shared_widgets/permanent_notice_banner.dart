import 'package:flutter/material.dart';

import '../../core/constants/app_texts.dart';
import '../../core/theme/app_colors.dart';

/// 清醒模式的永久提示（规划书 §2.4.1）。
///
/// 刻意做成「不可关闭」的样子：没有关闭按钮，也没有点击消失——
/// 界面本身就不给用户"消掉它"的可能，这样代码层面也不需要留删除入口。
class PermanentNoticeBanner extends StatelessWidget {
  const PermanentNoticeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: ClearColors.surfaceHigh,
        border: Border(
          left: BorderSide(color: ClearColors.accent, width: 3),
          bottom: BorderSide(color: ClearColors.divider),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline, size: 15, color: ClearColors.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppTexts.permanentNotice,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClearColors.text,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
