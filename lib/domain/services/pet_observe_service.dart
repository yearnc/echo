import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/pet_settings_repository.dart';
import '../../data/repositories/resident_memory_repository.dart';
import '../../data/repositories/resident_wake_log_repository.dart';
import '../models/pet_observation.dart';
import '../models/pet_settings.dart';
import 'call_registry.dart';
import 'model_gateway.dart';
import 'pet_native.dart';
import 'photo_describer.dart';
import 'resident_context_log.dart';
import 'resident_wake_service.dart';

class _PetFrame {
  const _PetFrame(this.path, this.at);

  final String path;
  final DateTime at;
}

/// 桌宠观察此刻走到哪一步（给桌宠页显示，方便确认它是不是真的在看）。
class PetObserveStatus {
  const PetObserveStatus({
    this.frames = 0,
    this.lastFrameAt,
    this.lastWakeAt,
    this.lastWake = '',
    this.lastError = '',
  });

  final int frames;
  final DateTime? lastFrameAt;
  final DateTime? lastWakeAt;
  final String lastWake;
  final String lastError;
}

/// 桌宠的观察循环（v4.0）。
///
/// 普通模式：隔十到二十分钟抓一张，交给当前控制住民点评一句。
/// 实时模式：原生侧按“观察间隔 ÷ 帧数”连续抓图，这里按用户选的间隔
/// 从整个窗口里均匀取几帧唤醒一次；
/// 关闭时先让住民把这段观察总结成一条记忆，写成功才清截图。
///
/// 上下文只保留“这段时间的简短观察”，不把每一帧都永久塞进历史——
/// 实时模式很贵，贵在图片，不该再贵在无限增长的历史。
class PetObserveService {
  PetObserveService({
    required this.native,
    required this.wake,
    required this.settings,
    required this.residents,
    required this.memories,
    required this.photos,
    required this.gateway,
    required this.wakeLogs,
    required this.contextLog,
  });

  final PetNative native;
  final ResidentWakeService wake;
  final PetSettingsRepository settings;
  final CustomResidentRepository residents;
  final ResidentMemoryRepository memories;
  final PhotoDescriber photos;
  final ModelGateway gateway;
  final ResidentWakeLogRepository wakeLogs;

  /// 屏幕这一侧看到/说过的东西，私信那一轮也要读到。
  final ResidentContextLog contextLog;

  /// 当前这段“桌宠醒着”的日志属于谁；换控制者时先收尾再开新的。
  String? _logResidentId;

  final Random _random = Random();
  StreamSubscription<Map<String, Object?>>? _subscription;
  Timer? _timer;
  Timer? _shiftTimer;
  bool _busy = false;
  bool _observing = false;
  bool _captureWaiting = false;
  bool _handingOff = false;
  bool _checkpointing = false;
  final Set<String> _recovering = {};
  int _wakesSinceCheckpoint = 0;
  final List<_PetFrame> _frames = [];

  /// 每位控制者这一班是几点开始的；私信增量从这里往后筛。
  final Map<String, DateTime> _sessionStartedAt = {};

  /// 每位控制者上一次被观察的时刻（换班时清空）。
  final Map<String, DateTime> _lastWakeAt = {};

  /// 刚接手的那一位：下一轮观察要告诉它“这是我第一次看”。
  final Set<String> _handoffPending = {};

  /// 实时观察每看这么多轮，就强制整理一次记忆，避免早期观察被挤掉。
  static const int checkpointEvery = 8;

  /// 给桌宠页看的状态（收到几帧、上次唤醒结果、错误）。
  final ValueNotifier<PetObserveStatus> status = ValueNotifier(
    const PetObserveStatus(),
  );

  void _setStatus({
    int? frames,
    DateTime? frameAt,
    DateTime? wakeAt,
    String? wake,
    String? error,
  }) {
    final old = status.value;
    status.value = PetObserveStatus(
      frames: frames ?? old.frames,
      lastFrameAt: frameAt ?? old.lastFrameAt,
      lastWakeAt: wakeAt ?? old.lastWakeAt,
      lastWake: wake ?? old.lastWake,
      lastError: error ?? old.lastError,
    );
  }

