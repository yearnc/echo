import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../data/headless_tick.dart';

/// 系统级后台调度（B10）。
///
/// 在这之前，"补发"只有三条路：冷启动、回前台、以及开着 APP 时的 30 秒心跳。
/// 三条都要求**用户自己回来**。于是有个说不通的场景：帖子发出去、APP 划掉、
/// 两小时后住民来评论了——用户什么都不知道，直到他下次主动打开。
///
/// WorkManager 补的就是这一段：APP 完全关着，系统按周期把它叫醒一次。
///
/// 三条老路一条都不撤——**验收标准是"补得回来"，不是"一定准时"**。
/// Android 的省电策略随时可能把周期任务推迟或合并，把可靠性押在它身上
/// 是不理智的；所以这里只把它当成"多一层机会"，不是唯一的机会。
class BackgroundWorker {
  const BackgroundWorker._();

  /// 周期任务名。同一个名字重复注册会被系统合并（keep 策略）。
  static const String taskName = 'echo.flush';

  /// 15 分钟是 Android WorkManager 划的**最小**周期，不是我们的选择。
  /// 想更勤只能靠前台心跳，那条路本来就有。
  static const Duration frequency = Duration(minutes: 15);

  /// 注册周期任务。失败不抛：注册不上就退回到原来那三条路。
  static Future<void> start() async {
    try {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().registerPeriodicTask(
        taskName,
        taskName,
        frequency: frequency,
        // 补发是纯本地的（排期本来就在磁盘上），不该要求网络——
        // 断网的时候来一条评论，用户照样该收到。
        constraints: Constraints(networkType: NetworkType.notRequired),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (error) {
      debugPrint('[后台] 周期任务没注册上，退回冷启动补发：$error');
    }
  }
}

/// 系统把 APP 叫醒时，从这里进入。
///
/// 必须带上 `vm:entry-point`：后台 isolate 是从这里起跑的，
/// 没有这个注解，编译期优化会把它当成没人调用的代码删掉。
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await runHeadlessTick();
    // 永远返回 true：这一轮有没有东西可补，不是"成功与否"。
    // 返回 false 会让系统按退避策略把任务越推越远，而我们要的是它照常来。
    return true;
  });
}
