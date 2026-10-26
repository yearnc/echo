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
      final clip = await tts.speak(
        text: clean,
        personaId: resident.id,
        // `local:<sid>` / `cloud:<voice>` / `speech:...`，TtsService 自己认。
        voiceModel: resident.voiceRef,
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
