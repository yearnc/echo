import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'speech_models.dart';
import 'speech_runtime.dart';

/// 把一段录音转成文字（B8）。
///
/// 用随包发布的中文离线模型，不联网、不上传——用户对着麦克风说的话
/// 一个字都不离开这台设备。这一点比识别率高几个点重要得多。
///
/// 拿不到模型时一律返回 null：语音输入那个入口干脆不出现，
/// 键盘打字照常（见 `VoiceInputButton`）。
class AsrService {
  AsrService({SpeechModelStore? store}) : _store = store ?? SpeechModelStore();

  final SpeechModelStore _store;

  sherpa.OfflineRecognizer? _recognizer;
  bool _unavailable = false;

  Future<sherpa.OfflineRecognizer?> _ensureRecognizer() async {
    if (_unavailable) return null;
    if (_recognizer != null) return _recognizer;

    try {
      SpeechRuntime.ensure();
      final models = await _store.prepareAsr();
      _recognizer = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            paraformer: sherpa.OfflineParaformerModelConfig(
              model: models.pathOf('model.int8.onnx'),
            ),
            tokens: models.pathOf('tokens.txt'),
            numThreads: 2,
            debug: false,
          ),
        ),
      );
      return _recognizer;
    } catch (error) {
      _unavailable = true;
      debugPrint('[语音] 识别引擎起不来，语音输入不可用：$error');
      return null;
    }
  }

  /// 识别一个 wav 文件（16k / 单声道 / 16 位，录音那一步就是这个格式）。
  ///
  /// 返回空串表示"听到了但没听清"，返回 null 表示这条路径整个不可用——
  /// 两者在界面上给的话不一样，所以分开。
  Future<String?> transcribe(String filePath) async {
    final recognizer = await _ensureRecognizer();
    if (recognizer == null) return null;

    sherpa.OfflineStream? stream;
    try {
      final wave = sherpa.readWave(filePath);
      if (wave.samples.isEmpty || wave.sampleRate <= 0) return '';

      stream = recognizer.createStream();
      stream.acceptWaveform(
        samples: wave.samples,
        sampleRate: wave.sampleRate,
      );
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } catch (error) {
      debugPrint('[语音] 这段没听出来：$error');
      return '';
    } finally {
      stream?.free();
    }
  }
}

final asrServiceProvider = Provider<AsrService>(
  (ref) => AsrService(store: ref.watch(speechModelStoreProvider)),
);
