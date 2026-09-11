import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/services/scheduler_service.dart';
import 'db/database_provider.dart';

/// 启动引导：开库 → 首次播种 → **补发离线期间到点的互动**。
///
/// 第三步是调度器方案的关键：APP 被系统杀掉、手机重启、关机几天，
/// 都不影响排期——因为它们本来就写在磁盘上，回来时扫一遍就补上了。
final appBootstrapProvider = FutureProvider<void>((ref) async {
  await ref.watch(seedServiceProvider).seedIfNeeded();
  await ref.watch(schedulerServiceProvider).flushDue();
});
