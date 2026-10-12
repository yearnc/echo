import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/services/direct_message_service.dart';
import '../domain/services/scheduler_service.dart';
import '../domain/services/world_service.dart';
import 'db/database_provider.dart';

/// 启动引导：开库 → 首次播种 → **补发离线期间到点的互动** → 给社区添上
/// 这段离线时间里发生过的事。
///
/// 第三步是调度器方案的关键：APP 被系统杀掉、手机重启、关机几天，
/// 都不影响排期——因为它们本来就写在磁盘上，回来时扫一遍就补上了。
///
/// 第四步是它的人文版本：用户不在的时候，社区也该有自己的动静。
/// 少了它，隔几天回来看到的信息流永远停在离开那一刻。
final appBootstrapProvider = FutureProvider<void>((ref) async {
  await ref.watch(seedServiceProvider).seedIfNeeded();
  await ref.watch(schedulerServiceProvider).flushDue();
  await ref.watch(worldServiceProvider).tick();
  // 私信排在最后：它要读刚更新的关系（谁到了互关、谁该来敲你的门），
  // 也要看有没有你说了话、他还欠着一句的会话
  await ref.watch(directMessageServiceProvider).tick();
});
