import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';

/// 启动引导页（规划书 §5.2 第 1~2 项：引导 + 模式选择）。
///
/// 这里要把两件事说清楚，而且不能含糊：
/// 1. 你即将进入的是一个 **AI 生成的社区**；
/// 2. 你可以随时切到清醒模式，并且那时所有 AI 内容会被归档。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _selected = 0;
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EchoColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text(
                '回响',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: EchoColors.text,
                  fontSize: 40,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Echo · 回响广场',
                style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              Text(
                '这里有一个永远热情的社区。\n它会认真看你发的每一条，然后回应你。',
                style: TextStyle(
                  color: EchoColors.textMuted,
                  fontSize: 13.5,
                  height: 1.8,
                ),
              ),
              const SizedBox(height: 26),
              _ModeOption(
                title: '回响模式',
                subtitle: 'AI 住民的点赞、评论与私信，0—48 小时内随机出现',
                badge: '体验异化',
                selected: _selected == 0,
                onTap: () => setState(() => _selected = 0),
              ),
              const SizedBox(height: 10),
              _ModeOption(
                title: '清醒模式',
                subtitle: '关闭所有虚拟反馈，只保留客观分析与真实记录',
                badge: '价值重建',
                selected: _selected == 1,
                onTap: () => setState(() => _selected = 1),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => setState(() => _agreed = !_agreed),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _agreed,
                        onChanged: (v) => setState(() => _agreed = v ?? false),
                        side: BorderSide(color: EchoColors.textFaint),
                        activeColor: EchoColors.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppTexts.switchToEchoAgeGate,
                        style: TextStyle(
                          color: EchoColors.textMuted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _agreed ? () => context.go(RoutePaths.feed) : null,
                  child: const Text('进入'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  AppTexts.aiDisclaimer,
                  style: TextStyle(color: EchoColors.textFaint, fontSize: 10.5),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: selected
              ? EchoColors.primary.withValues(alpha: 0.12)
              : EchoColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? EchoColors.primary.withValues(alpha: 0.65)
                : EchoColors.divider,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: EchoColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: EchoColors.overlay,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: EchoColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: EchoColors.textMuted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 19,
              color: selected ? EchoColors.primary : EchoColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}
