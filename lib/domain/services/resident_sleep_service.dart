import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/private_message_repository.dart';
import '../../data/repositories/resident_sleep_repository.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../models/custom_resident.dart';
import '../models/resident_sleep.dart';
import 'resident_wake_service.dart';

/// 固定住民的睡眠。
///
/// 热情不是无限的：连续五天没有任何互动，TA 会自己睡去；用户也可以
/// 从睡眠页让 TA 先歇一会儿。入睡前留最后一句话，醒来时知道过了多久。
/// 发帖、评论别人不算“找 TA”，只有私信、通话、游戏、桌宠这类直接互动才算。
class ResidentSleepService {
  ResidentSleepService({
    required this.residents,
    required this.sleep,
    required this.messages,
    required this.profiles,
    required this.wakeService,
    this.now = DateTime.now,
  });

  final CustomResidentRepository residents;
  final ResidentSleepRepository sleep;
  final PrivateMessageRepository messages;
  final UserProfileRepository profiles;
  final ResidentWakeService wakeService;
  final DateTime Function() now;

  /// 五天没有任何互动就自动入睡。
  static const Duration autoSleepAfter = Duration(days: 5);

  /// 自动检查不需要很勤：睡眠是“五天”尺度的状态，不是秒表。
  static const Duration checkGap = Duration(minutes: 30);

  DateTime? _lastCheck;
  bool _checking = false;
  final Set<String> _farewelling = {};

  /// 正在睡吗。
  Future<ResidentSleepPeriod?> current(String residentId) =>
      sleep.current(residentId);

  /// 用户主动找 TA 之前调用：先记互动；如果 TA 在睡，就当场唤醒，
  /// 并把“睡了多久”交给这一轮唤醒，放在消息最前面。
  ///
  /// 返回 null 表示 TA 本来醒着，调用方不用额外处理。
  Future<SleepWakeNotice?> prepareInteraction(String residentId) async {
    final at = now();
    await residents.touchInteraction(residentId, at: at);
    final period = await sleep.current(residentId);
    if (period == null) return null;
    await sleep.wake(residentId, endedBy: 'interaction', at: at);
    return SleepWakeNotice(
      sleptFrom: period.startedAt,
      wokeAt: at,
      manual: false,
    );
  }

  /// 只记一次互动（没有唤醒需求时用；比如主人随手点开桌宠控制）。
  Future<void> touch(String residentId) =>
      residents.touchInteraction(residentId, at: now());

  /// 对一批住民执行“直接找 TA”：记互动、睡着的当场叫醒。
  ///
  /// 私信、通话、约局、对局里走一步都用它；发帖不要调用。
  Future<void> interactAll(Iterable<String> residentIds) async {
    final seen = <String>{};
    for (final id in residentIds) {
      if (id.isEmpty || !seen.add(id)) continue;
      final notice = await prepareInteraction(id);
      if (notice == null) continue;
      unawaited(
        wakeService.wake(
          id,
          trigger: WakeTrigger.userAction,
          sleepNotice: notice,
        ),
      );
    }
  }

  /// 用户从睡眠页唤醒。
  ///
  /// 先结束睡眠状态，再让 TA 醒来说话。模型调用不阻塞页面：
  /// “已经醒了”是立刻生效的，回复可以晚一点到。
  Future<SleepWakeNotice?> wakeManually(String residentId) async {
    final at = now();
    await residents.touchInteraction(residentId, at: at);
    final period = await sleep.wake(residentId, endedBy: 'manual', at: at);
    if (period == null) return null;
    final notice = SleepWakeNotice(
      sleptFrom: period.startedAt,
      wokeAt: at,
      manual: true,
    );
    unawaited(
      wakeService.wake(
        residentId,
        trigger: WakeTrigger.userAction,
        sleepNotice: notice,
      ),
    );
    return notice;
  }

