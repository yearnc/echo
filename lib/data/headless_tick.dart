import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/services/direct_message_service.dart';
import '../domain/services/notification_service.dart';
import '../domain/services/scheduler_service.dart';
import '../domain/services/world_service.dart';

/// 后台补发（B10）。
///
/// 跑在一个**没有界面**的 isolate 里：APP 已经被系统杀掉了，
/// 是系统按周期把这一段 Dart 代码叫醒。所以这里没有 `ref`、没有 widget 树，
/// 只有一套自己建起来的 provider 容器。
///
/// 做的事和冷启动一样，顺序也一样：先兑现到点的互动（那也是要弹通知的
/// 那一步），再让社区自己动一动。差别只有两点：
/// 1. 不播种——首次启动不会发生在后台
/// 2. 补发时**要推系统通知**（`inBackgroundTaskProvider` 打开）：
///    这个时刻用户没在看手机，那正是通知该出场的时候
Future<void> runHeadlessTick() async {
  final container = ProviderContainer(
    overrides: [inBackgroundTaskProvider.overrideWithValue(true)],
  );

  try {
    await container.read(schedulerServiceProvider).flushDue();
    await container.read(worldServiceProvider).tick();
    await container.read(directMessageServiceProvider).tick();
  } catch (error) {
    // 后台任务失败没有人在场处理，也不该让系统把它标成"崩了"：
    // 这一轮没补上，下一轮（或用户下次打开）还会再补。
    debugPrint('[后台] 这一轮没跑完：$error');
  } finally {
    container.dispose();
  }
}
