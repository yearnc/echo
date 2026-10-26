import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/model_config.dart';
import '../models/resident_voice.dart';
import '../models/voice_settings.dart';
import 'model_gateway.dart';
import 'voice_settings_controller.dart';

/// 固定住民的音色怎么定下来。
///
/// 两条路：
/// - **文字描述**：本机 AISHELL-3 只有固定说话人，所以这里做稳定的
///   关键词映射（男/女 → 对应声池 → 按描述散列）；云端则挑一个预设音色。
/// - **参考音频**：只有硅基流动 CosyVoice2 支持，上传后拿到
///   `speech:...` URI，之后合成时当成 `voice` 用。
///
/// 真正“按描述创造新声音”的模型现在没接；这里不假装能做到。
class ResidentVoiceProfileService {
  const ResidentVoiceProfileService({
    required this.gateway,
    this.readSource,
  });

  final ModelGateway gateway;

  /// 用户选的是本机还是云端。文字描述按它决定落哪一边。
  final VoiceSource Function()? readSource;

  Future<ModelConfig?> activeTts() async {
    try {
      return await gateway.activeConfig(kind: ModelKind.tts);
    } catch (_) {
      return null;
    }
  }

  /// 当前云端 TTS 能不能吃参考音频。
  bool supportsClone(ModelConfig? config) {
    if (config == null) return false;
    return config.baseUrl.contains('siliconflow');
  }

  /// 用文字描述定一个音色，返回 `local:<sid>` 或 `cloud:<voice>`。
  Future<String> fromDescription(String description) async {
    final text = description.trim();
    final config = await activeTts();
    if (config != null && readSource?.call() == VoiceSource.cloud) {
      return 'cloud:${_pickCloudVoice(text, config.baseUrl)}';
    }
    final sid = ResidentVoice.sidForDescription(text);
    return 'local:$sid';
  }

  /// 上传参考音频克隆音色，返回 `cloud:speech:...`。
  Future<String> cloneFromSample({
    required Uint8List audio,
    required String text,
    required String customName,
    String mime = 'audio/mpeg',
  }) async {
    final config = await activeTts();
    if (!supportsClone(config)) {
      throw StateError('当前语音服务不支持参考音频克隆');
    }
    final uri = await gateway.cloneVoice(
      config: config!,
      audio: audio,
      text: text.trim(),
      customName: customName.trim().isEmpty ? 'resident' : customName.trim(),
      mime: mime,
    );
    return 'cloud:$uri';
  }

  /// 描述里明确是男声、且没有女性关键词时，才走男声池。
  static bool _soundsMale(String text) {
    final male = RegExp(r'男|大叔|磁性|低沉|醇厚|浑厚|青年音|少年音').hasMatch(text);
    final female = RegExp(
      r'女|少女|御姐|萝莉|甜|软糯|清亮|细腻|温柔',
    ).hasMatch(text);
    return male && !female;
  }

  static String _pickCloudVoice(String description, String baseUrl) {
    final female = !_soundsMale(description);
    final slow = description.contains('慢') || description.contains('慵懒');
    if (baseUrl.contains('siliconflow')) {
      if (female) return slow ? 'bella' : 'anna';
      return slow ? 'benjamin' : 'alex';
    }
    if (baseUrl.contains('openai')) {
      if (female) return slow ? 'shimmer' : 'nova';
      return slow ? 'echo' : 'onyx';
    }
    return female ? 'nova' : 'onyx';
  }
}

final residentVoiceProfileServiceProvider =
    Provider<ResidentVoiceProfileService>(
      (ref) => ResidentVoiceProfileService(
        gateway: ref.watch(modelGatewayProvider),
        readSource: () =>
            ref.read(voiceSettingsControllerProvider).source,
      ),
    );
