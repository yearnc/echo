import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'asr_worker.dart';
import 'speech_models.dart';
import 'speech_runtime.dart';
import 'wav_pcm.dart';

/// 本机语音识别（v4.0）。
///
/// 录音 → wav → 采样 → 离线识别。整条路不联网，语音本身不会被发到
/// 任何服务商；发出去的只有识别出来的文字（和以前打字一样）。
class AsrService {
  AsrService({SpeechModelStore? store})
    : _store = store ?? SpeechModelStore();

  final SpeechModelStore _store;

  /// 识别一段 wav。失败时抛异常，调用方把原因告诉用户。
  Future<AsrResult> transcribeWav(String wavPath) async {
    final bytes = await File(wavPath).readAsBytes();
    final pcm = WavPcm.tryParse(bytes);
    if (pcm == null) {
      throw StateError('这段录音读不出来，换个格式或重录一次');
    }
    if (pcm.samples.length < 16000 * 0.3) {
      throw StateError('录音太短了，再说一句吧');
    }

    final models = await _store.prepareAsr();
    final reply = await AsrWorker.instance.transcribe(
      samples: pcm.samples,
      sampleRate: pcm.sampleRate,
      files: {
        'model': models.pathOf('model.int8.onnx'),
        'tokens': models.pathOf('tokens.txt'),
      },
      libraryPath: SpeechRuntime.resolveLibraryPath(),
    );
    if (!reply.ok) throw StateError(reply.error);

    final text = reply.text.trim();
    if (text.isEmpty) {
      throw StateError('没听清，再说一遍试试');
    }
    return AsrResult(text: text, durationMs: _durationMs(pcm));
  }

  static int _durationMs(WavPcm pcm) =>
      (pcm.samples.length / pcm.sampleRate * 1000).round();
}

class AsrResult {
  const AsrResult({required this.text, required this.durationMs});

  final String text;
  final int durationMs;
}

final asrServiceProvider = Provider<AsrService>((ref) => AsrService());
