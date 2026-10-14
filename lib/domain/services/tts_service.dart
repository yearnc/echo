import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../data/media/media_service.dart';
import '../models/resident_voice.dart';
import 'speech_models.dart';
import 'speech_runtime.dart';
import 'voice_waveform.dart';

/// 合成好的一条语音。
class VoiceClip {
  const VoiceClip({
    required this.ref,
    required this.transcript,
    required this.durationMs,
    required this.waveform,
  });

  /// `file:` 引用，跟图片、头像同一套约定。
  final String ref;

  /// 转写稿。语音条下面那行字就是它——用户不开声音也知道说了什么。
  final String transcript;

  final int durationMs;

  /// 波形柱子（0—1，[VoiceWaveform.defaultBars] 根）。
  final List<double> waveform;
}

/// 住民说话的嗓子：本机离线合成（B8）。
///
/// 用的是随包发布的 AISHELL-3 多说话人模型，不联网、不花钱，
/// 而且**合成完就把 wav 落盘**——这样飞行模式下已经收到的语音照样能播，
/// 那是这一里程碑的验收条件之一。
///
/// 拿不到模型（比如开发者没按说明放模型文件）时一律返回 null，
/// 调用方保持纯文本，不报错、不阻塞——社区的正常运转不该被一个语音功能拖住。
class TtsService {
  TtsService({SpeechModelStore? store, this.media = const MediaService()})
    : _store = store ?? SpeechModelStore();

  final SpeechModelStore _store;
  final MediaService media;

  sherpa.OfflineTts? _engine;
  bool _unavailable = false;

  /// 一句话最多合成这么多字。
  ///
  /// 语音评论本来就不长（住在评论区里，用户要等它放完），
  /// 超过这个长度的一律退回文字——一分钟的语音条没人会听。
  static const int maxTranscriptLength = 120;

  Future<sherpa.OfflineTts?> _ensureEngine() async {
    if (_unavailable) return null;
    if (_engine != null) return _engine;

    try {
      SpeechRuntime.ensure();
      final models = await _store.prepareTts();
      _engine = sherpa.OfflineTts(
        sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(
            vits: sherpa.OfflineTtsVitsModelConfig(
              model: models.pathOf('model.onnx'),
              lexicon: models.pathOf('lexicon.txt'),
              tokens: models.pathOf('tokens.txt'),
            ),
            // 合成是纯 CPU 活，两个线程够用：再多会跟 UI 抢，
            // 而这条路径本来就不该让人等太久。
            numThreads: 2,
            debug: false,
          ),
        ),
      );
      return _engine;
    } catch (error) {
      // 记一次就够，不必每条评论都试一遍引擎。
      _unavailable = true;
      debugPrint('[语音] 合成引擎起不来，本次运行只发文字：$error');
      return null;
    }
  }

  /// 把一句话合成成语音条。失败或不可用时返回 null。
  Future<VoiceClip?> speak({
    required String text,
    required String personaId,
    String voiceModel = '',
  }) async {
    final transcript = _clean(text);
    if (transcript.isEmpty) return null;

    // 用户的帖子里会出现话题标签、@、"哈哈哈哈哈"这类东西，
    // 念出来很奇怪；能读出人话才合成，读不出来就退回文字。
    if (!_worthSpeaking(transcript)) return null;

    final engine = await _ensureEngine();
    if (engine == null) return null;

    try {
      final audio = engine.generate(
        text: transcript,
        sid: ResidentVoice.sidFor(personaId, voiceModel: voiceModel),
        speed: ResidentVoice.speedFor(voiceModel),
      );
      if (audio.samples.isEmpty || audio.sampleRate <= 0) return null;

      final file = await media.newVoiceFile();
      final written = sherpa.writeWave(
        filename: file.path,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );
      if (!written) return null;

      return VoiceClip(
        ref: 'file:${file.path}',
        transcript: transcript,
        durationMs: VoiceWaveform.durationMs(
          audio.samples.length,
          audio.sampleRate,
        ),
        waveform: VoiceWaveform.bars(audio.samples),
      );
    } catch (error) {
      debugPrint('[语音] 这句没合成出来，退回文字：$error');
      return null;
    }
  }

  /// 合成前的清理：一行、不带话题标签、不超过长度上限。
  static String _clean(String text) {
    var cleaned = text
        .replaceAll(RegExp(r'#([^#]{1,20})#'), r'$1')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.length > maxTranscriptLength) {
      cleaned = cleaned.substring(0, maxTranscriptLength);
    }
    return cleaned;
  }

  /// 这句话值不值得念。
  ///
  /// 全是表情、标点或者语气词的（"哈哈哈哈"、"？"、"蹲"）合成出来只有噪音，
  /// 判断放在合成之前：白合成一次要等好几秒，而用户看到的是一个占位语音条。
  static bool _worthSpeaking(String text) {
    final meaningful = text.replaceAll(
      RegExp(r'[\s\p{P}\p{S}哈呵嘿嘻呜唉诶嗯哦噢啊呀吧呢嘛]', unicode: true),
      '',
    );
    return meaningful.length >= 2;
  }
}

final ttsServiceProvider = Provider<TtsService>(
  (ref) => TtsService(store: ref.watch(speechModelStoreProvider)),
);
