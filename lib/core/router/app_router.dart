import 'package:go_router/go_router.dart';

import '../../features/analysis/analysis_page.dart';
import '../../features/composer/compose_page.dart';
import '../../features/demo/demo_page.dart';
import '../../features/feed/feed_page.dart';
import '../../features/notifications/notifications_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/post_detail/post_detail_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/records/records_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/shell/app_shell.dart';

/// 路由路径常量。通知点击跳转、深链都从这里取，避免散落的字符串。
class RoutePaths {
  const RoutePaths._();

  static const String onboarding = '/onboarding';
  static const String feed = '/feed';
  static const String records = '/records';
  static const String compose = '/compose';
  static const String notifications = '/notifications';
  static const String profile = '/profile';
  static const String analysis = '/analysis';
  static const String settings = '/settings';
  static const String demo = '/demo';

  static String post(String id) => '/post/$id';
}

/// 阶段 A 路由表。
///
/// 带底部导航的页面放在 [ShellRoute] 里（骨架负责合规小字与永久提示），
/// 沉浸式页面（帖子详情、演示模式、引导页）单独成路由，自己挂合规模块。
final appRouter = GoRouter(
  initialLocation: RoutePaths.feed,
  routes: [
    GoRoute(
      path: RoutePaths.onboarding,
      builder: (context, state) => const OnboardingPage(),
    ),
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: RoutePaths.feed,
          builder: (context, state) => const FeedPage(),
        ),
        GoRoute(
          path: RoutePaths.records,
          builder: (context, state) => const RecordsPage(),
        ),
        GoRoute(
          path: RoutePaths.compose,
          builder: (context, state) => const ComposePage(),
        ),
        GoRoute(
          path: RoutePaths.notifications,
          builder: (context, state) => const NotificationsPage(),
        ),
        GoRoute(
          path: RoutePaths.profile,
          builder: (context, state) => const ProfilePage(),
        ),
        GoRoute(
          path: RoutePaths.analysis,
          builder: (context, state) => const AnalysisPage(),
        ),
        GoRoute(
          path: RoutePaths.settings,
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    ),
    GoRoute(
      path: '/post/:id',
      builder: (context, state) =>
          PostDetailPage(postId: state.pathParameters['id'] ?? ''),
    ),
    GoRoute(
      path: RoutePaths.demo,
      builder: (context, state) => const DemoPage(),
    ),
  ],
);
