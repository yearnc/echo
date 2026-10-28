import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/services/notification_service.dart';
import '../domain/services/resident_wake_service.dart';
import '../domain/services/scheduler_service.dart';

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
    // 住民自己定的闹钟：到点先叫醒它，再处理普通的待办补发。
    await container.read(residentWakeServiceProvider).wakeDueAlarms();
    // 不在后台替固定住民发帖：它自己醒来后决定要不要 create_post。
    // 固定住民的待办也要在后台补上：以前只在前台心跳里唤醒，
    // APP 一划掉，用户发的私信就一直没人接——直到他再打开 APP。
    // 只叫醒真的有待办的人（最多 3 个），避免一轮后台任务跑不完。
    await container
        .read(residentWakeServiceProvider)
        .wakePending(maxResidents: 3);
  } catch (error) {
    // 后台任务失败没有人在场处理，也不该让系统把它标成"崩了"：
    // 这一轮没补上，下一轮（或用户下次打开）还会再补。
    debugPrint('[后台] 这一轮没跑完：$error');
  } finally {
    container.dispose();
  }
}
