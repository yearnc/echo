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

// 启动引导（含冷启动补发）见 `lib/data/bootstrap_provider.dart`——
// 放在那里是为了避免 database_provider ↔ scheduler_service 的循环依赖。
