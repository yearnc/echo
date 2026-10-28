import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'speech_runtime.dart';

/// 本机语音识别的后台 isolate（v4.0）。
///
/// 和 TTS 一样：模型加载与 FFI 解码都放后台，界面只等结果。
/// 区别是识别空闲时会主动释放引擎——SenseVoice 占的内存不小，
/// 不用的时候不该一直压在进程里和语音合成抢。
class AsrWorker {
  AsrWorker._();

  static final AsrWorker instance = AsrWorker._();

  ReceivePort? _inbox;
  SendPort? _toWorker;
  Future<void>? _starting;
  int _nextId = 0;
  final Map<int, Completer<AsrReply>> _pending = {};

  Future<AsrReply> transcribe({
    required Float32List samples,
    required int sampleRate,
    required Map<String, String> files,
    String? libraryPath,
  }) async {
    await _ensureStarted();
    final id = _nextId++;
    final completer = Completer<AsrReply>();
    _pending[id] = completer;
    _toWorker!.send({
      'id': id,
      'samples': samples,
      'sampleRate': sampleRate,
      'files': files,
      'libraryPath': libraryPath,
    });

    try {
      return await completer.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => const AsrReply(text: '', error: '识别超时'),
      );
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> _ensureStarted() {
    if (_toWorker != null) return Future.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    final inbox = ReceivePort();
    _inbox = inbox;
    final ready = Completer<void>();

    inbox.listen((message) {
      if (message is SendPort) {
        _toWorker = message;
        if (!ready.isCompleted) ready.complete();
        return;
      }
      if (message is! Map) return;
      final id = message['id'];
      if (id is! int) return;
      final completer = _pending[id];
      if (completer == null || completer.isCompleted) return;
      completer.complete(
        AsrReply(
          text: (message['text'] as String?) ?? '',
          error: (message['error'] as String?) ?? '',
        ),
      );
    });

    try {
      await Isolate.spawn(
        _asrWorkerMain,
        inbox.sendPort,
        debugName: 'echo-asr',
        errorsAreFatal: true,
      );
      await ready.future.timeout(const Duration(seconds: 10));
    } on Object catch (error) {
      _starting = null;
      _toWorker = null;
      _inbox?.close();
      _inbox = null;
      throw StateError('识别后台线程起不来：$error');
    }
  }
}

class AsrReply {
  const AsrReply({required this.text, required this.error});

  final String text;
  final String error;

  bool get ok => error.isEmpty;
}

/// worker isolate 的入口。不要碰任何 Flutter 插件。
@pragma('vm:entry-point')
void _asrWorkerMain(SendPort mainPort) {
  final inbox = ReceivePort();
  mainPort.send(inbox.sendPort);

  sherpa.OfflineRecognizer? engine;
  Map<String, String>? engineFiles;
  Timer? idle;

  void release() {
    engine?.free();
    engine = null;
    engineFiles = null;
  }

  Future<void> handle(Map<Object?, Object?> message) async {
    final id = message['id'];
    if (id is! int) return;
    final samples = message['samples'];
    final sampleRate = message['sampleRate'];
    final files = <String, String>{
      for (final entry in ((message['files'] as Map?) ?? const {}).entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
    final libraryPath = message['libraryPath'] as String?;

    try {
      if (samples is! Float32List || sampleRate is! int || sampleRate <= 0) {
        throw StateError('录音数据不完整');
      }
      SpeechRuntime.ensure(libraryPath);
      if (engine == null || !_sameFiles(engineFiles, files)) {
        release();
        engine = _buildEngine(files);
        engineFiles = files;
      }

      final stream = engine!.createStream();
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      engine!.decode(stream);
      final text = engine!.getResult(stream).text.trim();
      stream.free();

      mainPort.send({'id': id, 'text': text});
    } on Object catch (error) {
      release();
      mainPort.send({'id': id, 'error': '$error'});
    } finally {
      idle?.cancel();
      idle = Timer(const Duration(minutes: 5), release);
    }
  }

  inbox.listen((message) {
    if (message is Map) unawaited(handle(message));
  });
}

bool _sameFiles(Map<String, String>? a, Map<String, String> b) {
  if (a == null || a.length != b.length) return false;
  for (final entry in b.entries) {
    if (a[entry.key] != entry.value) return false;
  }
  return true;
}

sherpa.OfflineRecognizer _buildEngine(Map<String, String> files) {
  String path(String name) {
    final value = files[name];
    if (value == null || value.isEmpty) {
      throw StateError('缺少识别模型文件：$name');
    }
    return value;
  }

  return sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        senseVoice: sherpa.OfflineSenseVoiceModelConfig(
          model: path('model'),
          // auto：中英日韩粤都可能混着说，让模型自己判断。
          language: 'auto',
          useInverseTextNormalization: true,
        ),
        tokens: path('tokens'),
        // 识别和合成一样吃 CPU；两个线程够用，再多会跟界面抢。
        numThreads: 2,
        debug: false,
      ),
    ),
  );
}