  /// 实时模式最多留这么多帧；旧的边收边删。
  /// 一个唤醒窗口只会截“每次带几张”那么多张，240 帧足够覆盖改设置前的残留。
  static const int maxFrames = 240;

  /// 桌宠自己的参照图：截图会把它截进去，模型得知道那是谁。
  /// v4.1 起素材是 `manifest.json` 编号的无损 WebP 帧，act_001 = 待机呼吸。
  static const String selfImageRef = 'asset:assets/pet_frames/act_001_00.webp';

  /// 每次唤醒附几张、隔多久唤醒一次，都由用户在桌宠页选。
  int _framesPerWake = 3;
  Duration _gap = const Duration(seconds: 20);

  void attach() {
    _subscription ??= native.events.listen(_onEvent);
  }

  Future<void> detach() async {
    _timer?.cancel();
    _timer = null;
    _shiftTimer?.cancel();
    _shiftTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _clearFrames();
    contextLog.clearAll();
    _sessionStartedAt.clear();
    _lastWakeAt.clear();
    _handoffPending.clear();
    status.value = const PetObserveStatus();
    await _endLogSession();
  }

  /// 设置变了：重排计时器；实时模式交给原生连续抓图。
  Future<void> sync(PetSettings value) async {
    _timer?.cancel();
    _timer = null;
    _shiftTimer?.cancel();
    _shiftTimer = null;
    if (!value.enabled) return;
    // 先把“醒着”的日志建立起来：时长从桌宠打开算，不是从第一次截图算。
    final controller = await controllerId();
    // 换班检查独立于观察间隔：观察间隔可能被用户调到 10 分钟，
    // 但值班表整点换人时不能让它再多看十分钟才认新的控制者。
    _shiftTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(controllerId()),
    );
    if (controller != null) {
      await _recoverDigest(controller);
    }
    if (value.realtime) {
      _framesPerWake = value.realtimeFrames.clamp(1, 6);
      _gap = Duration(
        seconds: value.realtimeGapSeconds.clamp(
          PetSettings.minRealtimeGapSeconds,
          PetSettings.maxRealtimeGapSeconds,
        ),
      );
      // 截屏间隔由“观察间隔 ÷ 每次带几张”算出来，不再单独设置。
      await native.setWatchInterval(value.captureIntervalMs);
      await native.setContinuous(true);
      _timer = Timer.periodic(_gap, (_) => _observeRealtime());
    } else {
      await native.setContinuous(false);
      _scheduleNormal();
    }
  }

  void _scheduleNormal() {
    _timer?.cancel();
    final minutes = 10 + _random.nextInt(11);
    _timer = Timer(Duration(minutes: minutes), () async {
      await native.captureOnce();
      _captureWaiting = true;
      // 抓不到也算这一轮过去：下一轮重新排，不在这里死等。
      Timer(const Duration(seconds: 8), () => _captureWaiting = false);
      _scheduleNormal();
    });
  }

  void _onEvent(Map<String, Object?> event) {
    final kind = event['event'];
    if (kind == 'bubble') {
      final ok = event['ok'] == true;
      final text = (event['text'] as String?) ?? '';
      final message = (event['message'] as String?) ?? '';
      _setStatus(
        wake: ok ? '气泡：${_short(text)}' : '气泡失败：${_short(message)}',
        error: ok ? '' : message,
      );
      return;
    }
    if (kind != 'frame') return;
    final path = event['path'];
    if (path is! String || path.isEmpty) return;
    final at = event['at'] is int
        ? DateTime.fromMillisecondsSinceEpoch(event['at'] as int)
        : DateTime.now();
    _frames.add(_PetFrame(path, at));
    while (_frames.length > maxFrames) {
      final old = _frames.removeAt(0);
      _deleteFile(old.path);
    }
    _setStatus(frames: _frames.length, frameAt: at, error: '');
    if (_captureWaiting) {
      _captureWaiting = false;
      unawaited(_observeFrame('file:$path'));
    }
  }

  Future<String?> controllerId() async {
    // 换班收尾可能正在跑：等它跑完再决定这一轮是谁的。
    for (var i = 0; i < 300 && _handingOff; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final value = await settings.load();
    final candidate = await settings.controllerAt(
      DateTime.now(),
      fallbackResidentId: value.defaultResidentId,
    );
    var result = await _validController(candidate, value.defaultResidentId);
    if (result == null && candidate != null) {
      // 排班表里的人已经被删了：别让它继续“控制”一只没人管的桌宠，
      // 能回落到默认控制者就回落，不然这一班先停。
      result = await _validController(value.defaultResidentId, '');
    }
    await _maybeHandoff(result);
    await _ensureLogSession(result);
    return result;
  }

  /// 只认还在的住民；正在通话的人这一班让给通话。
  Future<String?> _validController(String? id, String fallback) async {
    final clean = id?.trim() ?? '';
    if (clean.isEmpty) return null;
    final resident = await residents.findById(clean);
    if (resident == null) return null;
    if (CallRegistry.isActive(clean)) {
      if (fallback.trim().isEmpty || fallback == clean) return null;
      return _validController(fallback, '');
    }
    return clean;
  }

  /// 到点换人（或有人被删）时，先让上一位把这班收尾成记忆，
  /// 再清掉这一班拍的画面，最后才把新的一班交给下一位。
  Future<void> _maybeHandoff(String? next) async {
    final previous = _logResidentId;
    if (previous == next || _handingOff) return;
    _handingOff = true;
    try {
      if (previous != null) {
        // 等正在看的那一眼结束，避免同一位住民两轮唤醒打架。
        for (var i = 0; i < 60 && _busy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await _summarizeSession(
          previous,
          reason: next == null ? '这一班先到这里' : '下面换人来陪他',
          clearOnSuccess: true,
        );
      }
      // 上一位拍到的画面不该给下一位看。
      _clearFrames();
      _lastWakeAt.remove(previous);
      _wakesSinceCheckpoint = 0;
      if (next != null && previous != null) {
        _handoffPending.add(next);
        _sessionStartedAt[next] = DateTime.now();
      }
      _setStatus(
        wake: next == null ? '暂时没人接手，先停下观察' : '控制权已交给下一位',
      );
    } finally {
      _handingOff = false;
    }
  }

  /// 桌宠的“醒着”是一段连续日志：控制者变了就先收尾旧的、再开新的；
  /// 暂时无人（通话中）就收尾，等有人接手再开。
  Future<void> _ensureLogSession(String? residentId) async {
    if (residentId == _logResidentId) return;
    await _endLogSession();
    _logResidentId = residentId;
    if (residentId == null) return;
    _sessionStartedAt.putIfAbsent(residentId, DateTime.now);
    final open = await wakeLogs.openPetLog(residentId);
    if (open == null) {
      await wakeLogs.startPetLog(residentId);
    }
  }

  Future<void> _endLogSession() async {
    final current = _logResidentId;
    _logResidentId = null;
    if (current != null) {
      await wakeLogs.finishPetLog(current);
    }
  }

  Future<void> _observeFrame(String ref) async {
    if (_observing) return;
    _observing = true;
    try {
      // 先换班再开始忙：否则换班收尾会等这一轮结束，白白卡 6 秒。
      final residentId = await controllerId();
      if (residentId == null) return;
      _busy = true;
      final resident = await residents.findById(residentId);
      if (resident == null) return;
      final config =
          await gateway.configFor(configId: resident.modelConfigId) ??
          await gateway.activeConfig();
      final canSee = config?.supportsVision ?? false;

      final description = await photos.describe(ref);
      final shared = contextLog.recent(residentId);
      final previousWake = _lastWakeAt[residentId];
      final now = DateTime.now();
      final note = [
        '这是 ${_clock(now)} 刚刚截的一张（${_ago(now)}）。',
        if (previousWake != null)
          '距上一次观察过去了 ${_durationLabel(now.difference(previousWake))}。',
        description.isEmpty ? '画面已经附在后面；如果你看不懂图，就说没看清。' : '画面：$description',
        if (shared.isNotEmpty) '这段时间此前的上下文：\n${shared.join('\n')}',
      ].join('\n');
      // 普通模式只留这一张，看完就删；不把一整天都存成图库。
      await wake.wake(
        residentId,
        trigger: WakeTrigger.pet,
        pet: PetObservation(
          images: canSee ? [ref] : const [],
          note: note,
          selfImage: canSee ? selfImageRef : null,
          sessionStartedAt: _sessionStartedAt[residentId],
          lastWakeAt: previousWake,
          handoff: _handoffPending.remove(residentId),
        ),
      );
      _lastWakeAt[residentId] = now;
      _deleteFile(ref.replaceFirst('file:', ''));
      // 气泡说过的话已经在 pet_say 那一刻写进共享上下文；这里只补
      // “看到了什么”，私信下一次醒来也能接上。
      wake.takePetSaid(residentId);
      contextLog.add(
        residentId,
        '${_clock(DateTime.now())} 你看了屏幕：'
        '${description.isEmpty ? '（没看清）' : description}',
      );
      _setStatus(wakeAt: DateTime.now(), wake: '普通模式点评完成');
    } catch (error) {
      debugPrint('[桌宠] 这次观察没成：$error');
      _setStatus(error: '$error');
    } finally {
      _busy = false;
      _observing = false;
    }
  }

  /// 按时间均匀挑 [count] 帧，首尾都包含。
  List<_PetFrame> _pickFrames(int count, {List<_PetFrame>? pool}) {
    final source = pool ?? _frames;
    if (source.isEmpty) return const [];
    final wanted = count.clamp(1, 6);
    if (source.length <= wanted) return List<_PetFrame>.of(source);
    if (wanted == 1) return [source.last];
    return [
      for (var i = 0; i < wanted; i++)
        source[((source.length - 1) * i / (wanted - 1)).round()],
    ];
  }

  Future<void> _observeRealtime() async {
    if (_observing || _handingOff) return;
    _observing = true;
    try {
      // 换班要发生在这一轮开始之前，而且这时 _busy 还是 false：
      // 否则收尾等待会把自己等成 6 秒超时。
      final residentId = await controllerId();
      if (residentId == null) return;

      _busy = true;
      // 唤醒前补截一张：原来的“最后一张”可能已经是几秒前（间隔 20 秒、
      // 带 3 张时约 6.7 秒），这就叫“看到的是上一幕”。现在先截，
      // 停 0.5 秒再叫醒，模型看到的就是说话前那一刻的屏幕。
      CapturedFrame? fresh;
      try {
        fresh = await native.captureNow();
        if (fresh != null) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      } catch (error) {
        debugPrint('[桌宠] 唤醒前补截没成：$error');
      }

      // 从整个唤醒窗口里均匀抽，而不是只拿最后几张：
      // 1 秒一张、20 秒唤醒一次时，前面那些帧也该被看到。
      // 补截的那张单独放在最后，不挤掉窗口里的取样名额。
      final wanted = _framesPerWake.clamp(1, 6);
      final pool = _frames
          .where((frame) => fresh == null || frame.path != fresh.path)
          .toList(growable: false);
      final picked = _pickFrames(
        fresh == null ? wanted : wanted - 1,
        pool: pool,
      );
      final recent = <_PetFrame>[
        ...picked,
        if (fresh != null) _PetFrame(fresh.path, fresh.at),
      ];
      if (recent.isEmpty) return;

      final resident = await residents.findById(residentId);
      if (resident == null) return;
      final config =
          await gateway.configFor(configId: resident.modelConfigId) ??
          await gateway.activeConfig();
      final canSee = config?.supportsVision ?? false;

      // 能看图的模型不必每轮再花一次视觉请求；关闭总结时会附最近两帧。
      // 不能看图的才需要先把最后一帧描述成文字。
      final description = canSee
          ? ''
          : await photos.describe('file:${recent.last.path}');
      final shared = contextLog.recent(residentId);
      final previousWake = _lastWakeAt[residentId];
      final now = DateTime.now();
      final frameTimes = [
        for (var i = 0; i < recent.length; i++)
          '第 ${i + 1} 张 ${_clock(recent[i].at)}'
              '（${_ago(recent[i].at, now: now)}）',
      ].join('；');
      final note = [
        '这是过去 ${_gap.inSeconds} 秒里抽出的 ${recent.length} 张画面。',
        '各张时间：$frameTimes。',
        if (fresh != null)
          '最后一张是在叫醒你之前 0.5 秒刚截的，就是此刻的屏幕。',
        if (previousWake != null)
          '距上一次观察过去了 ${_durationLabel(now.difference(previousWake))}。',
        if (_handoffPending.contains(residentId))
          '你刚接手这只桌宠，新的一班从现在开始。',
        if (description.isNotEmpty) '最后一张的画面：$description',
        if (shared.isNotEmpty) '这段时间此前的观察和你说过的话：\n${shared.join('\n')}',
      ].join('\n');

      final handled = await wake.wake(
        residentId,
        trigger: WakeTrigger.pet,
        pet: PetObservation(
          images: canSee
              ? [for (final frame in recent) 'file:${frame.path}']
              : const [],
          note: note,
          realtime: true,
          selfImage: canSee ? selfImageRef : null,
          sessionStartedAt: _sessionStartedAt[residentId],
          lastWakeAt: previousWake,
          handoff: _handoffPending.remove(residentId),
        ),
      );
      debugPrint(
        '[桌宠] 实时观察：${recent.length} 帧，控制者 $residentId，'
        '唤醒结果 $handled',
      );
      // 气泡本身在 pet_say 那一刻已经写进共享上下文，这里只记画面；
      // takePetSaid 仍要调用，把“这一轮说过什么”的标记取走。
      wake.takePetSaid(residentId);
      contextLog.add(
        residentId,
        '${_clock(recent.first.at)}—${_clock(recent.last.at)}：'
        '${description.isEmpty ? '看了屏幕' : description}',
      );
      _lastWakeAt[residentId] = now;
      _wakesSinceCheckpoint++;
      // 每轮都落一次盘：进程下一秒被清掉，这段观察也还在。
      await _persistDigest(residentId);
      _setStatus(
        wakeAt: now,
        wake: '唤醒 $handled（${recent.length} 帧）',
        error: '',
      );

      // 早期观察会被 12 行上限挤掉，所以在挤掉之前先让住民整理一次。
      if (_wakesSinceCheckpoint >= checkpointEvery ||
          contextLog.recent(residentId).length >=
              ResidentContextLog.maxLines - 2) {
        unawaited(_writeCheckpoint(residentId));
      }
    } catch (error) {
      debugPrint('[桌宠] 实时观察没成：$error');
      _setStatus(error: '$error');
    } finally {
      _busy = false;
      _observing = false;
    }
  }

  /// 把这一班还没整理成记忆的文字落盘（只是几行字，不调模型）。
  Future<void> _persistDigest(String residentId) async {
    final lines = contextLog.recent(residentId);
    if (lines.isEmpty) return;
    await settings.saveDigest(residentId, lines.join('\n'));
  }

  /// 定期检查点：让住民把这段观察真正写进长期记忆，写成功才清短期上下文。
  ///
  /// 不做这一步的话，12 行上限一到，最早的观察就被挤掉了；做的话，
  /// 即使之后进程被杀，也已经有一条记忆留在库里。
  Future<void> _writeCheckpoint(String residentId) async {
    if (_checkpointing) return;
    _checkpointing = true;
    try {
      final shared = contextLog.recent(residentId);
      if (shared.isEmpty) {
        await settings.clearDigest(residentId);
        _wakesSinceCheckpoint = 0;
        return;
      }
      await _persistDigest(residentId);
      final before = DateTime.now();
      await wake.wake(
        residentId,
        trigger: WakeTrigger.pet,
        pet: PetObservation(
          note:
              '你已经看了一段时间屏幕，先停一下把值得留下的整理成记忆。'
              '下面这些是你这段时间看到和说过的：\n${shared.join('\n')}\n'
              '用 memory_write 写一条简短记忆（不要写成日记，也不要提“截图”）。'
              '写完之后可以继续安静待着。',
          realtime: true,
          sessionStartedAt: _sessionStartedAt[residentId],
          lastWakeAt: _lastWakeAt[residentId],
        ),
      );
      final recent = await memories.recent(residentId, limit: 1);
      final wrote =
          recent.isNotEmpty && !recent.first.createdAt.isBefore(before);
      if (wrote) {
        contextLog.clear(residentId);
        await settings.clearDigest(residentId);
        _wakesSinceCheckpoint = 0;
        _setStatus(wake: '已把这段观察整理成记忆');
      }
    } catch (error) {
      debugPrint('[桌宠] 检查点没写成：$error');
    } finally {
      _checkpointing = false;
    }
  }

  /// 收尾一位控制者的这一班：先落盘，再让模型整理，成功才清文字和截图。
  Future<bool> _summarizeSession(
    String residentId, {
    required String reason,
    bool clearOnSuccess = true,
  }) async {
    final shared = contextLog.recent(residentId);
    if (shared.isEmpty) {
      // 只有截图、没有一条“看到了什么”，不值得为它编一条记忆。
      await settings.clearDigest(residentId);
      contextLog.clear(residentId);
      return true;
    }
    await _persistDigest(residentId);
    final before = DateTime.now();
    try {
      await wake.wake(
        residentId,
        trigger: WakeTrigger.pet,
        pet: PetObservation(
          note:
              '桌宠这一班要结束了（$reason）。这段时间你一直看着屏幕，'
              '下面是看到的和你说过的话：\n'
              '${shared.isEmpty ? '（没有更多细节）' : shared.join('\n')}\n'
              '把真正值得记的整理成一条简短记忆，用 memory_write 写下来。'
              '不要写成日记，也不要提“截图”；如果画面里有你自己，'
              '那是你，不要当成别人。这一轮不用再冒气泡。',
          realtime: true,
          sessionStartedAt: _sessionStartedAt[residentId],
          lastWakeAt: _lastWakeAt[residentId],
          handoff: true,
        ),
      );
    } catch (error) {
      debugPrint('[桌宠] 这一班收尾没成：$error');
      return false;
    }
    final recent = await memories.recent(residentId, limit: 1);
    final wrote = recent.isNotEmpty && !recent.first.createdAt.isBefore(before);
    if (wrote) {
      if (clearOnSuccess) {
        contextLog.clear(residentId);
        await settings.clearDigest(residentId);
      }
      return true;
    }
    // 没写成也先把文字留着（digest 已落盘）；截图由调用方决定清不清。
    return false;
  }

  /// 所有还没收尾的观察都补写一次。
  ///
  /// APP 被更新 / 清后台时，桌宠服务可能已经不在了；下次打开不会再走
  /// `sync`（因为 enabled 已被收回 false），所以这里必须单独扫一遍。
  Future<void> recoverPendingDigests() async {
    try {
      final ids = await settings.digestResidentIds();
      for (final id in ids) {
        if (id == _logResidentId) continue;
        await _recoverDigest(id);
      }
    } catch (error) {
      debugPrint('[桌宠] 检查未收尾观察失败：$error');
    }
  }

  /// 上次进程被杀 / 被更新打断时留下的文字，补交给住民写成记忆。
  Future<void> _recoverDigest(String residentId) async {
    if (!_recovering.add(residentId)) return;
    try {
      final digest = await settings.digest(residentId);
      if (digest == null || digest.trim().isEmpty) return;
      final before = DateTime.now();
      await wake.wake(
        residentId,
        trigger: WakeTrigger.pet,
        pet: PetObservation(
          note:
              '上一次桌宠观察没有正常结束（APP 被关掉或更新了），'
              '这是最后留下的记录：\n$digest\n'
              '把其中真正值得记的整理成一条简短记忆，用 memory_write 写下来；'
              '不要写成日记，也不要提“截图”。',
          realtime: true,
          sessionStartedAt: _sessionStartedAt[residentId],
          lastWakeAt: _lastWakeAt[residentId],
          handoff: true,
        ),
      );
      final recent = await memories.recent(residentId, limit: 1);
      final wrote =
          recent.isNotEmpty && !recent.first.createdAt.isBefore(before);
      if (wrote) {
        await settings.clearDigest(residentId);
        contextLog.clear(residentId);
        _setStatus(wake: '补写了上次没来得及记的观察');
      }
    } catch (error) {
      debugPrint('[桌宠] 补写上次观察没成：$error');
    } finally {
      _recovering.remove(residentId);
    }
  }

  /// APP 要切后台 / 被系统收走前调一次：至少把文字落盘。
  ///
  /// 不在这里强等模型：切后台只有几秒，等模型返回多半来不及。
  /// 落盘之后，下一次打开（或服务恢复）会走 [_recoverDigest]。
  Future<void> checkpointNow() async {
    final residentId = _logResidentId;
    if (residentId == null) return;
    await _persistDigest(residentId);
  }

  /// 关闭实时模式：先总结写记忆，成功才清截图。
  Future<({bool ok, String error})> finishRealtime() async {
    final residentId = await controllerId();
    final shared = residentId == null
        ? const <String>[]
        : contextLog.recent(residentId);
    final hadAnything = _frames.isNotEmpty || shared.isNotEmpty;
    if (residentId == null || !hadAnything) {
      _clearFrames();
      if (residentId != null) {
        contextLog.clear(residentId);
        await settings.clearDigest(residentId);
      }
      return (ok: true, error: '');
    }
    await _persistDigest(residentId);

    final before = DateTime.now();
    try {
      // 关闭时不再重新附帧：这段时间的画面和它说过的话已经在上下文里，
      // 这里只负责说一句“结束了，去记下来”。
      await wake.wake(
        residentId,
        trigger: WakeTrigger.pet,
        pet: PetObservation(
          note:
              '这段桌宠观察结束了。这段时间你一直看着屏幕，'
              '以下是看到的和你说过的话：\n'
              '${shared.isEmpty ? '（没有更多细节）' : shared.join('\n')}\n'
              '把真正值得记的整理成一条简短记忆，用 memory_write 写下来。'
              '不要写成日记，也不要提“截图”；如果画面里有你自己，'
              '那是你，不要当成别人。',
          realtime: true,
          sessionStartedAt: _sessionStartedAt[residentId],
          lastWakeAt: _lastWakeAt[residentId],
          handoff: true,
        ),
      );
    } catch (error) {
      return (ok: false, error: '$error');
    }

    // 工具调用的结果不直接回传，所以用“有没有新记忆”判断写没写成功。
    final recent = await memories.recent(residentId, limit: 1);
    final wrote = recent.isNotEmpty && !recent.first.createdAt.isBefore(before);
    if (!wrote) {
      return (ok: false, error: '住民没有写成记忆，截图先留着，可以再试一次');
    }
    _clearFrames();
    contextLog.clear(residentId);
    await settings.clearDigest(residentId);
    _wakesSinceCheckpoint = 0;
    _lastWakeAt.remove(residentId);
    _setStatus(wake: '观察结束，记忆已写入');
    return (ok: true, error: '');
  }

  void _clearFrames() {
    for (final frame in _frames) {
      _deleteFile(frame.path);
    }
    _frames.clear();
  }

  /// 实时模式关掉、桌宠停掉时，把临时图也收干净。
  Future<void> purge() async {
    _timer?.cancel();
    _timer = null;
    _shiftTimer?.cancel();
    _shiftTimer = null;
    _clearFrames();
    contextLog.clearAll();
    _sessionStartedAt.clear();
    _lastWakeAt.clear();
    _handoffPending.clear();
    _wakesSinceCheckpoint = 0;
    _captureWaiting = false;
    await _endLogSession();
    await wakeLogs.finishAllPetLogs();
  }

  static void _deleteFile(String path) {
    try {
      // 异步删：实时模式每收到一帧都可能触发一次清理，
      // 同步 IO 会把主线程拖住。
      File(path).delete().ignore();
    } catch (_) {
      // 系统缓存目录迟早会清，删不掉不阻塞。
    }
  }

  static String _short(String text) {
    final clean = text.trim();
    return clean.length <= 24 ? clean : '${clean.substring(0, 24)}…';
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}';

  static String _ago(DateTime at, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(at);
    if (diff.inSeconds <= 1) return '刚刚';
    return '${_durationLabel(diff)}前';
  }

  static String _durationLabel(Duration diff) {
    if (diff.inSeconds < 60) return '${diff.inSeconds} 秒';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟';
    return '${diff.inHours} 小时';
  }
}

final petObserveServiceProvider = Provider<PetObserveService>(
  (ref) => PetObserveService(
    native: ref.watch(petNativeProvider),
    wake: ref.watch(residentWakeServiceProvider),
    settings: ref.watch(petSettingsRepositoryProvider),
    residents: ref.watch(customResidentRepositoryProvider),
    memories: ref.watch(residentMemoryRepositoryProvider),
    photos: ref.watch(photoDescriberProvider),
    gateway: ref.watch(modelGatewayProvider),
    wakeLogs: ref.watch(residentWakeLogRepositoryProvider),
    contextLog: ref.watch(residentContextLogProvider),
  ),
);
