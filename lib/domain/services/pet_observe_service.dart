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
/// 实时模式：原生侧按 0.5/1 秒连续抓图，这里每 15 秒取最近几帧唤醒一次；
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
  });

  final PetNative native;
  final ResidentWakeService wake;
  final PetSettingsRepository settings;
  final CustomResidentRepository residents;
  final ResidentMemoryRepository memories;
  final PhotoDescriber photos;
  final ModelGateway gateway;
  final ResidentWakeLogRepository wakeLogs;

  /// 当前这段“桌宠醒着”的日志属于谁；换控制者时先收尾再开新的。
  String? _logResidentId;

  final Random _random = Random();
  StreamSubscription<Map<String, Object?>>? _subscription;
  Timer? _timer;
  bool _busy = false;
  bool _captureWaiting = false;
  final List<_PetFrame> _frames = [];

  /// 这段观察的上下文：每轮看到的画面和它自己说过的话。
  /// 关闭时只把这段交给它去写记忆，不再重新附最后两张图。
  final List<String> _history = [];
  static const int maxHistoryLines = 10;

  /// 给桌宠页看的状态（收到几帧、上次唤醒结果、错误）。
  final ValueNotifier<PetObserveStatus> status =
      ValueNotifier(const PetObserveStatus());

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
  /// 按最长 120 秒、0.5 秒一张估算，留得下整个唤醒窗口。
  static const int maxFrames = 240;

  /// 桌宠自己的参照图：截图会把它截进去，模型得知道那是谁。
  static const String selfImageRef = 'asset:assets/pet_frames/idle_00.png';

  /// 每次唤醒附几张、隔多久唤醒一次，都由用户在桌宠页选。
  int _framesPerWake = 3;
  Duration _gap = const Duration(seconds: 20);

  void attach() {
    _subscription ??= native.events.listen(_onEvent);
  }

  Future<void> detach() async {
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    _clearFrames();
    _history.clear();
    status.value = const PetObserveStatus();
    await _endLogSession();
  }

  /// 设置变了：重排计时器；实时模式交给原生连续抓图。
  Future<void> sync(PetSettings value) async {
    _timer?.cancel();
    _timer = null;
    if (!value.enabled) return;
    // 先把“醒着”的日志建立起来：时长从桌宠打开算，不是从第一次截图算。
    await controllerId();
    if (value.realtime) {
      _framesPerWake = value.realtimeFrames.clamp(1, 6);
      _gap = Duration(seconds: value.realtimeGapSeconds.clamp(5, 120));
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
    final value = await settings.load();
    final candidate = await settings.controllerAt(
      DateTime.now(),
      fallbackResidentId: value.defaultResidentId,
    );
    String? result;
    if (candidate == null) {
      result = null;
    } else if (!CallRegistry.isActive(candidate)) {
      result = candidate;
    } else {
      // 正在通话的住民不接管桌宠：控制时段先让给通话，
      // 等通话结束后的下一次观察再由它接手。
      final fallback = value.defaultResidentId;
      result = fallback.isNotEmpty &&
              fallback != candidate &&
              !CallRegistry.isActive(fallback)
          ? fallback
          : null;
    }
    await _ensureLogSession(result);
    return result;
  }

  /// 桌宠的“醒着”是一段连续日志：控制者变了就先收尾旧的、再开新的；
  /// 暂时无人（通话中）就收尾，等有人接手再开。
  Future<void> _ensureLogSession(String? residentId) async {
    if (residentId == _logResidentId) return;
    await _endLogSession();
    _logResidentId = residentId;
    if (residentId == null) return;
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
    if (_busy) return;
    _busy = true;
    try {
      final residentId = await controllerId();
      if (residentId == null) return;
      final resident = await residents.findById(residentId);
      if (resident == null) return;
      final config =
          await gateway.configFor(configId: resident.modelConfigId) ??
          await gateway.activeConfig();
      final canSee = config?.supportsVision ?? false;

      final description = await photos.describe(ref);
      final note = description.isEmpty
          ? '画面已经附在后面；如果你看不懂图，就说没看清。'
          : '画面：$description';
      // 普通模式只留这一张，看完就删；不把一整天都存成图库。
      await wake.wake(
        residentId,
        trigger: WakeTrigger.pet,
        pet: PetObservation(
          images: canSee ? [ref] : const [],
          note: note,
          selfImage: canSee ? selfImageRef : null,
        ),
      );
      _deleteFile(ref.replaceFirst('file:', ''));
      // 普通模式每轮都是独立的一眼，不跨轮累积。
      _history.clear();
      _setStatus(wakeAt: DateTime.now(), wake: '普通模式点评完成');
    } catch (error) {
      debugPrint('[桌宠] 这次观察没成：$error');
      _setStatus(error: '$error');
    } finally {
      _busy = false;
    }
  }

  /// 按时间均匀挑 [count] 帧，首尾都包含。
  List<_PetFrame> _pickFrames(int count) {
    if (_frames.isEmpty) return const [];
    final wanted = count.clamp(1, 6);
    if (_frames.length <= wanted) return List<_PetFrame>.of(_frames);
    if (wanted == 1) return [_frames.last];
    return [
      for (var i = 0; i < wanted; i++)
        _frames[((_frames.length - 1) * i / (wanted - 1)).round()],
    ];
  }

  Future<void> _observeRealtime() async {
    if (_busy) return;
    // 从整个唤醒窗口里均匀抽，而不是只拿最后几张：
    // 1 秒一张、20 秒唤醒一次时，前面那些帧也该被看到。
    final recent = _pickFrames(_framesPerWake);
    if (recent.isEmpty) return;

    _busy = true;
    try {
      final residentId = await controllerId();
      if (residentId == null) return;
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
      final note = [
        '这是过去 ${_gap.inSeconds} 秒里均匀抽出的 ${recent.length} 帧'
            '（${_clock(recent.first.at)}—${_clock(recent.last.at)}）。',
        if (description.isNotEmpty) '最后一张的画面：$description',
        if (_history.isNotEmpty)
          '这段时间此前的观察和你说过的话：\n${_history.join('\n')}',
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
        ),
      );
      debugPrint(
        '[桌宠] 实时观察：${recent.length} 帧，控制者 $residentId，'
        '唤醒结果 $handled',
      );
      final said = wake.takePetSaid(residentId);
      final line = StringBuffer()
        ..write('${_clock(recent.first.at)}—${_clock(recent.last.at)}：')
        ..write(description.isEmpty ? '看了屏幕' : description)
        ..write(
          said == null || said.trim().isEmpty ? '' : '；你说：「${said.trim()}」',
        );
      _history.add(line.toString());
      while (_history.length > maxHistoryLines) {
        _history.removeAt(0);
      }
      _setStatus(
        wakeAt: DateTime.now(),
        wake: '唤醒 $handled（${recent.length} 帧）',
        error: '',
      );
    } catch (error) {
      debugPrint('[桌宠] 实时观察没成：$error');
      _setStatus(error: '$error');
    } finally {
      _busy = false;
    }
  }

  /// 关闭实时模式：先总结写记忆，成功才清截图。
  Future<({bool ok, String error})> finishRealtime() async {
    final residentId = await controllerId();
    final hadAnything = _frames.isNotEmpty || _history.isNotEmpty;
    if (residentId == null || !hadAnything) {
      _clearFrames();
      _history.clear();
      return (ok: true, error: '');
    }

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
              '${_history.isEmpty ? '（没有更多细节）' : _history.join('\n')}\n'
              '把真正值得记的整理成一条简短记忆，用 memory_write 写下来。'
              '不要写成日记，也不要提“截图”；如果画面里有你自己，'
              '那是你，不要当成别人。',
          realtime: true,
        ),
      );
    } catch (error) {
      return (ok: false, error: '$error');
    }

    // 工具调用的结果不直接回传，所以用“有没有新记忆”判断写没写成功。
    final recent = await memories.recent(residentId, limit: 1);
    final wrote =
        recent.isNotEmpty && !recent.first.createdAt.isBefore(before);
    if (!wrote) {
      return (ok: false, error: '住民没有写成记忆，截图先留着，可以再试一次');
    }
    _clearFrames();
    _history.clear();
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
    _clearFrames();
    _history.clear();
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
  ),
);
