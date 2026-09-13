import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/services/appearance_controller.dart';
import '../../domain/services/mode_controller.dart';
import '../shared_widgets/mode_switch_flow.dart';

/// 设置页（规划书 §2.3 的目录结构）。
///
/// 阶段 A 先把结构立起来：模式管理可用，其余入口按规划书的层级摆好，
/// 点进去是"即将实现"的说明——让结构先成型，比把功能散着做更可控。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeControllerProvider);
    final appearance = ref.watch(appearanceControllerProvider);
    final isEcho = mode.isEcho;

    // 从「我的」push 进来时（有上级页面）才需要返回键与标题栏；
    // 清醒模式下设置是底部导航的一个 tab，那时不该出现返回键。
    final canPop = context.canPop();
    final bg = isEcho ? EchoColors.bg : ClearColors.bg;
    final surface = isEcho ? EchoColors.surface : ClearColors.surface;
    final fg = isEcho ? EchoColors.text : ClearColors.text;

    return Scaffold(
      backgroundColor: bg,
      appBar: canPop
          ? AppBar(
              backgroundColor: surface,
              elevation: 0,
              iconTheme: IconThemeData(color: fg),
              title: Text('设置', style: TextStyle(color: fg, fontSize: 16)),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (!canPop)
            Text(
              '设置',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: fg, fontSize: 24),
            ),
          const SizedBox(height: 16),
          _Group(
            title: '外观',
            isEcho: isEcho,
            children: [
              _Row(
                isEcho: isEcho,
                icon: Icons.brightness_6_outlined,
                title: '明暗',
                subtitle: '默认跟随模式：回响深色、清醒暖白',
                value: appearance.label,
                onTap: () => _pickAppearance(context, ref),
              ),
            ],
          ),
          _Group(
            title: '模式管理',
            isEcho: isEcho,
            children: [
              _Row(
                isEcho: isEcho,
                icon: Icons.swap_horiz,
                title: '当前模式',
                value: mode.label,
              ),
              _Row(
                isEcho: isEcho,
                icon: mode.isEcho
                    ? Icons.nightlight_outlined
                    : Icons.wb_sunny_outlined,
                title: mode.isEcho ? '切到清醒模式' : '切到回响模式',
                subtitle: mode.isEcho ? '停止虚拟互动，归档 AI 内容' : '需二次确认与年龄确认',
                onTap: () => _toggleMode(context, ref),
              ),
              _Row(
                isEcho: isEcho,
                icon: Icons.inventory_2_outlined,
                title: '虚拟反馈数据',
                value: '归档',
                onTap: () => _soon(context, '数据归档与永久删除'),
              ),
            ],
          ),
          _Group(
            title: '模型配置',
            isEcho: isEcho,
            children: [
              _Row(
                isEcho: isEcho,
                icon: Icons.hub_outlined,
                title: '模型配置中心',
                subtitle: '地址、模型名与密钥，支持测试连接',
                onTap: () => context.push(RoutePaths.models),
              ),
            ],
          ),
          _Group(
            title: '回响模式',
            isEcho: isEcho,
            children: [
              _Row(
                isEcho: isEcho,
                icon: Icons.people_alt_outlined,
                title: 'AI 人格管理',
                value: '24 位',
                onTap: () => _soon(context, '人格管理'),
              ),
              _Row(
                isEcho: isEcho,
                icon: Icons.emoji_emotions_outlined,
                title: '头像与表情包',
                subtitle: '支持导入自己的图片',
                onTap: () => _soon(context, '素材管理'),
              ),
              _Row(
                isEcho: isEcho,
                icon: Icons.volume_up_outlined,
                title: '语音与音色',
                onTap: () => _soon(context, '语音设置'),
              ),
            ],
          ),
          _Group(
            title: '清醒模式',
            isEcho: isEcho,
            children: [
              _Row(
                isEcho: isEcho,
                icon: Icons.tune,
                title: '客观分析维度',
                value: '5 项',
                onTap: () => _soon(context, '分析维度设置'),
              ),
              _Row(
                isEcho: isEcho,
                icon: Icons.info_outline,
                title: '永久提示',
                value: '已固定',
                subtitle: AppTexts.permanentNotice,
              ),
            ],
          ),
          _Group(
            title: '安全与合规',
            isEcho: isEcho,
            children: [
              _Row(
                isEcho: isEcho,
                icon: Icons.favorite_border,
                title: '心理安全',
                subtitle: '冷静模式 / 反馈查看阈值',
                onTap: () => _soon(context, '心理安全设置'),
              ),
              _Row(
                isEcho: isEcho,
                icon: Icons.escalator_warning_outlined,
                title: '未成年人保护',
                subtitle: '默认禁止回响模式',
                onTap: () => _soon(context, '未成年人保护'),
              ),
              _Row(
                isEcho: isEcho,
                icon: Icons.privacy_tip_outlined,
                title: '隐私与数据',
                subtitle: '导出 / 一键清除本地数据',
                onTap: () => _soon(context, '隐私与数据'),
              ),
            ],
          ),
          _Group(
            title: '开发',
            isEcho: isEcho,
            children: [
              _Row(
                isEcho: isEcho,
                icon: Icons.theater_comedy_outlined,
                title: '策划脚本',
                subtitle: '管理可保留的互动脚本',
                onTap: () => context.push(RoutePaths.scripts),
              ),
              _Row(
                isEcho: isEcho,
                icon: Icons.code,
                title: '版本',
                value: '0.1.0 (M1)',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              isEcho ? AppTexts.aiDisclaimer : AppTexts.permanentNotice,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isEcho ? EchoColors.textFaint : ClearColors.textFaint,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMode(BuildContext context, WidgetRef ref) async {
    final current = ref.read(modeControllerProvider);
    // 二次确认、年龄门、冷却期都在这个流程里
    await runModeSwitch(context, ref, current.opposite);
  }

  Future<void> _pickAppearance(BuildContext context, WidgetRef ref) async {
    final current = ref.read(appearanceControllerProvider);

    final picked = await showModalBottomSheet<AppearanceMode>(
      context: context,
      backgroundColor: currentPalette.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            for (final option in AppearanceMode.values)
              ListTile(
                dense: true,
                title: Text(
                  option.label,
                  style: TextStyle(color: currentPalette.text, fontSize: 14),
                ),
                subtitle: Text(
                  switch (option) {
                    AppearanceMode.auto => '回响模式深色，清醒模式暖白',
                    AppearanceMode.light => '两种模式都用暖白',
                    AppearanceMode.dark => '两种模式都用深色',
                  },
                  style: TextStyle(
                    color: currentPalette.textFaint,
                    fontSize: 11.5,
                  ),
                ),
                trailing: option == current
                    ? Icon(Icons.check, size: 18, color: currentPalette.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(option),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (picked == null) return;
    await ref.read(appearanceControllerProvider.notifier).setMode(picked);
  }

  void _soon(BuildContext context, String name) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$name：待实现')));
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.children,
    required this.isEcho,
  });

  final String title;
  final List<Widget> children;
  final bool isEcho;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                color: isEcho ? EchoColors.textFaint : ClearColors.textFaint,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: isEcho ? EchoColors.surface : ClearColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isEcho ? EchoColors.divider : ClearColors.divider,
              ),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.isEcho,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
  });

  final bool isEcho;
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = isEcho ? EchoColors.text : ClearColors.text;
    final muted = isEcho ? EchoColors.textMuted : ClearColors.textMuted;
    final faint = isEcho ? EchoColors.textFaint : ClearColors.textFaint;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 19, color: muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: text, fontSize: 14)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: faint,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null)
              Text(value!, style: TextStyle(color: faint, fontSize: 12)),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 18, color: faint),
            ],
          ],
        ),
      ),
    );
  }
}
