import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/services/mode_controller.dart';
import '../shared_widgets/user_avatar.dart';

/// 「我的」页：个人资料 + 模式管理入口。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeControllerProvider);

    return Container(
      color: EchoColors.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const _ProfileHeader(),
          const SizedBox(height: 18),
          _ModeCard(
            title: mode.label,
            subtitle: mode.tagline,
            onTap: mode.isEcho
                ? () {
                    ref.read(modeControllerProvider.notifier).toClear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已切到清醒模式：虚拟互动已停用')),
                    );
                  }
                : () => context.go(RoutePaths.settings),
            actionLabel: mode.isEcho ? '切到清醒模式' : '管理模式',
          ),
          const SizedBox(height: 18),
          const _SectionTitle('内容'),
          const _Tile(icon: Icons.grid_view_outlined, title: '我的帖子', trailing: '2'),
          const _Tile(icon: Icons.bookmark_border, title: '我的收藏', trailing: '0'),
          const _Tile(icon: Icons.workspace_premium_outlined, title: '勋章墙', trailing: '3'),
          const SizedBox(height: 18),
          const _SectionTitle('设置'),
          _Tile(
            icon: Icons.settings_outlined,
            title: '设置',
            onTap: () => context.go(RoutePaths.settings),
          ),
          _Tile(
            icon: Icons.science_outlined,
            title: '演示模式',
            subtitle: '微视频三幕一键触发',
            onTap: () => context.push(RoutePaths.demo),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const UserAvatar(name: AppTexts.defaultNickname, size: 72, showRing: true),
        const SizedBox(height: 12),
        Text(AppTexts.defaultNickname,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: EchoColors.text,
                  fontWeight: FontWeight.w700,
                )),
        const SizedBox(height: 4),
        Text('回响大学 · 东区 · Lv.3',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: EchoColors.textMuted)),
        const SizedBox(height: 14),
        Row(
          children: const [
            _MiniStat(value: '2', label: '帖子'),
            _MiniStat(value: '284', label: '获赞'),
            _MiniStat(value: '2', label: '粉丝'),
            _MiniStat(value: '7', label: '连续签到'),
          ],
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: EchoColors.text,
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: EchoColors.textFaint, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.actionLabel,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2150), Color(0xFF181530)],
        ),
        border: Border.all(color: EchoColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz, size: 17, color: EchoColors.primary),
              const SizedBox(width: 7),
              Text('当前模式',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: EchoColors.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: EchoColors.text,
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(color: EchoColors.textMuted, fontSize: 12.5)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: EchoColors.primary,
                side: BorderSide(color: EchoColors.primary.withValues(alpha: 0.6)),
              ),
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: EchoColors.textFaint)),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: EchoColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: EchoColors.divider),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: EchoColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: EchoColors.text, fontSize: 14)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: const TextStyle(
                              color: EchoColors.textFaint, fontSize: 11.5)),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                Text(trailing!,
                    style: const TextStyle(
                        color: EchoColors.textFaint, fontSize: 12)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 18, color: EchoColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
