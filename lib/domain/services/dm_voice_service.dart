import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/custom_resident.dart';
import 'tts_service.dart';
import 'voice_settings_controller.dart';

/// 给固定住民合成一段语音。
///
/// 这里**只负责合成**，不替它决定成功之后怎么发。合成失败会把 null
/// 交给调用方，让模型自己决定改用文字、换句话再试，还是先解释一下。
class DmVoiceService {
  DmVoiceService({
    required this.tts,
    this.readEnabled,
  });

  final TtsService tts;

  /// 「住民语音」总开关。关掉之后历史语音照常能播，只是不再生成新的。
  final bool Function()? readEnabled;

  bool get enabled => readEnabled?.call() ?? true;

  /// 合成一句语音。失败把原因一起交回去，让模型自己决定下一步。
  Future<({VoiceClip? clip, String error})> synthesize({
    required CustomResident resident,
    required String text,
  }) async {
    if (!enabled) {
      return (clip: null, error: '语音总开关关着');
    }
    if (!resident.voiceEnabled) {
      return (clip: null, error: '这个住民没有开启语音');
    }

    final clean = text.trim();
    if (clean.isEmpty) {
      return (clip: null, error: '这句话是空的');
    }

    try {
      // 本机克隆只在本机方式、且已经选了参考音频 + 逐字稿时启用；
      // 云端克隆的 voiceRef 是 cloud:...，走云端那条路。
      final localClone =
          resident.voiceMode == ResidentVoiceMode.referenceTranscript &&
          resident.voiceSamplePath.trim().isNotEmpty &&
          resident.voiceSampleText.trim().isNotEmpty &&
          !resident.voiceRef.startsWith('cloud:');
      final clip = await tts.speak(
        text: clean,
        personaId: resident.id,
        // `local:<sid>` / `local:zipvoice` / `cloud:<voice>` / `speech:...`。
        voiceModel: resident.voiceRef,
        // 文字描述方式下，OpenAI 的 instructions 能真的按描述调语气；
        // 其他家忽略这段文本，不会出错。
        voiceDescription: resident.voiceDescription,
        wantsDescription: resident.voiceMode.usesDescription,
        referenceAudioPath: resident.voiceSamplePath,
        referenceText: resident.voiceSampleText,
        preferLocalClone: localClone,
      );
      if (clip == null) {
        return (clip: null, error: '语音服务没有返回音频');
      }
      return (clip: clip, error: '');
    } catch (error) {
      debugPrint('[私信语音] 这句没合成出来：$error');
      return (clip: null, error: '$error');
    }
  }
}

final dmVoiceServiceProvider = Provider<DmVoiceService>(
  (ref) => DmVoiceService(
    tts: ref.watch(ttsServiceProvider),
    readEnabled: () => ref.read(voiceSettingsControllerProvider).enabled,
  ),
);
