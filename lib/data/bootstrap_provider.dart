import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/services/scheduler_service.dart';
import '../domain/services/speech_models.dart';
import 'db/database_provider.dart';

/// 启动引导：开库 → 首次播种（**只等这一段**）→ 补发与世界里发生的事。
///
/// 首屏只依赖数据库和播种；后面的补发、世界 tick、私信 tick 都可能联网，
/// 模型慢的时候能拖上半分钟。以前它们串在同一条 await 链上，于是
/// “APP 一直在加载、超时后说开库失败”，而退出重进（网络缓存/模型刚好回完）
/// 又正常了——这是等待，不是数据库坏了。
///
/// 现在把后半段放到后台跑：界面立刻可用，补出来的内容由 Drift 的
/// 表更新通知自己冒出来。三条补发路径（冷启动 / 回前台 / 心跳）都还在。
final appBootstrapProvider = FutureProvider<void>((ref) async {
  await _bootstrapStep(
    '打开本地数据库并播种',
    () => ref.watch(seedServiceProvider).seedIfNeeded(),
    // 播种只是本地写入。真卡住时给一次明确失败，而不是无限转圈。
    timeout: const Duration(seconds: 30),
  );

  // 先把服务对象取出来：后台任务不应该在 provider 结束后还攥着 ref。
  final scheduler = ref.watch(schedulerServiceProvider);
  final speech = ref.watch(speechModelStoreProvider);
  unawaited(_catchUp(scheduler));
  // 两套语音模型有 300MB 左右，第一次启动要搬到应用目录。放到后台做，
  // 等用户真的点语音时就不必在工具调用的 30/90 秒里慢慢拷。
  unawaited(_prewarmSpeech(speech));
});

Future<void> _prewarmSpeech(SpeechModelStore store) async {
  try {
    await store.prepareTts();
  } catch (error) {
    debugPrint('[启动] 文字语音模型没准备好：$error');
  }
  try {
    await store.prepareZipVoice();
  } catch (error) {
    debugPrint('[启动] 克隆语音模型没准备好：$error');
  }
}

/// 离线期间该补的东西。失败只记日志——这一轮没补上，
/// 下一次回前台或 30 秒心跳还会再补。
///
/// 这里**不再跑世界 tick**：固定住民的动态交给它自己醒来后用
/// `create_post` 决定，平台不预生成、也不补在过去的时间点上。
Future<void> _catchUp(SchedulerService scheduler) async {
  final steps = <(String, Future<void> Function())>[
    ('补发离线期间到点的互动', scheduler.flushDue),
  ];

  for (final (label, run) in steps) {
    try {
      await _bootstrapStep(
        label,
        run,
        timeout: const Duration(seconds: 60),
      );
    } catch (error) {
      debugPrint('[启动] $error');
    }
  }
}

/// 跑一步，失败时把**是哪一步**记下来再往外抛。
///
/// 启动失败页原本只会说一句"本地数据库启动失败"，可真正炸的可能是后面
/// 任意一步——2026-10-14 真机上报过一次，重装才好、也复现不出来，
/// 就是因为现场只剩那句笼统的话。带上步骤名（和一条日志），下次能一眼看出断在哪。
Future<void> _bootstrapStep(
  String label,
  Future<void> Function() run, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  try {
    await run().timeout(timeout);
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
