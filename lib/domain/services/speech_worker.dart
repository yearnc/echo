import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'speech_runtime.dart';
import 'voice_waveform.dart';
import 'wav_pcm.dart';

/// 本机语音合成的后台 isolate（v3.9）。
///
/// 以前 `OfflineTts.generate` 直接跑在 UI isolate 上：FFI 调用是同步的，
/// 一句三五秒的语音就会把界面钉住三五秒——调用语音功能时“卡一下”就是它。
/// 现在引擎和合成都搬进一个常驻 worker isolate，主 isolate
/// 只负责准备文件路径和发消息。
///
/// 为什么是**常驻**而不是每次 `Isolate.run`：模型加载一次要几百毫秒到几秒，
/// 每次新建等于每次重付这笔钱。worker 里同时只保留一套引擎（和原来一样），
/// 切模型时先 free 旧的，手机不会同时常驻两份大模型。
class SpeechWorker {
  SpeechWorker._();

  static final SpeechWorker instance = SpeechWorker._();

  ReceivePort? _inbox;
  SendPort? _toWorker;
  Future<void>? _starting;
  int _nextId = 0;
  final Map<int, Completer<SpeechWorkerReply>> _pending = {};

  Future<SpeechWorkerReply> synthesize(SpeechWorkerRequest request) async {
    await _ensureStarted();
    final id = _nextId++;
    final completer = Completer<SpeechWorkerReply>();
    _pending[id] = completer;
    _toWorker!.send({'id': id, ...request.toMessage()});

    try {
      return await completer.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => SpeechWorkerReply.failure('语音合成超时'),
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
        SpeechWorkerReply(
          path: (message['path'] as String?) ?? '',
          durationMs: (message['durationMs'] as int?) ?? 0,
          waveform: widgetBars(message['waveform']),
          error: (message['error'] as String?) ?? '',
        ),
      );
    });

    try {
      await Isolate.spawn(
        _speechWorkerMain,
        inbox.sendPort,
        debugName: 'echo-speech',
        // worker 真挂了也不该让主线程永远等：超时会把失败交回调用方，
        // 下一次合成会重新起一个 isolate。
        errorsAreFatal: true,
      );
      await ready.future.timeout(const Duration(seconds: 10));
    } on Object catch (error) {
      _starting = null;
      _toWorker = null;
      _inbox?.close();
      _inbox = null;
      throw StateError('语音后台线程起不来：$error');
    }
  }

  /// 把 worker 里算好的波形收回来（跨 isolate 是 List，不是 Float32List）。
  static List<double> widgetBars(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is num) item.toDouble(),
    ];
  }
}

/// 一次合成任务。路径都由主 isolate 提前准备好——
/// worker 不碰 path_provider / 资源包这些需要平台通道的东西。
class SpeechWorkerRequest {
  const SpeechWorkerRequest({
    required this.kind,
    required this.text,
    required this.outputPath,
    required this.files,
    this.sid = 0,
    this.speed = 1.0,
    this.referenceAudioPath = '',
    this.referenceText = '',
    this.libraryPath,
  });

  /// `vits` 或 `zipvoice`。
  final String kind;
  final String text;
  final String outputPath;

  /// 模型文件路径，按 worker 需要取。
  final Map<String, String> files;
  final int sid;
  final double speed;
  final String referenceAudioPath;
  final String referenceText;

  /// 能给就给：某些环境（测试 / Dart CLI）需要显式告诉 sherpa 原生库在哪。
  final String? libraryPath;

  Map<String, Object?> toMessage() => {
    'op': 'synthesize',
    'kind': kind,
    'text': text,
    'outputPath': outputPath,
    'files': files,
    'sid': sid,
    'speed': speed,
    'referenceAudioPath': referenceAudioPath,
    'referenceText': referenceText,
    'libraryPath': libraryPath,
  };
}

class SpeechWorkerReply {
  const SpeechWorkerReply({
    required this.path,
    required this.durationMs,
    required this.waveform,
    required this.error,
  });

  factory SpeechWorkerReply.failure(String error) => SpeechWorkerReply(
    path: '',
    durationMs: 0,
    waveform: const [],
    error: error,
  );

  final String path;
  final int durationMs;
  final List<double> waveform;
  final String error;

  bool get ok => error.isEmpty && path.isNotEmpty;
}