  /// 让 TA 入睡。
  ///
  /// [startedBy] 是 `manual` 或 `auto`。无论哪一种，都先落睡眠状态，
  /// 再叫醒 TA 说最后一句话——这样这一轮里别的路径不会把它当成醒着。
  Future<ResidentSleepPeriod?> sleepNow(
    String residentId, {
    String startedBy = 'manual',
  }) async {
    final period = await sleep.start(
      residentId: residentId,
      startedBy: startedBy,
      at: now(),
    );
    if (period.isSleeping && period.startedAt.isAfter(
      now().subtract(const Duration(seconds: 5)),
    )) {
      unawaited(_leaveFarewell(residentId, period, startedBy));
    }
    return period;
  }

  Future<void> _leaveFarewell(
    String residentId,
    ResidentSleepPeriod period,
    String startedBy,
  ) async {
    if (!_farewelling.add(residentId)) return;
    try {
      final resident = await residents.findById(residentId);
      if (resident == null) return;
      final profile = await profiles.load();
      final name = profile?.displayName ?? '对方';
      final automatic = startedBy == 'auto';
      final prompt = automatic
          ? '$name已经五天没来找你了，你即将进入睡眠状态，给TA留最后一句话吧。'
          : '对方让你先睡一会儿，你即将进入睡眠状态，给TA留最后一句话吧。';
      await wakeService.wake(
        residentId,
        trigger: WakeTrigger.sleep,
        farewellPrompt: prompt,
      );
      // 醒来后的收尾：如果这轮留下了私信，把最后一句记进这段睡眠。
      final last = await messages.lastOutgoing(residentId);
      if (last != null && last.createdAt.isAfter(period.startedAt)) {
        await sleep.setFarewell(period.id, last.content);
      }
    } catch (error) {
      debugPrint('[睡眠] $residentId 的最后一句话没说出来：$error');
    } finally {
      _farewelling.remove(residentId);
    }
  }

  /// 自动把“五天没互动”的住民送进睡眠。
  ///
  /// 冷启动、前台心跳和后台任务都可以调用；内部按 [checkGap] 限流，
  /// 不会每 30 秒扫一遍。
  Future<int> checkAutoSleep({bool force = false}) async {
    final at = now();
    final last = _lastCheck;
    if (!force &&
        last != null &&
        at.difference(last) < checkGap) {
      return 0;
    }
    if (_checking) return 0;
    _checking = true;
    _lastCheck = at;
    try {
      final pool = await residents.all();
      var slept = 0;
      for (final resident in pool) {
        if (await sleep.isSleeping(resident.id)) continue;
        final quietFor = at.difference(resident.interactionAnchor);
        if (quietFor < autoSleepAfter) continue;
        await sleepNow(resident.id, startedBy: 'auto');
        slept++;
        debugPrint(
          '[睡眠] ${resident.name}：${quietFor.inDays} 天没互动，先睡了',
        );
      }
      return slept;
    } catch (error) {
      debugPrint('[睡眠] 自动检查没跑完：$error');
      return 0;
    } finally {
      _checking = false;
    }
  }

  /// 睡眠页用：每位住民的当前状态和上一次互动。
  Future<List<ResidentSleepView>> overview() async {
    final pool = await residents.all();
    final sleeping = {
      for (final period in await sleep.sleeping()) period.residentId: period,
    };
    final at = now();
    return [
      for (final resident in pool)
        ResidentSleepView(
          resident: resident,
          period: sleeping[resident.id],
          quietFor: at.difference(resident.interactionAnchor),
        ),
    ];
  }
}

class ResidentSleepView {
  const ResidentSleepView({
    required this.resident,
    required this.period,
    required this.quietFor,
  });

  final CustomResident resident;
  final ResidentSleepPeriod? period;
  final Duration quietFor;

  bool get isSleeping => period != null;
}

final residentSleepServiceProvider = Provider<ResidentSleepService>(
  (ref) => ResidentSleepService(
    residents: ref.watch(customResidentRepositoryProvider),
    sleep: ref.watch(residentSleepRepositoryProvider),
    messages: ref.watch(privateMessageRepositoryProvider),
    profiles: ref.watch(userProfileRepositoryProvider),
    wakeService: ref.watch(residentWakeServiceProvider),
  ),
);
