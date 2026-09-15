import 'package:go_router/go_router.dart';

import '../../features/actions/actions_page.dart';
import '../../features/analysis/analysis_page.dart';
import '../../features/composer/compose_page.dart';
import '../../features/feed/feed_page.dart';
import '../../features/models/model_edit_page.dart';
import '../../features/models/models_page.dart';
import '../../features/notifications/notifications_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/post_detail/post_detail_page.dart';
import '../../features/profile/profile_edit_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/records/records_page.dart';
import '../../features/safety/safety_page.dart';
import '../../features/scripts/script_edit_page.dart';
import '../../features/scripts/scripts_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/shell/app_shell.dart';
import '../../features/stickers/stickers_page.dart';
import '../../features/values/values_page.dart';

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

  /// 策划脚本管理。
  static const String scripts = '/scripts';

  /// 模型配置中心。
  static const String models = '/models';

  /// 价值澄清（清醒模式）。
  static const String values = '/values';

  /// 真实行动记录（清醒模式）。
  static const String actions = '/actions';

  /// 心理安全（冷静模式 / 援助入口）。
  static const String safety = '/settings/safety';

  /// 头像与表情包管理。
  static const String stickers = '/settings/stickers';

  /// 编辑我的资料（昵称 / 头像）。
  static const String profileEdit = '/settings/profile';

  static String post(String id) => '/post/$id';

  /// 脚本编辑页。
  static String scriptEdit(String id) => '/scripts/$id';

  /// 模型配置编辑页。
  static String modelEdit(String id) => '/models/$id';

  /// 新建模型配置（草稿，保存后才真正落库）。
  static const String modelNew = '/models/new';
}

/// 路由表。
///
/// 带底部导航的页面放在 [ShellRoute] 里（骨架负责合规小字与永久提示），
/// 沉浸式页面（帖子详情、脚本编辑、引导页）单独成路由，自己挂合规模块。
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
      path: RoutePaths.values,
      builder: (context, state) => const ValuesPage(),
    ),
    GoRoute(
      path: RoutePaths.actions,
      builder: (context, state) => const ActionsPage(),
    ),
    GoRoute(
      path: RoutePaths.safety,
      builder: (context, state) => const SafetyPage(),
    ),
    GoRoute(
      path: RoutePaths.stickers,
      builder: (context, state) => const StickersPage(),
    ),
    GoRoute(
      path: RoutePaths.profileEdit,
      builder: (context, state) => const ProfileEditPage(),
    ),
    GoRoute(
      path: RoutePaths.scripts,
      builder: (context, state) => const ScriptsPage(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              ScriptEditPage(scriptId: state.pathParameters['id'] ?? ''),
        ),
      ],
    ),
    GoRoute(
      path: RoutePaths.models,
      builder: (context, state) => const ModelsPage(),
      routes: [
        // 静态段要排在 :id 前面，否则 "/models/new" 会被当成一个配置 id
        GoRoute(
          path: 'new',
          builder: (context, state) => const ModelEditPage(),
        ),
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              ModelEditPage(configId: state.pathParameters['id']),
        ),
      ],
    ),
  ],
);
