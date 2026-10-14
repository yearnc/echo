import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 系统通知（B10）。
///
/// 应用内那张通知列表从阶段 A 就在了，但它只在用户自己打开 APP 时才看得见——
/// 而"有人回应我"这件事，最有价值的时刻恰恰是用户没在看手机的时候。
///
/// 两条自觉的约束：
/// 1. **锁屏上不露内容**。公共场合手机亮起来，"老陈的键盘 评论了你的帖子"
///    不该被旁边的人读到；要看的细节，解锁进 APP 再看。
/// 2. **它只是提醒，不是召唤**。这一层不重复、不催促、不堆叠——
///    通知文案保持社区的口吻，不携带"AI"前缀（规划书 §3.11）。
class SystemNotificationService {
  SystemNotificationService();

  static const String channelId = 'echo_interactions';
  static const String channelName = '社区互动';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  /// 初始化：建渠道、要权限。
  ///
  /// 权限被拒绝不是错误——用户可以永远不授权，APP 照常跑，
  /// 只是提醒留在应用内。所以这里整段兜住，失败就当没有系统通知。
  Future<void> ensureReady() async {
    if (_ready) return;
    _ready = true;

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          // 目前只做"点开 APP"这一件事：深链到具体帖子要等路由参数
          // 能携带通知 payload 再说，做一半的跳转比不跳更让人困惑。
          debugPrint('[通知] 用户点了通知：${response.payload}');
        },
      );

      // Android 13 起通知要运行时授权，不申请的话通知会被静默丢掉。
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (error) {
      debugPrint('[通知] 系统通知起不来，提醒只留在应用内：$error');
    }
  }

  /// 弹一条。失败不抛——通知发不出去不该影响互动本身。
  Future<void> show({
    required String key,
    required String title,
    String body = '',
  }) async {
    await ensureReady();
    try {
      await _plugin.show(
        id: _idOf(key),
        title: title,
        body: body,
        notificationDetails: _details(),
        payload: key,
      );
    } catch (error) {
      debugPrint('[通知] 这条没弹出来：$error');
    }
  }

  /// 同一条互动重复弹会覆盖上一条（id 由来源派生），
  /// 不会出现"补发一次刷屏十条"。
  static int _idOf(String key) => key.hashCode & 0x7fffffff;

  NotificationDetails _details() => const NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: '住民的点赞、评论与私信提醒',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      // 锁屏上只显示"你有一条社区互动通知"，内容等解锁再看（规划书 §B10）。
      visibility: NotificationVisibility.secret,
    ),
    iOS: DarwinNotificationDetails(),
  );
}

final systemNotificationProvider = Provider<SystemNotificationService>(
  (ref) => SystemNotificationService(),
);

/// 当前这次运行是不是"后台补发"（B10）。
///
/// 默认 false（用户就在 APP 里）；后台任务那个容器会把它 override 成 true。
/// 它只回答一个问题：**这次补发要不要推到通知栏**。
/// 用户正看着屏幕的时候还弹通知，那是打扰，不是提醒。
final inBackgroundTaskProvider = Provider<bool>((ref) => false);
