import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/app_mode.dart';
import '../../domain/services/mode_switch_service.dart';

/// 走完"检查冷却期 → 二次确认 / 年龄门 → 执行切换"的完整流程。
///
/// 所有想切模式的入口都该走这里，免得某个页面漏掉年龄门或者冷却期。
/// 返回是否真的切了。
Future<bool> runModeSwitch(
  BuildContext context,
  WidgetRef ref,
  AppMode target,
) async {
  final service = ref.read(modeSwitchServiceProvider);

  if (!context.mounted) return false;
  final confirmed = target.isClear
      ? await _confirmToClear(context)
      : await _confirmToEcho(context);
  if (confirmed != true) return false;

  await service.switchTo(target);

  if (!context.mounted) return true;

  // 两种模式的首页不是同一个页面，切完得把人带过去——
  // 否则站在"回响广场"上却被切成了清醒模式，会以为界面坏了。
  // （脚本演出的切换不走这里：第三幕要停在原帖上看客观分析。）
  context.go(target.isClear ? RoutePaths.records : RoutePaths.feed);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(target.isClear ? '已切到清醒模式：虚拟互动已停止并归档' : '已切回响模式：虚拟反馈重新启用'),
    ),
  );
  return true;
}

/// 回响 → 清醒：说清楚会失去什么，再让用户按确认。
Future<bool?> _confirmToClear(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: EchoColors.surface,
      title: Text(
        '切换到清醒模式',
        style: TextStyle(color: EchoColors.text, fontSize: 16),
      ),
      content: Text(
        '${AppTexts.switchToClearBody}\n\n'
        '待发的虚拟互动会停止，已经产生的会归档保留——它们还在，只是不再显示。',
        style: TextStyle(
          color: EchoColors.textMuted,
          fontSize: 13,
          height: 1.7,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('再想想', style: TextStyle(color: EchoColors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('切换', style: TextStyle(color: EchoColors.primary)),
        ),
      ],
    ),
  );
}

/// 清醒 → 回响：二次确认 + 年龄门，缺一不可。
Future<bool?> _confirmToEcho(BuildContext context) {
  var ageConfirmed = false;

  return showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: EchoColors.surface,
        title: Text(
          '切回响模式',
          style: TextStyle(color: EchoColors.text, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppTexts.switchToEchoConfirm,
              style: TextStyle(
                color: EchoColors.textMuted,
                fontSize: 13,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => setState(() => ageConfirmed = !ageConfirmed),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    ageConfirmed
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 18,
                    color: ageConfirmed
                        ? EchoColors.primary
                        : EchoColors.textFaint,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppTexts.switchToEchoAgeGate,
                      style: TextStyle(
                        color: EchoColors.textMuted,
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: TextStyle(color: EchoColors.textMuted)),
          ),
          TextButton(
            onPressed: ageConfirmed
                ? () => Navigator.of(context).pop(true)
                : null,
            child: Text('确认切换', style: TextStyle(color: EchoColors.primary)),
          ),
        ],
      ),
    ),
  );
}
