import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_session.dart';
import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/resident_inbox_repository.dart';
import '../../data/repositories/resident_memory_repository.dart';
import '../../data/repositories/resident_sleep_repository.dart';
import '../models/custom_resident.dart';
import '../models/resident_memory.dart';
import 'call_registry.dart';
import 'game_session_registry.dart';
import 'memory_text.dart';
import 'model_gateway.dart';
import 'resident_wake_service.dart';

/// 一次整理的结果。没有真正跑（未开启、不空闲、没到点）时 [ran] 为 false。
class MemoryMaintenanceReport {
  const MemoryMaintenanceReport({
    required this.ran,
    this.message = '',
    this.before = 0,
    this.after = 0,
    this.removed = 0,
  });

  final bool ran;
  final String message;
  final int before;
  final int after;
  final int removed;

  int get mergedOrDeleted => removed;
}

/// 记忆页展示用的状态。
class MemoryMaintenanceState {
  const MemoryMaintenanceState({
    required this.enabled,
    this.lastRunAt,
    this.before = 0,
    this.after = 0,
    this.removed = 0,
  });

  final bool enabled;
  final DateTime? lastRunAt;
  final int before;
  final int after;
  final int removed;
}

/// 把住民叫醒，完整整理一遍长期记忆。
///
/// 两条触发路径：
/// - **后台**（WorkManager，每 [backgroundInterval] 左右一次，要求联网）：
///   APP 关着也会整理。这条是主路——用户打开 APP 时通常在聊天，不会发呆。
/// - **前台空闲**（心跳）：APP 开着，且已经 [idleThreshold] 没有真实点按。
///
/// 共同条件：住民打开了自己的自动整理、醒着、没有待办、不在通话/对局、
/// 配了对话模型，且离上次整理超过 [runInterval]。
/// 前台/后台两个 isolate 用 `app_settings` 里的一把短锁互斥，避免同时整理。
///
/// 整理只动记忆：工具白名单在 [ResidentToolSession] 里，只给 memory_* + finish。
class MemoryMaintenanceService {
  MemoryMaintenanceService({
    required this.db,
    required this.residents,
    required this.memories,
    required this.inbox,
    required this.sleep,
    required this.gateway,
    required this.wakeService,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final AppDatabase db;
  final CustomResidentRepository residents;
  final ResidentMemoryRepository memories;
  final ResidentInboxRepository inbox;
  final ResidentSleepRepository sleep;
  final ModelGateway gateway;
  final ResidentWakeService wakeService;
  final DateTime Function() now;

  static const String _enabledPrefix = 'memory.maintenance.enabled.';
  static const String _lastRunPrefix = 'memory.maintenance.lastRun.';
  static const String _lastResultPrefix = 'memory.maintenance.lastResult.';
  static const String _lastAttemptPrefix = 'memory.maintenance.lastAttempt.';
  static const String _lockKey = 'memory.maintenance.lock';

  /// 前台心跳每 30 秒刷新一次的时间戳。后台任务看到它很新，
  /// 就说明用户正开着 APP，别在人家聊天时插一轮整理。
  static const String foregroundAtKey = 'app.foregroundAt';

  /// 多久没有点按算“人已经放下手机了”。
  static const Duration idleThreshold = Duration(minutes: 10);

  /// 同一位住民两次整理至少隔一天。
  static const Duration runInterval = Duration(hours: 24);

  /// 失败/没整理出东西之后，隔一小时再试，别在一轮里反复叫模型。
  static const Duration retryGap = Duration(hours: 1);

  /// 心跳最多五分钟看一次，避免每秒都去查库。
  static const Duration checkGap = Duration(minutes: 5);

  /// 后台任务的建议检查间隔。WorkManager 只是“多一层机会”，
  /// 真正的最小粒度由系统省电策略决定；这里取 3 小时，避免为了
  /// 一天一次的整理频繁唤醒整台手机。
  static const Duration backgroundInterval = Duration(hours: 3);

  /// 跨 isolate 的整理锁：进程崩了也会在 15 分钟后自动失效。
  static const Duration lockTtl = Duration(minutes: 15);

  /// 后台一轮最多整理几位。模型调用可能几十秒，给 WorkManager 留余量。
  static const int backgroundBatch = 2;

  /// 前台时间戳多新算“APP 正在前台”。心跳 30 秒刷新一次，留两分钟余量。
  static const Duration foregroundFreshness = Duration(minutes: 2);

  bool _running = false;
  DateTime? _lastCheck;
  String? _lockValue;

  /// 开关按住民分开：一位住民的记忆页只决定 TA 自己要不要整理。
  Future<bool> isEnabled(String residentId) async =>
      await _read('$_enabledPrefix$residentId') == 'true';

  Future<void> setEnabled(String residentId, bool value) =>
      _write('$_enabledPrefix$residentId', value ? 'true' : 'false');

  Future<MemoryMaintenanceState> stateFor(String residentId) async {
    final enabled = await isEnabled(residentId);
    final lastRunMs = int.tryParse(
      await _read('$_lastRunPrefix$residentId') ?? '',
    );
    final raw = await _read('$_lastResultPrefix$residentId');
    var before = 0;
    var after = 0;
    var removed = 0;
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw);
        if (map is Map) {
          before = _asInt(map['before']);
          after = _asInt(map['after']);
          removed = _asInt(map['removed']);
        }
      } catch (_) {
        // 旧记录坏了就当没跑过，不影响整理本身。
      }
    }
    return MemoryMaintenanceState(
      enabled: enabled,
      lastRunAt: lastRunMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastRunMs),
      before: before,
      after: after,
      removed: removed,
    );
  }

  /// 心跳/后台任务调用：条件都满足时，最多整理一位住民。
  ///
  /// [background] 为 true 时跳过“前台空闲 10 分钟”的判断——
  /// 后台任务本来就是在用户没看 APP 的时候跑的。
  Future<MemoryMaintenanceReport> maybeRun({bool background = false}) async {
    if (_running) return const MemoryMaintenanceReport(ran: false);
    if (!background) {
      final at = now();
      final last = _lastCheck;
      if (last != null && at.difference(last) < checkGap) {
        return const MemoryMaintenanceReport(ran: false);
      }
      _lastCheck = at;
      // 用户正在用手机时不抢模型、不抢注意力。
      if (AppSession.idleFor < idleThreshold) {
        return const MemoryMaintenanceReport(ran: false);
      }
    }
    // 后台任务如果发现 APP 正在前台，也先让位：用户多半在聊天，
    // 整理交给前台“放下手机 10 分钟”那条路。
    if (background && await _appIsForeground()) {
      return const MemoryMaintenanceReport(ran: false);
    }

    _running = true;
    var locked = false;
    try {
      locked = await _acquireLock();
      if (!locked) {
        return const MemoryMaintenanceReport(
          ran: false,
          message: '另一轮记忆整理正在进行',
        );
      }
      final pool = await residents.all();
      MemoryMaintenanceReport? last;
      var done = 0;
      for (final resident in pool) {
        if (!resident.memoryEnabled) continue;
        if (!await isEnabled(resident.id)) continue;
        if (CallRegistry.isActive(resident.id) ||
            GameSessionRegistry.isActiveResident(resident.id)) {
          continue;
        }
        if (await sleep.current(resident.id) != null) continue;
        if ((await inbox.pending(resident.id)).isNotEmpty) continue;
        if (!await _due(resident.id)) continue;
        // 整理第一位的过程中用户可能打开了 APP：剩下的让给下一次。
        if (background && await _appIsForeground()) break;
        final report = await _runFor(resident.id, force: false);
        if (!report.ran) continue;
        last = report;
        done++;
        // 前台一次一位就够；后台给 WorkManager 留余量，最多两位。
        if (!background) return report;
        if (done >= backgroundBatch) return report;
      }
      return last ?? const MemoryMaintenanceReport(ran: false);
    } catch (error) {
      debugPrint('[记忆整理] 这一轮没跑成：$error');
      return MemoryMaintenanceReport(ran: false, message: '$error');
    } finally {
      if (locked) await _releaseLock();
      _running = false;
    }
  }

  /// 手动或自动整理某一位住民的记忆。
  ///
  /// [force] 为 true 时忽略“自动开关 / 空闲 / 24 小时”三个条件，
  /// 但仍然不把睡着的住民吵醒，也不会在通话/对局中插一脚。
  Future<MemoryMaintenanceReport> runFor(
    String residentId, {
    bool force = false,
  }) async {
    if (_running) {
      return const MemoryMaintenanceReport(ran: false, message: '另一次整理正在进行');
    }
    _running = true;
    var locked = false;
    try {
      locked = await _acquireLock();
      if (!locked) {
        return const MemoryMaintenanceReport(
          ran: false,
          message: '另一轮记忆整理正在进行',
        );
      }
      return await _runFor(residentId, force: force);
    } finally {
      if (locked) await _releaseLock();
      _running = false;
    }
  }

  Future<MemoryMaintenanceReport> _runFor(
    String residentId, {
    required bool force,
  }) async {
    final resident = await residents.findById(residentId);
    if (resident == null || !resident.memoryEnabled) {
      return const MemoryMaintenanceReport(ran: false, message: '这位住民没有开启记忆');
    }
    if (await sleep.current(residentId) != null) {
      return const MemoryMaintenanceReport(ran: false, message: 'TA 正在睡觉');
    }
    if (CallRegistry.isActive(residentId) ||
        GameSessionRegistry.isActiveResident(residentId)) {
      return const MemoryMaintenanceReport(ran: false, message: 'TA 正在通话或对局');
    }
    if (wakeService.isAwake(residentId)) {
      return const MemoryMaintenanceReport(
        ran: false,
        message: 'TA 刚醒来，等这一轮结束',
      );
    }
    if (!force && !await _due(residentId)) {
      return const MemoryMaintenanceReport(ran: false);
    }
    final config = await gateway.configFor(configId: resident.modelConfigId);
    if (config == null) {
      return const MemoryMaintenanceReport(ran: false, message: '还没有配置可用的对话模型');
    }

    final before = await memories.count(residentId);
    final at = now();
    await _write(
      '$_lastAttemptPrefix$residentId',
      '${at.millisecondsSinceEpoch}',
    );
    if (before < 2) {
      await _recordRun(residentId, at, before, before, 0);
      return MemoryMaintenanceReport(
        ran: true,
        message: '记忆太少，暂时不用整理',
        before: before,
        after: before,
      );
    }

    try {
      final all = await memories.activeAll(residentId);
      final clusters = duplicateClusters(all);
      final prompt = _buildPrompt(resident, all, clusters);
      // 给前台用户消息留个标记：后台整理期间发来的私信会先等这一轮
      // 结束，避免同一住民在两个 isolate 里同时跑模型。
      final markerKey =
          '${ResidentWakeService.maintenanceMarkerPrefix}$residentId';
      await _write(markerKey, '${at.millisecondsSinceEpoch}');
      try {
        await wakeService.wake(
          residentId,
          trigger: WakeTrigger.maintenance,
          maintenancePrompt: prompt,
        );
      } finally {
        await _deleteKey(markerKey);
      }
      // 整理完把窗口作废：下一次对话读到的是合并后的记忆，而不是旧快照。
      wakeService.invalidateWindow(residentId);
      final after = await memories.count(residentId);
      final deleted = await memories.recentlyDeleted(residentId, since: at);
      final removed = deleted.length;
      await _recordRun(residentId, at, before, after, removed);
      return MemoryMaintenanceReport(
        ran: true,
        message: removed == 0 ? '检查完了，没有重复需要合并' : '整理掉 $removed 条重复或过时记忆',
        before: before,
        after: after,
        removed: removed,
      );
    } catch (error) {
      debugPrint('[记忆整理] ${resident.name} 整理失败：$error');
      // 失败也记一次尝试，避免下一拍立刻重试。
      await _write(
        '$_lastAttemptPrefix$residentId',
        '${at.millisecondsSinceEpoch}',
      );
      return MemoryMaintenanceReport(ran: false, message: '$error');
    }
  }

  /// APP 是否正开着。后台 isolate 读不到前台的 `AppSession`，
  /// 所以由前台心跳每 30 秒写一次时间戳。
  Future<bool> _appIsForeground() async {
    final raw = await _read(foregroundAtKey);
    final at = int.tryParse(raw ?? '');
    if (at == null || at <= 0) return false;
    return now().difference(DateTime.fromMillisecondsSinceEpoch(at)) <
        foregroundFreshness;
  }

  /// 跨 isolate 短锁：前台心跳和后台 WorkManager 是两个进程，
  /// 内存里的 `_running` 管不到对方，所以用 `app_settings` 里的一个键。
  Future<bool> _acquireLock() async {
    final at = now().millisecondsSinceEpoch;
    // 前半段给 TTL 判断用，后半段是本次持有的唯一标记：
    // 放锁时只删自己那把，不会误删别人刚抢到的。
    final value = '$at-${identityHashCode(this)}-$at';
    try {
      final inserted = await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(key: _lockKey, value: value),
            mode: InsertMode.insertOrIgnore,
          );
      if (inserted > 0) {
        _lockValue = value;
        return true;
      }
    } catch (error) {
      debugPrint('[记忆整理] 抢锁失败：$error');
      return false;
    }
    // 键已存在：可能上一轮崩了没释放。超过 TTL 就接管。
    final existing = await _read(_lockKey);
    final stamp = int.tryParse((existing ?? '').split('-').first);
    if (stamp != null &&
        now().difference(DateTime.fromMillisecondsSinceEpoch(stamp)) <=
            lockTtl) {
      return false;
    }
    await _write(_lockKey, value);
    _lockValue = value;
    return true;
  }

  Future<void> _releaseLock() async {
    final value = _lockValue;
    _lockValue = null;
    if (value == null) return;
    try {
      await (db.delete(
        db.appSettings,
      )..where((t) => t.key.equals(_lockKey) & t.value.equals(value))).go();
    } catch (error) {
      debugPrint('[记忆整理] 放锁失败：$error');
    }
  }

  Future<bool> _due(String residentId) async {
    final lastRun = int.tryParse(
      await _read('$_lastRunPrefix$residentId') ?? '',
    );
    final lastAttempt = int.tryParse(
      await _read('$_lastAttemptPrefix$residentId') ?? '',
    );
    return maintenanceDue(
      now: now(),
      lastRunAt: lastRun == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastRun),
      lastAttemptAt: lastAttempt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastAttempt),
    );
  }

  Future<void> _recordRun(
    String residentId,
    DateTime at,
    int before,
    int after,
    int removed,
  ) async {
    final stamp = '${at.millisecondsSinceEpoch}';
    await _write('$_lastRunPrefix$residentId', stamp);
    await _write(
      '$_lastResultPrefix$residentId',
      jsonEncode({
        'at': at.millisecondsSinceEpoch,
        'before': before,
        'after': after,
        'removed': removed,
      }),
    );
  }

  String _buildPrompt(
    CustomResident resident,
    List<ResidentMemory> all,
    List<List<ResidentMemory>> clusters,
  ) {
    final buffer = StringBuffer()
      ..writeln('你是「${resident.name}」。现在是空闲时间，你醒来整理自己的长期记忆。')
      ..writeln('你一共有 ${all.length} 条记忆。这一轮只动记忆：')
      ..writeln('不要发私信、不要发动态、不要冒气泡、不要编造；整理完调用 finish。')
      ..writeln()
      ..writeln('要做的事：')
      ..writeln('1. 同一件事记了好几遍：保留信息最全的一条，用 memory_consolidate 把其余并进去。')
      ..writeln('2. 寒暄、客套、一时的状态、你自己的推测：用 memory_delete 删掉。')
      ..writeln('3. 记错或过时的：用 memory_update 改正；确认不再成立的才删。')
      ..writeln('4. 不要为了“看起来整齐”删掉真实发生过的经历；拿不准就留着。')
      ..writeln();
    if (clusters.isNotEmpty) {
      buffer.writeln('规则预扫发现这些可能是重复的（只是线索，最后由你判断）：');
      for (final group in clusters.take(12)) {
        buffer.writeln(
          '- ${group.map((item) => '[${item.id}] ${_clip(item.summary, 60)}').join(' / ')}',
        );
      }
      buffer.writeln();
    }
    buffer.writeln('你的记忆（id | 摘要）：');
    for (final item in all.take(80)) {
      final tags = item.tags.isEmpty ? '' : '（${item.tags.join('、')}）';
      buffer.writeln('- [${item.id}] ${_clip(item.summary, 80)}$tags');
    }
    if (all.length > 80) {
      buffer
        ..writeln()
        ..writeln(
          '还有 ${all.length - 80} 条没列出来：用 memory_list_recent 带 offset 往后翻，每次最多 50 条。',
        );
    }
    buffer
      ..writeln()
      ..writeln('整理完调用 finish。这一轮不要对任何人说话。');
    return buffer.toString();
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  static int _asInt(Object? raw) =>
      raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;

  Future<String?> _read(String key) async {
    final row = await (db.select(
      db.appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _deleteKey(String key) async {
    try {
      await (db.delete(db.appSettings)..where((t) => t.key.equals(key))).go();
    } catch (error) {
      debugPrint('[记忆整理] 标记没清掉：$error');
    }
  }

  Future<void> _write(String key, String value) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }
}

/// 是否到了可以整理的时间：离上次成功整理满一天，且离上次尝试满一小时。
@visibleForTesting
bool maintenanceDue({
  required DateTime now,
  DateTime? lastRunAt,
  DateTime? lastAttemptAt,
  Duration interval = MemoryMaintenanceService.runInterval,
  Duration retry = MemoryMaintenanceService.retryGap,
}) {
  if (lastRunAt != null && now.difference(lastRunAt) < interval) return false;
  if (lastAttemptAt != null && now.difference(lastAttemptAt) < retry) {
    return false;
  }
  return true;
}

/// 纯规则预扫：把“可能是同一件事”的记忆聚成组。
///
/// 只给模型当线索，不自动删任何东西；真正怎么处理由住民决定。
@visibleForTesting
List<List<ResidentMemory>> duplicateClusters(List<ResidentMemory> items) {
  final parent = List<int>.generate(items.length, (index) => index);
  int find(int value) {
    var root = value;
    while (parent[root] != root) {
      root = parent[root];
    }
    var cursor = value;
    while (parent[cursor] != cursor) {
      final next = parent[cursor];
      parent[cursor] = root;
      cursor = next;
    }
    return root;
  }

  void union(int a, int b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA != rootB) parent[rootB] = rootA;
  }

  final normalized = [
    for (final item in items) normalizeMemoryText(item.summary),
  ];
  for (var i = 0; i < items.length; i++) {
    for (var j = i + 1; j < items.length; j++) {
      final a = normalized[i];
      final b = normalized[j];
      if (a.isEmpty || b.isEmpty) continue;
      final shorter = a.length <= b.length ? a.length : b.length;
      final longer = a.length <= b.length ? b.length : a.length;
      if (longer > 0 && shorter / longer < 0.4) continue;
      if (isDuplicateMemory(
        summary: items[i].summary,
        content: items[i].content,
        tags: items[i].tags,
        otherSummary: items[j].summary,
        otherContent: items[j].content,
        otherTags: items[j].tags,
      )) {
        union(i, j);
      }
    }
  }

  final groups = <int, List<ResidentMemory>>{};
  for (var i = 0; i < items.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(items[i]);
  }
  return [
    for (final group in groups.values)
      if (group.length > 1) group,
  ]..sort((a, b) => b.length.compareTo(a.length));
}

final memoryMaintenanceServiceProvider = Provider<MemoryMaintenanceService>(
  (ref) => MemoryMaintenanceService(
    db: ref.watch(databaseProvider),
    residents: ref.watch(customResidentRepositoryProvider),
    memories: ref.watch(residentMemoryRepositoryProvider),
    inbox: ref.watch(residentInboxRepositoryProvider),
    sleep: ref.watch(residentSleepRepositoryProvider),
    gateway: ref.watch(modelGatewayProvider),
    wakeService: ref.watch(residentWakeServiceProvider),
  ),
);
