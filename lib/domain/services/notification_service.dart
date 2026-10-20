import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

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

  /// 预约一条**将来**的通知。
  ///
  /// 这是"APP 关着也能收到"的正路：排期本来就写在数据库里，我们在排期时
  /// 顺手把它交给系统的 AlarmManager，时间到了由系统亮屏提醒，
  /// 不依赖 WorkManager（后者在国产 ROM 上随时会被掐掉）。
  ///
  /// 用 `inexactAllowWhileIdle`：不需要"精确闹钟"权限，允许系统把时间
  /// 挪几分钟——社区互动的提醒不需要秒级精确，能到就行。
  Future<void> schedule({
    required String key,
    required DateTime at,
    required String title,
    String body = '',
  }) async {
    // 已经过去的时间点没有预约的意义，交给 flushDue 当场兑现。
    if (!at.isAfter(DateTime.now())) return;

    await ensureReady();
    try {
      await _plugin.zonedSchedule(
        id: _scheduledIdOf(key),
        // 用 UTC 表示绝对时刻：不依赖设备时区名，也不用额外装时区插件
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        payload: key,
      );
    } catch (error) {
      debugPrint('[通知] 这条没预约上：$error');
    }
  }

  /// 取消一条还没到点的预约（互动提前被兑现、或切到清醒模式时）。
  Future<void> cancelScheduled(String key) async {
    try {
      await _plugin.cancel(id: _scheduledIdOf(key));
    } catch (error) {
      debugPrint('[通知] 这条预约没取消掉：$error');
    }
  }

  /// 把通知栏里已经弹出来的提醒收掉。
  ///
  /// 用户既然已经打开 APP 看到了消息，状态栏里那条"有人回应你"就完成了
  /// 它的使命；一直挂着反而像没读过。只清"已经展示的"，
  /// 没到点的预约由 [cancelAllScheduled] 单独管。
  Future<void> cancelAllShown() async {
    try {
      await _plugin.cancelAll();
    } catch (error) {
      debugPrint('[通知] 通知栏没清干净：$error');
    }
  }

  /// 取消所有已预约、还没弹出的通知。
  ///
  /// 只动"排着的"，已经弹出来的历史通知不动——切模式不该顺手把
  /// 通知栏清空，那是另一件事。
  Future<void> cancelAllScheduled() async {
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (error) {
      debugPrint('[通知] 预约没清干净：$error');
    }
  }

  /// 同一条互动重复弹会覆盖上一条（id 由来源派生），
  /// 不会出现"补发一次刷屏十条"。
  static int _idOf(String key) => key.hashCode & 0x7fffffff;

  /// 预约用的 id 单独一档：和"已经弹出来的那条"分开，
  /// 这样兑现时取消预约不会把通知栏里刚出现的那条一起抹掉。
  static int _scheduledIdOf(String key) =>
      'scheduled:$key'.hashCode & 0x7fffffff;

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
