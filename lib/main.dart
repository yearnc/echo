import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/utils/app_session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 记下进程启动时间，「使用时长」提示要用（规划书 §13）
  AppSession.markStarted();
  runApp(const ProviderScope(child: EchoApp()));
}
