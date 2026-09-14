import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_texts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_session.dart';
import '../../data/repositories/addiction_repository.dart';
import '../../domain/services/mode_controller.dart';
import '../../domain/services/safety_controller.dart';
import '../shared_widgets/mode_switch_flow.dart';

/// 最近 30 分钟查看了几次反馈（防沉迷提醒的依据）。
final recentFeedbackViewsProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(addictionRepositoryProvider).countFeedbackViews(),
);

/// 心理安全页（规划书 §6.9 / §6.10 / §13）。
///
/// 这一页的原则是**只提供信息与开关，不做拦截**：不弹"你不能再用"，
/// 不强制退出，也不把使用时长变成一条需要打败的记录。
/// 工具该做的是让用户看见自己的行为，而不是替用户做决定。
///
/// 配色直接用 [ClearColors]：它与 [EchoColors] 同源（都指向当前调色板），
/// 所以这一页在两种模式下都跟随外观设置。
class SafetyPage extends ConsumerStatefulWidget {
  const SafetyPage({super.key});

  @override
  ConsumerState<SafetyPage> createState() => _SafetyPageState();
}

class _SafetyPageState extends ConsumerState<SafetyPage> {
  @override
  Widget build(BuildContext context) {
    final safety = ref.watch(safetyControllerProvider);
    final mode = ref.watch(modeControllerProvider);
    final recentViews = ref.watch(recentFeedbackViewsProvider).value;

    return Scaffold(
      backgroundColor: ClearColors.bg,
      appBar: AppBar(
        backgroundColor: ClearColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: ClearColors.text),
        title: Text(
          '心理安全',
          style: TextStyle(color: ClearColors.text, fontSize: 16),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const _Intro(),
          const SizedBox(height: 18),
          _Group(
            title: '使用情况',
            children: [
              const _SessionRow(),
              _InfoRow(
                icon: Icons.refresh,
                title: '最近 30 分钟查看反馈',
                value: recentViews == null ? '—' : '$recentViews 次',
                subtitle: '下拉刷新信息流、反复打开同一条帖子，都算一次。',
              ),
            ],
          ),
          _Group(
            title: '保护',
            children: [
              _SwitchRow(
                icon: Icons.hourglass_empty,
                title: '冷静模式',
                subtitle: AppTexts.coolDownReminder,
                value: safety.coolDownMode,
                onChanged: (on) => _toggleCoolDown(on),
              ),
              _SwitchRow(
                icon: Icons.notifications_paused_outlined,
                title: '防沉迷提醒',
                subtitle: '查看反馈次数超过阈值时，温和提醒一次。',
                value: safety.addictionGuard,
                onChanged: (on) =>
                    ref.read(safetyControllerProvider.notifier).setAddictionGuard(on),
              ),
              _ThresholdRow(
                value: safety.feedbackViewThreshold,
                enabled: safety.addictionGuard,
                onChanged: (value) => ref
                    .read(safetyControllerProvider.notifier)
                    .setFeedbackViewThreshold(value),
              ),
            ],
          ),
          _Group(
            title: '求助',
            children: [
              _ActionRow(
                icon: Icons.support_agent,
                title: AppTexts.helpEntry,
                subtitle: '如果情绪持续低落，请找真实的人聊一聊。',
                onTap: () => _showHelp(context),
              ),
            ],
          ),
          if (mode.isEcho) ...[
            const SizedBox(height: 4),
            _ClearShortcut(
              onTap: () => runModeSwitch(context, ref, mode.opposite),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleCoolDown(bool on) async {
    await ref.read(safetyControllerProvider.notifier).setCoolDownMode(on);
    await ref
        .read(addictionRepositoryProvider)
        .logEvent(
          on
              ? AddictionEventType.coolDownOn
              : AddictionEventType.coolDownOff,
        );
  }

  Future<void> _showHelp(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ClearColors.surface,
        title: Text(
          AppTexts.helpEntry,
          style: TextStyle(color: ClearColors.text, fontSize: 15),
        ),
        content: Text(
          AppTexts.helpBody,
          style: TextStyle(
            color: ClearColors.textMuted,
            fontSize: 13,
            height: 1.9,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('知道了', style: TextStyle(color: ClearColors.accent)),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ClearColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ClearColors.divider),
      ),
      child: Text(
        '这一页只做两件事：让你看见自己的使用情况，给你一个随时退出的出口。\n'
        '它不会限制你、不会弹窗拦住你，也不会替你决定该用多久。',
        style: TextStyle(
          color: ClearColors.textMuted,
          fontSize: 13,
          height: 1.8,
        ),
      ),
    );
  }
}

/// 本次已使用时长。每 30 秒自己刷新一次——用户盯着这一页看的时候，
/// 数字不动会显得像坏了。
class _SessionRow extends StatefulWidget {
  const _SessionRow();

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = AppSession.elapsedMinutes;
    final isLong = minutes >= AppSession.longSessionMinutes;

    return _InfoRow(
      icon: Icons.schedule,
      title: '本次已使用',
      value: minutes < 1 ? '不到 1 分钟' : '$minutes 分钟',
      subtitle: isLong
          ? '已经坐了一段时间了，起来动一动吧。'
          : '这个数字只是给你看的。',
      emphasize: isLong,
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

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
                color: ClearColors.textFaint,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: ClearColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ClearColors.divider),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
    this.subtitle,
    this.emphasize = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: ClearColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: ClearColors.text, fontSize: 14)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: emphasize
                          ? ClearColors.accent
                          : ClearColors.textFaint,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: emphasize ? ClearColors.accent : ClearColors.textMuted,
              fontSize: 12.5,
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Icon(icon, size: 19, color: ClearColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: ClearColors.text, fontSize: 14),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: ClearColors.textFaint,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: ClearColors.primary,
          ),
        ],
      ),
    );
  }
}

/// 阈值调节：滑杆 + 当前值。
class _ThresholdRow extends StatelessWidget {
  const _ThresholdRow({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune,
                size: 19,
                color: enabled ? ClearColors.textMuted : ClearColors.textFaint,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '提醒阈值',
                  style: TextStyle(
                    color: enabled ? ClearColors.text : ClearColors.textFaint,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '$value 次',
                style: TextStyle(
                  color: enabled ? ClearColors.primary : ClearColors.textFaint,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: SafetyController.minThreshold.toDouble(),
            max: SafetyController.maxThreshold.toDouble(),
            divisions:
                SafetyController.maxThreshold - SafetyController.minThreshold,
            activeColor: ClearColors.primary,
            inactiveColor: ClearColors.divider,
            label: '$value',
            onChanged: enabled
                ? (raw) => onChanged(raw.round())
                : null,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              '30 分钟内查看反馈达到这个次数，就提醒一次。',
              style: TextStyle(color: ClearColors.textFaint, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 19, color: ClearColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: ClearColors.text, fontSize: 14),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: ClearColors.textFaint,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: ClearColors.textFaint),
          ],
        ),
      ),
    );
  }
}

/// 一键清醒（规划书 §6.10「一键清醒快捷入口」）。
class _ClearShortcut extends StatelessWidget {
  const _ClearShortcut({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ClearColors.surfaceHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.wb_twilight, size: 19, color: ClearColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '现在切到清醒模式',
                      style: TextStyle(
                        color: ClearColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '停掉所有虚拟反馈，并归档已有的评论与点赞。',
                      style: TextStyle(
                        color: ClearColors.textFaint,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward,
                size: 18,
                color: ClearColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
