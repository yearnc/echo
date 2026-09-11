import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'seed_service.dart';

/// 数据库单例。整个 APP 只开一个连接，退出时随 ProviderScope 一起释放。
final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final seedServiceProvider = Provider<SeedService>(
  (ref) => SeedService(ref.watch(databaseProvider)),
);

/// 启动引导：开库 + 首次播种。
///
/// 放在 Provider 里而不是 `main()` 里，是为了让"正在准备"这件事
/// 有一个可被 UI 观察的状态——首屏可以据此显示启动页，
/// 出错时也能给出可读的提示，而不是白屏。
final appBootstrapProvider = FutureProvider<void>((ref) async {
  await ref.watch(seedServiceProvider).seedIfNeeded();
});
