import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/app_mode.dart';
import '../../domain/services/mode_controller.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';
import '../shared_widgets/permanent_notice_banner.dart';

/// 页面骨架：底部导航 + 模式相关的合规模块。
///
/// 合规模块挂在这一层而不是各页面里，是为了保证它"固定"——
/// 无论用户切到哪个 tab、列表滚到哪，小字和永久提示都必须在。
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  /// 回响模式导航（阶段 A）：消息/私信属于阶段 B，先不放进来。
  static const List<_NavItem> _echoTabs = [
    _NavItem('/feed', Icons.auto_awesome_outlined, Icons.auto_awesome, '首页'),
    _NavItem('/compose', Icons.add_box_outlined, Icons.add_box, '发布'),
    _NavItem('/notifications', Icons.notifications_none, Icons.notifications, '通知'),
    _NavItem('/profile', Icons.person_outline, Icons.person, '我的'),
  ];

  /// 清醒模式导航：记录、发布、分析、设置。
  static const List<_NavItem> _clearTabs = [
    _NavItem('/records', Icons.edit_note_outlined, Icons.edit_note, '记录'),
    _NavItem('/compose', Icons.add_box_outlined, Icons.add_box, '发布'),
    _NavItem('/analysis', Icons.insights_outlined, Icons.insights, '分析'),
    _NavItem('/settings', Icons.settings_outlined, Icons.settings, '设置'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeControllerProvider);
    final tabs = mode.isEcho ? _echoTabs : _clearTabs;
    final location = GoRouterState.of(context).uri.path;

    var index = tabs.indexWhere((tab) => location.startsWith(tab.path));
    if (index < 0) index = 0;

    return Scaffold(
      body: Column(
        children: [
          // 清醒模式的永久提示必须在最上方且不可关闭
          if (mode.isClear) const PermanentNoticeBanner(),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        tabs: tabs,
        currentIndex: index,
        mode: mode,
        onTap: (path) => context.go(path),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.path, this.icon, this.activeIcon, this.label);

  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.tabs,
    required this.currentIndex,
    required this.mode,
    required this.onTap,
  });

  final List<_NavItem> tabs;
  final int currentIndex;
  final AppMode mode;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final isEcho = mode.isEcho;
    final background = isEcho ? EchoColors.surface : ClearColors.surface;
    final divider = isEcho ? EchoColors.divider : ClearColors.divider;
    final active = isEcho ? EchoColors.primary : ClearColors.primary;
    final inactive = isEcho ? EchoColors.textFaint : ClearColors.textFaint;

    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: _TabButton(
                    item: tabs[i],
                    selected: i == currentIndex,
                    active: active,
                    inactive: inactive,
                    onTap: () => onTap(tabs[i].path),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.active,
    required this.inactive,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final Color active;
  final Color inactive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? active : inactive;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? item.activeIcon : item.icon, size: 22, color: color),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// 阶段 A 的合规小字挂载点，供独立页面（帖子详情、演示模式）复用。
class ComplianceFooter extends StatelessWidget {
  const ComplianceFooter({super.key, required this.mode, required this.child});

  final AppMode mode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (mode.isClear) const PermanentNoticeBanner(),
        Expanded(child: child),
        if (mode.isEcho) const AiDisclaimerBar(),
      ],
    );
  }
}
