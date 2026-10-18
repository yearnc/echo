import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_info.dart';
import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/voice_settings.dart';
import '../../domain/services/appearance_controller.dart';
import '../../domain/services/community_settings_controller.dart';
import '../../domain/services/mode_controller.dart';
import '../../domain/services/model_gateway.dart';
import '../../domain/services/voice_settings_controller.dart';
import '../shared_widgets/mode_switch_flow.dart';

/// 设置页（规划书 §2.3 的目录结构）。
///
/// 只留真实可用的入口，说明压到一行以内：设置页是拿来改东西的，
/// 不是拿来解释产品的。心理援助这类必须被看见的提示不在压缩范围内。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeControllerProvider);
    final appearance = ref.watch(appearanceControllerProvider);
    final community = ref.watch(communitySettingsProvider);
    final voice = ref.watch(voiceSettingsControllerProvider);
    final cloudTts = ref.watch(cloudTtsConfigProvider).value;
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
                subtitle: mode.isEcho ? '停止虚拟互动' : '需要二次确认',
                onTap: () => _toggleMode(context, ref),
              ),
            ],
          ),
          _Group(
            title: '模型与密钥',
            isEcho: isEcho,
            children: [
              _Row(
                isEcho: isEcho,
                icon: Icons.hub_outlined,
                title: '模型配置',
                subtitle: '对话 / 文生图 / 语音合成',
                onTap: () => context.push(RoutePaths.models),
              ),
            ],
          ),
          _Group(
            title: '回响模式',
            isEcho: isEcho,
            children: [
              _SwitchRow(
                isEcho: isEcho,
                icon: Icons.dynamic_feed_outlined,
                title: '固定住民动态',
                subtitle: '关闭后，固定住民不会自己发动态',
                value: community.allowResidentPosts,
                onChanged: (on) => ref
                    .read(communitySettingsProvider.notifier)
                    .setAllowResidentPosts(on),
              ),
              _SwitchRow(
                isEcho: isEcho,
                icon: Icons.visibility_outlined,
                title: '允许网友只读',
                subtitle: '关闭后，每个来的网友都会点赞或评论',
                value: community.allowLurk,
                onChanged: (on) => ref
                    .read(communitySettingsProvider.notifier)
                    .setAllowLurk(on),
              ),
              _Row(
                isEcho: isEcho,
                icon: Icons.forum_outlined,
                title: '网友互相接话',
                subtitle: '每帖 AI 之间的来往上限',
                value: community.aiPeerInteractionLimit == 0
                    ? '关闭'
                    : '${community.aiPeerInteractionLimit} 次',
                onTap: () => _pickPeerLimit(context, ref),
              ),
              _Row(
                isEcho: isEcho,
                icon: Icons.people_outline,
                title: '固定住民',
                subtitle: '自己配置、每帖都会出现的人',
                onTap: () => context.push(RoutePaths.customResidents),
              ),
              _Row(
                isEcho: isEcho,
                icon: Icons.emoji_emotions_outlined,
                title: '头像与表情包',
                onTap: () => context.push(RoutePaths.stickers),
              ),
            ],
          ),
          _Group(
            title: '语音',
            isEcho: isEcho,
            children: [
              _SwitchRow(
                isEcho: isEcho,
                icon: Icons.volume_up_outlined,
                title: '住民语音',
                subtitle: '评论可以带语音条',
                value: voice.enabled,
                onChanged: (on) => ref
                    .read(voiceSettingsControllerProvider.notifier)
                    .setEnabled(on),
              ),
              _Row(
                isEcho: isEcho,
                icon: Icons.graphic_eq,
                title: '语音来源',
                value: cloudTts == null ? '本机' : voice.source.label,
                subtitle: voice.source == VoiceSource.cloud && cloudTts == null
                    ? '云端未配置，暂用本机'
                    : (cloudTts == null ? '配置后可选云端' : null),
                onTap: () => _pickVoiceSource(
                  context,
                  ref,
                  cloudAvailable: cloudTts != null,
                ),
              ),
            ],
          ),
          _Group(
            title: '清醒模式',
            isEcho: isEcho,
            children: [
              _Row(
                isEcho: isEcho,
                icon: Icons.insights_outlined,
                title: '数据看板',
                subtitle: isEcho ? 'AI 制造的动静' : '只统计真实记录',
                onTap: () => context.push(RoutePaths.dashboard),
              ),
              _Row(
                isEcho: isEcho,
                icon: Icons.info_outline,
                title: '常驻提示',
                // 把提示本身写出来：只写"已固定"，用户不知道固定的是什么。
                subtitle: '清醒模式下始终显示：${AppTexts.permanentNotice}',
                value: '不可关闭',
              ),
            ],
          ),
          _Group(
            title: '安全',
            isEcho: isEcho,
            children: [
              _Row(
                isEcho: isEcho,
                icon: Icons.favorite_border,
                title: '心理安全',
                subtitle: '冷静模式与求助',
                onTap: () => context.push(RoutePaths.safety),
              ),
              _Row(
                isEcho: isEcho,
                icon: Icons.escalator_warning_outlined,
                title: '未成年人保护',
                subtitle: '锁定回响模式',
                onTap: () => context.push(RoutePaths.minorProtection),
              ),
            ],
          ),
          _Group(
            title: '其他',
            isEcho: isEcho,
            children: [
              _Row(
                isEcho: isEcho,
                icon: Icons.theater_comedy_outlined,
                title: '策划脚本',
                onTap: () => context.push(RoutePaths.scripts),
              ),
              _Row(
                isEcho: isEcho,
                icon: Icons.code,
                title: '版本',
                value: '$appVersion ($appStageLabel)',
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

  Future<void> _pickPeerLimit(BuildContext context, WidgetRef ref) async {
    final current = ref.read(communitySettingsProvider).aiPeerInteractionLimit;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: currentPalette.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            for (final value in const [0, 1, 2, 3, 5])
              _SourceOption(
                title: value == 0 ? '关闭' : '$value 次',
                subtitle: value == 0 ? '网友只跟帖主说话' : '每帖 AI 之间的来往上限',
                selected: current == value,
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (picked == null) return;
    await ref
        .read(communitySettingsProvider.notifier)
        .setAiPeerInteractionLimit(picked);
  }

  /// 选语音来源。云端没配置时只让选本机，并留一个去配置的入口。
  Future<void> _pickVoiceSource(
    BuildContext context,
    WidgetRef ref, {
    required bool cloudAvailable,
  }) async {
    final current = ref.read(voiceSettingsControllerProvider).source;

    final picked = await showModalBottomSheet<VoiceSource>(
      context: context,
      backgroundColor: currentPalette.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            _SourceOption(
              title: '本机',
              subtitle: '离线合成，随包模型',
              selected: current == VoiceSource.local,
              onTap: () =>
                  Navigator.of(sheetContext).pop(VoiceSource.local),
            ),
            _SourceOption(
              title: '云端',
              subtitle: cloudAvailable ? '使用已配置的 TTS 服务' : '还没有配置 TTS 服务',
              selected: current == VoiceSource.cloud && cloudAvailable,
              onTap: cloudAvailable
                  ? () => Navigator.of(sheetContext).pop(VoiceSource.cloud)
                  : null,
              trailing: cloudAvailable
                  ? null
                  : TextButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        context.push(RoutePaths.models);
                      },
                      child: const Text('去配置', style: TextStyle(fontSize: 12)),
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (picked == null) return;
    await ref
        .read(voiceSettingsControllerProvider.notifier)
        .setSource(picked);
  }
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      enabled: onTap != null,
      title: Text(
        title,
        style: TextStyle(color: currentPalette.text, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: currentPalette.textFaint, fontSize: 11.5),
      ),
      trailing: trailing ??
          (selected
              ? Icon(Icons.check, size: 18, color: currentPalette.primary)
              : null),
      onTap: onTap,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.isEcho,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final bool isEcho;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = isEcho ? EchoColors.text : ClearColors.text;
    final muted = isEcho ? EchoColors.textMuted : ClearColors.textMuted;
    final faint = isEcho ? EchoColors.textFaint : ClearColors.textFaint;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Icon(icon, size: 19, color: muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: text, fontSize: 14)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(color: faint, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: isEcho ? EchoColors.primary : ClearColors.primary,
          ),
        ],
      ),
    );
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
