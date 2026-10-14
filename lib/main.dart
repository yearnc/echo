import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/utils/app_session.dart';
import 'domain/services/background_worker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 记下进程启动时间，「使用时长」提示要用（规划书 §13）
  AppSession.markStarted();
  // 注册系统后台补发（B10）。不 await：注册要跟系统服务打交道，
  // 让它拖慢开屏不值得——没注册上也只是退回冷启动补发那三条路。
  unawaited(BackgroundWorker.start());
  runApp(const ProviderScope(child: EchoApp()));
}
