import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/post_repository.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../../domain/services/update_service.dart';
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
          _Tile(
            icon: Icons.help_outline,
            title: '帮助',
            onTap: () => context.push(RoutePaths.help),
          ),
          const _UpdateTile(),
        ],
      ),
    );
  }
}

/// 「检查更新」：查 GitHub 最新 Release，不自动弹窗、不后台轮询。
class _UpdateTile extends ConsumerStatefulWidget {
  const _UpdateTile();

  @override
  ConsumerState<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends ConsumerState<_UpdateTile> {
  bool _busy = false;

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await ref.read(updateServiceProvider).check();
    if (!mounted) return;
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _UpdateDialog(result: result),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: _busy ? null : _check,
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
              Icon(Icons.system_update_outlined, size: 19, color: EchoColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '检查更新',
                  style: TextStyle(color: EchoColors.text, fontSize: 14),
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.chevron_right, size: 18, color: EchoColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.result});

  final UpdateCheckResult result;

  @override
  Widget build(BuildContext context) {
    if (result.failed) {
      return AlertDialog(
        title: const Text('检查更新失败'),
        content: Text(result.error),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      );
    }

    if (!result.hasUpdate) {
      return AlertDialog(
        title: const Text('已经是最新版本'),
        content: Text('当前版本 ${result.currentVersion}。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('好'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text('发现新版本 ${result.latestVersion}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '当前 ${result.currentVersion} → 最新 ${result.latestVersion}',
                style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5),
              ),
              if (result.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '更新说明',
                  style: TextStyle(
                    color: EchoColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  result.notes,
                  style: TextStyle(
                    color: EchoColors.textMuted,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SelectableText(
                result.url,
                style: TextStyle(color: EchoColors.primary, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: result.url));
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('下载链接已复制')));
          },
          child: const Text('复制链接'),
        ),
        FilledButton(
          onPressed: () async {
            final uri = Uri.tryParse(result.url);
            if (uri == null) return;
            try {
              final opened = await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('没有找到能打开链接的应用')),
                );
              }
            } catch (error) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('打不开链接：$error')),
              );
            }
          },
          child: const Text('打开发布页'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 统计是真查出来的——个人主页上摆四个写死的数字，拍进镜头就露馅了。
    final stats = ref.watch(profileStatsProvider).value;
    // 昵称与头像来自 `user_profile` 单行表：改一次，首页、详情页、这里一起变。
    final profile = ref.watch(userProfileProvider).value;
    final nickname = profile?.displayName ?? AppTexts.defaultNickname;

    return Column(
      children: [
        // 点头像或名字就能改资料——不额外摆一个"编辑"按钮，
        // 但旁边留一支小铅笔，让人知道这里点得动
        InkWell(
          onTap: () => context.push(RoutePaths.profileEdit),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: [
                UserAvatar(
                  name: nickname,
                  avatarRef: profile?.avatarOrNull,
                  size: 72,
                  showRing: true,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      nickname,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: EchoColors.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.edit_outlined,
                      size: 15,
                      color: EchoColors.textFaint,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '仅存于这台设备',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: EchoColors.textMuted),
                ),
              ],
            ),
          ),
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
