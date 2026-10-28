import 'package:go_router/go_router.dart';

import '../../features/actions/actions_page.dart';
import '../../features/analysis/analysis_page.dart';
import '../../features/analysis/clear_album_page.dart';
import '../../features/analysis/reflection_page.dart';
import '../../features/composer/compose_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/feed/feed_page.dart';
import '../../features/help/help_page.dart';
import '../../features/help/tutorial_page.dart';
import '../../features/messages/chat_page.dart';
import '../../features/messages/messages_page.dart';
import '../../features/models/model_edit_page.dart';
import '../../features/models/models_page.dart';
import '../../features/notifications/notifications_page.dart';
import '../../features/messages/call_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/pet/pet_page.dart';
import '../../features/post_detail/post_detail_page.dart';
import '../../features/profile/identity_page.dart';
import '../../features/profile/profile_edit_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/records/records_page.dart';
import '../../features/residents/custom_resident_editor_page.dart';
import '../../features/residents/custom_residents_page.dart';
import '../../features/residents/resident_memories_page.dart';
import '../../features/residents/resident_wake_log_page.dart';
import '../../features/safety/minor_page.dart';
import '../../features/safety/safety_page.dart';
import '../../features/scripts/script_edit_page.dart';
import '../../features/scripts/scripts_page.dart';
import '../../features/search/search_page.dart';
import '../../features/settings/backup_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/shell/app_shell.dart';
import '../../features/stickers/stickers_page.dart';
import '../../features/topics/topics_page.dart';
import '../../features/trending/trending_page.dart';
import '../../features/values/values_page.dart';

/// 路由路径常量。通知点击跳转、深链都从这里取，避免散落的字符串。
class RoutePaths {
  const RoutePaths._();

  static const String onboarding = '/onboarding';
  static const String feed = '/feed';
  static const String records = '/records';
  static const String compose = '/compose';
  static const String notifications = '/notifications';

  /// 私信会话列表（B5）。
  static const String messages = '/messages';

  /// 今天的热榜（B6）。
  static const String trending = '/trending';

  /// 关注与粉丝（B5）。
  static const String follows = '/follows';

  /// 话题列表（B6）。
  static const String topics = '/topics';

  /// 搜索（B6）。
  static const String search = '/search';

  /// 某个话题下的帖子。
  static String topic(String name) => '/topics/${Uri.encodeComponent(name)}';
  static const String profile = '/profile';
  static const String analysis = '/analysis';
  static const String settings = '/settings';

  /// 用户自己配置的固定住民。
  static const String customResidents = '/custom-residents';
  static const String customResidentEdit = '/custom-residents/edit';

  /// 某个固定住民的长期记忆。
  static String residentMemories(String residentId) =>
      '/custom-residents/memories/$residentId';

  /// 某位固定住民的唤醒日志。
  static String residentWakeLog(String residentId) =>
      '/custom-residents/logs/$residentId';

  /// 策划脚本管理。
  static const String scripts = '/scripts';

  /// 模型配置中心。
  static const String models = '/models';

  /// 价值澄清（清醒模式）。
  /// 数据看板（B9）。两种模式共用这一个入口，页面内容按模式分开。
  static const String dashboard = '/dashboard';

  static const String values = '/values';

  /// 真实行动记录（清醒模式）。
  static const String actions = '/actions';

  /// 数字关系反思（线上投入 vs 线下行动）。
  static const String reflection = '/analysis/reflection';

  /// 真实生活相册。
  static const String album = '/analysis/album';

  /// 心理安全（冷静模式 / 援助入口）。
  static const String safety = '/settings/safety';

  /// 未成年人保护（B11）：一道独立于模式切换的长期锁。
  static const String minorProtection = '/settings/minor';

  /// 头像与表情包管理。
  static const String stickers = '/settings/stickers';

  /// 全量数据备份与恢复。
  static const String backup = '/settings/backup';

  /// 桌宠设置（v4.0）。
  static const String pet = '/pet';

  /// 编辑我的资料（昵称 / 头像）。
  static const String profileEdit = '/settings/profile';

