import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/post_repository.dart';
import '../shared_widgets/user_avatar.dart';

/// 「我的」页：个人资料 + 模式管理入口。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: EchoColors.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const _ProfileHeader(),
          const SizedBox(height: 20),
          const _SectionTitle('设置'),
          _Tile(
            icon: Icons.settings_outlined,
            title: '设置',
            onTap: () => context.push(RoutePaths.settings),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 统计是真查出来的——个人主页上摆四个写死的数字，拍进镜头就露馅了。
    final stats = ref.watch(profileStatsProvider).value;

    return Column(
      children: [
        const UserAvatar(
          name: AppTexts.defaultNickname,
          size: 72,
          showRing: true,
        ),
        const SizedBox(height: 12),
        Text(
          AppTexts.defaultNickname,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: EchoColors.text, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '仅存于这台设备',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: EchoColors.textMuted),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _MiniStat(value: '${stats?.postCount ?? 0}', label: '帖子'),
            _MiniStat(value: '${stats?.likeCount ?? 0}', label: '获赞'),
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
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: EchoColors.text, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
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
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: EchoColors.textFaint),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, this.onTap});

  final IconData icon;
  final String title;
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
                    Text(
                      title,
                      style: TextStyle(color: EchoColors.text, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 18, color: EchoColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
