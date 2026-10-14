import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/app_mode.dart';
import '../../domain/services/mode_controller.dart';
import '../../domain/services/mode_switch_service.dart';
import '../../domain/services/safety_controller.dart';

/// 未成年人保护（规划书 §6.10 / §13，页面清单第 24 项）。
///
/// 规划书里这条要求写得很短——"未成年人默认禁用回响模式"——但它和别的
/// 开关不是一类东西：它是**给监护人的**，不是给用户的。
/// 所以这一页不劝、不解释产品优势，只把两件事说清楚：
/// 回响模式对还在长的人来说为什么不适合，以及这道门管到哪一步。
class MinorProtectionPage extends ConsumerWidget {
  const MinorProtectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safety = ref.watch(safetyControllerProvider);
    final isEcho = ref.watch(modeControllerProvider).isEcho;
    final enabled = safety.minorProtection;

    final bg = isEcho ? EchoColors.bg : ClearColors.bg;
    final surface = isEcho ? EchoColors.surface : ClearColors.surface;
    final divider = isEcho ? EchoColors.divider : ClearColors.divider;
    final fg = isEcho ? EchoColors.text : ClearColors.text;
    final muted = isEcho ? EchoColors.textMuted : ClearColors.textMuted;
    final accent = isEcho ? EchoColors.primary : ClearColors.primary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        iconTheme: IconThemeData(color: fg),
        title: Text(
          '未成年人保护',
          style: TextStyle(color: fg, fontSize: 16),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: divider),
            ),
            child: Text(
              AppTexts.minorWhy,
              style: TextStyle(color: muted, fontSize: 13, height: 1.75),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: enabled ? accent : divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '回响模式',
                        style: TextStyle(color: fg, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        enabled ? '已锁定' : '未锁定',
                        style: TextStyle(
                          color: enabled ? accent : muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  activeThumbColor: accent,
                  onChanged: (value) => value
                      ? _enable(context, ref)
                      : _disable(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            enabled
                ? '这道门开着的时候，切模式、脚本演示、演示模式里的回响入口都进不去。'
                : '开启后，这台设备上的回响模式会被关闭并锁定。',
            style: TextStyle(color: muted, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }

  /// 开锁出门：先确认，再关掉回响模式。
  ///
  /// 顺序很重要——**先锁门，再切模式**。反过来的话，中间有几十毫秒
  /// 门开着而人还在回响模式里。
  Future<void> _enable(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: '开启未成年人保护',
      body: AppTexts.minorTurnOnConfirm,
      isEcho: ref.read(modeControllerProvider).isEcho,
    );
    if (confirmed != true) return;

    await ref.read(safetyControllerProvider.notifier).setMinorProtection(true);
    if (!context.mounted) return;

    if (ref.read(modeControllerProvider).isEcho) {
      await ref.read(modeSwitchServiceProvider).switchTo(AppMode.clear);
      if (!context.mounted) return;
      // 两种模式的首页不是同一个页面，切完得把人带过去，
      // 否则会站在"回响广场"上却已经是清醒模式。
      context.go(RoutePaths.records);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未成年人保护已开启，已切到清醒模式')),
      );
    }
  }

  Future<void> _disable(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: '关闭未成年人保护',
      body: AppTexts.minorTurnOffConfirm,
      isEcho: ref.read(modeControllerProvider).isEcho,
    );
    if (confirmed != true) return;

    await ref.read(safetyControllerProvider.notifier).setMinorProtection(false);
  }

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required bool isEcho,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isEcho ? EchoColors.surface : ClearColors.surface,
        title: Text(
          title,
          style: TextStyle(
            color: isEcho ? EchoColors.text : ClearColors.text,
            fontSize: 16,
          ),
        ),
        content: Text(
          body,
          style: TextStyle(
            color: isEcho ? EchoColors.textMuted : ClearColors.textMuted,
            fontSize: 13,
            height: 1.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '取消',
              style: TextStyle(
                color: isEcho ? EchoColors.textMuted : ClearColors.textMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              '确定',
              style: TextStyle(
                color: isEcho ? EchoColors.primary : ClearColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