/// worker isolate 的入口。
///
/// 不要在这里调用任何 Flutter 插件：没有 `WidgetsBinding`，也没有平台通道。
/// 只用 dart:io、FFI 和纯 Dart。
@pragma('vm:entry-point')
void _speechWorkerMain(SendPort mainPort) {
  final inbox = ReceivePort();
  mainPort.send(inbox.sendPort);

  sherpa.OfflineTts? engine;
  String? engineKind;
  final unavailable = <String>{};

  Future<void> handle(Map<Object?, Object?> message) async {
    // 只处理一次合成请求；参数不合法就原样回去，主线程只当合成失败。
    final id = message['id'];
    if (id is! int) return;
    final kind = (message['kind'] as String?) ?? '';
    final text = (message['text'] as String?) ?? '';
    final outputPath = (message['outputPath'] as String?) ?? '';
    final files = <String, String>{
      for (final entry in ((message['files'] as Map?) ?? const {}).entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
    final sid = (message['sid'] as int?) ?? 0;
    final speed = (message['speed'] as num?)?.toDouble() ?? 1.0;
    final referenceAudioPath =
        (message['referenceAudioPath'] as String?) ?? '';
    final referenceText = (message['referenceText'] as String?) ?? '';
    final libraryPath = message['libraryPath'] as String?;

    try {
      if (unavailable.contains(kind)) {
        throw StateError('$kind 引擎之前没起来');
      }
      if (engine == null || engineKind != kind) {
        engine?.free();
        engine = null;
        engineKind = null;
        SpeechRuntime.ensure(libraryPath);
        engine = _buildEngine(kind, files);
        engineKind = kind;
      }

      final sherpa.GeneratedAudio audio;
      if (kind == 'zipvoice') {
        final pcm = WavPcm.tryParse(
          await File(referenceAudioPath.replaceFirst('file:', '')).readAsBytes(),
        );
        if (pcm == null) {
          throw StateError('本地克隆需要 wav 格式的参考音频');
        }
        audio = engine!.generateWithConfig(
          text: text,
          config: sherpa.OfflineTtsGenerationConfig(
            referenceAudio: pcm.samples,
            referenceSampleRate: pcm.sampleRate,
            referenceText: referenceText.trim(),
            // ZipVoice 蒸馏版推荐 4 步；再少会有明显底噪。
            numSteps: 4,
            speed: speed,
          ),
        );
      } else {
        audio = engine!.generate(text: text, sid: sid, speed: speed);
      }

      if (audio.samples.isEmpty || audio.sampleRate <= 0) {
        throw StateError('没有生成出音频');
      }
      final written = sherpa.writeWave(
        filename: outputPath,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );
      if (!written) throw StateError('语音文件没写出来');

      mainPort.send({
        'id': id,
        'path': outputPath,
        'durationMs': VoiceWaveform.durationMs(
          audio.samples.length,
          audio.sampleRate,
        ),
        'waveform': VoiceWaveform.bars(audio.samples),
      });
    } on Object catch (error) {
      // 引擎级失败只记一次：同一套模型坏了，下一条不必再花几秒重试。
      if (engine == null && kind.isNotEmpty) unavailable.add(kind);
      engine?.free();
      engine = null;
      engineKind = null;
      mainPort.send({'id': id, 'error': '$error'});
    }
  }

  inbox.listen((message) {
    if (message is Map) unawaited(handle(message));
  });
}

sherpa.OfflineTts _buildEngine(String kind, Map<String, String> files) {
  String path(String name) {
    final value = files[name];
    if (value == null || value.isEmpty) {
      throw StateError('缺少模型文件：$name');
    }
    return value;
  }

  final sherpa.OfflineTtsConfig config;
  if (kind == 'vits') {
    config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: path('model'),
          lexicon: path('lexicon'),
          tokens: path('tokens'),
        ),
        // 合成是纯 CPU 活，两个线程够用：再多会跟 UI 抢。
        numThreads: 2,
        debug: false,
      ),
      // 日期/数字/电话这类文本正则化。
      ruleFsts: [path('date'), path('number'), path('phone')].join(','),
    );
  } else if (kind == 'zipvoice') {
    config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        zipvoice: sherpa.OfflineTtsZipVoiceModelConfig(
          tokens: path('tokens'),
          encoder: path('encoder'),
          decoder: path('decoder'),
          vocoder: path('vocoder'),
          dataDir: path('dataDir'),
          lexicon: path('lexicon'),
        ),
        numThreads: 2,
        debug: false,
      ),
    );
  } else {
    throw StateError('不认识的语音模型：$kind');
  }
  return sherpa.OfflineTts(config);
}