  /// 我的身份（性别 / 职业 / 城市等，作为 AI 前缀）。
  static const String identity = '/settings/identity';

  /// 帮助与常见问题。
  static const String help = '/help';

  /// 新手教程。
  static const String tutorial = '/tutorial';

  static String post(String id) => '/post/$id';

  /// 脚本编辑页。
  static String scriptEdit(String id) => '/scripts/$id';

  /// 模型配置编辑页。
  static String modelEdit(String id) => '/models/$id';

  /// 新建模型配置（草稿，保存后才真正落库）。
  static const String modelNew = '/models/new';

  /// AI 住民的个人主页。
  static String resident(String personaId) => '/resident/$personaId';

  /// 和某一位住民的私信会话。
  static String chat(String personaId) => '/chat/$personaId';

  /// 私信内通话（v4.0）。
  static String call(String personaId, {bool video = false}) =>
      '/call/$personaId${video ? '?video=1' : ''}';
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
          path: RoutePaths.messages,
          builder: (context, state) => const MessagesPage(),
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
      path: RoutePaths.customResidents,
      builder: (context, state) => const CustomResidentsPage(),
    ),
    GoRoute(
      path: RoutePaths.customResidentEdit,
      builder: (context, state) => CustomResidentEditorPage(
        residentId: state.uri.queryParameters['residentId'],
      ),
    ),
    GoRoute(
      path: '/custom-residents/memories/:id',
      builder: (context, state) => ResidentMemoriesPage(
        residentId: state.pathParameters['id'] ?? '',
      ),
    ),
    GoRoute(
      path: '/custom-residents/logs/:id',
      builder: (context, state) => ResidentWakeLogPage(
        residentId: state.pathParameters['id'] ?? '',
      ),
    ),
    // 私信会话是沉浸式的：进去之后只有你们两个人，不挂底部导航
    GoRoute(
      path: '/chat/:id',
      builder: (context, state) =>
          ChatPage(personaId: state.pathParameters['id'] ?? ''),
    ),
    GoRoute(
      path: RoutePaths.search,
      builder: (context, state) => const SearchPage(),
    ),
    GoRoute(
      path: RoutePaths.topics,
      builder: (context, state) => const TopicsPage(),
      routes: [
        GoRoute(
          path: ':name',
          builder: (context, state) =>
              TopicDetailPage(topic: state.pathParameters['name'] ?? ''),
        ),
      ],
    ),
    GoRoute(
      path: RoutePaths.trending,
      builder: (context, state) => const TrendingPage(),
    ),
    GoRoute(
      path: RoutePaths.dashboard,
      builder: (context, state) => const DashboardPage(),
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
      path: RoutePaths.reflection,
      builder: (context, state) => const ReflectionPage(),
    ),
    GoRoute(
      path: RoutePaths.album,
      builder: (context, state) => const ClearAlbumPage(),
    ),
    GoRoute(
      path: RoutePaths.safety,
      builder: (context, state) => const SafetyPage(),
    ),
    GoRoute(
      path: RoutePaths.minorProtection,
      builder: (context, state) => const MinorProtectionPage(),
    ),
    GoRoute(
      path: RoutePaths.stickers,
      builder: (context, state) => const StickersPage(),
    ),
    GoRoute(
      path: RoutePaths.backup,
      builder: (context, state) => const BackupPage(),
    ),
    GoRoute(
      path: RoutePaths.profileEdit,
      builder: (context, state) => const ProfileEditPage(),
    ),
    GoRoute(
      path: RoutePaths.identity,
      builder: (context, state) => const IdentityPage(),
    ),
    GoRoute(
      path: RoutePaths.pet,
      builder: (context, state) => const PetPage(),
    ),
    GoRoute(
      path: '/call/:id',
      builder: (context, state) => CallPage(
        personaId: state.pathParameters['id'] ?? '',
        video: state.uri.queryParameters['video'] == '1',
      ),
    ),
    GoRoute(
      path: RoutePaths.help,
      builder: (context, state) => const HelpPage(),
    ),
    GoRoute(
      path: RoutePaths.tutorial,
      builder: (context, state) => const TutorialPage(),
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
