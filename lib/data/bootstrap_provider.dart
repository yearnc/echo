import 'package:flutter/foundation.dart';
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
  await _bootstrapStep(
    '打开本地数据库并播种',
    () => ref.watch(seedServiceProvider).seedIfNeeded(),
  );
  await _bootstrapStep(
    '补发离线期间到点的互动',
    () => ref.watch(schedulerServiceProvider).flushDue(),
  );
  await _bootstrapStep(
    '补上社区这段时间的动静',
    () => ref.watch(worldServiceProvider).tick(),
  );
  // 私信排在最后：它要读刚更新的关系（谁到了互关、谁该来敲你的门），
  // 也要看有没有你说了话、他还欠着一句的会话
  await _bootstrapStep(
    '处理私信',
    () => ref.watch(directMessageServiceProvider).tick(),
  );
});

/// 跑一步，失败时把**是哪一步**记下来再往外抛。
///
/// 启动失败页原本只会说一句"本地数据库启动失败"，可真正炸的可能是后面
/// 任意一步——2026-10-14 真机上报过一次，重装才好、也复现不出来，
/// 就是因为现场只剩那句笼统的话。带上步骤名（和一条日志），下次能一眼看出断在哪。
Future<void> _bootstrapStep(String label, Future<void> Function() run) async {
  try {
    await run();
  } catch (error, stack) {
    debugPrint('[启动] $label 失败：$error\n$stack');
    throw BootstrapStepFailure(label, error);
  }
}

/// 启动某一步失败：对外说人话，日志里留全尸。
class BootstrapStepFailure implements Exception {
  const BootstrapStepFailure(this.step, this.cause);

  final String step;
  final Object cause;

  @override
  String toString() => '「$step」这一步没成：$cause';
}
