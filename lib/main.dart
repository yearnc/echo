import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/utils/app_session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 记下进程启动时间，「使用时长」提示要用（规划书 §13）
  AppSession.markStarted();
  // 系统后台补发（B10）不在这里注册——见 `EchoApp`：等本地库打开完
  // 再交给 WorkManager，避免冷启动时后台 isolate 和前台抢同一把库锁。
  runApp(const ProviderScope(child: EchoApp()));
}
