import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/custom_resident.dart';
import '../models/model_config.dart';
import '../models/resident_voice.dart';
import '../models/voice_settings.dart';
import 'model_gateway.dart';
import 'voice_settings_controller.dart';

/// 固定住民的音色怎么定下来。
///
/// 四种方式（v41）各自要靠模型能力：
/// - **文字描述**：本机 vits-zh-ll 做稳定映射；云端 OpenAI 走 `instructions`。
/// - **仅参考音频**：需要服务商支持“不带文字”的注册，目前没有接入。
/// - **参考音频 + 文字描述**：需要服务商两者都吃，目前没有接入。
/// - **参考音频 + 转录文本**：本机 ZipVoice；云端硅基流动 CosyVoice2 的注册接口。
///
/// 不支持的选项在编辑页会置灰——不假装能做到，也不让用户配完才发现报错。
class ResidentVoiceProfileService {
  const ResidentVoiceProfileService({
    required this.gateway,
    this.readSource,
  });

  final ModelGateway? gateway;

  /// 用户选的是本机还是云端。文字描述按它决定落哪一边。
  final VoiceSource Function()? readSource;

  Future<ModelConfig?> activeTts() async {
    final client = gateway;
    if (client == null) return null;
    try {
      return await client.activeConfig(kind: ModelKind.tts);
    } catch (_) {
      return null;
    }
  }

  /// 当前云端 TTS 能不能吃参考音频（本机 ZipVoice 不算在这里）。
  bool supportsClone(ModelConfig? config) {
    if (config == null) return false;
    return config.baseUrl.contains('siliconflow');
  }

  /// 这条 TTS 配置支持哪几种音色方式。
  ///
  /// 本机永远有两套：文字描述（vits-zh-ll）和参考音频 + 逐字稿（ZipVoice）。
  /// 云端再按模型能力追加——所以“仅文字描述”和“参考音频 + 转录文本”
  /// 不会再因为没配云端而消失。
  List<ResidentVoiceMode> modesFor(
    ModelConfig? config, {
    VoiceSource? source,
  }) {
    final useCloud =
        config != null && (source ?? readSource?.call()) == VoiceSource.cloud;

    final modes = <ResidentVoiceMode>[
      ResidentVoiceMode.description,
      // 本机 ZipVoice 已经随包内置，所以这一项不依赖云端。
      ResidentVoiceMode.referenceTranscript,
      if (useCloud) ...[
        if (config.ttsVoiceDescription) ResidentVoiceMode.cloudDescription,
        if (config.ttsReferenceOnly) ResidentVoiceMode.referenceOnly,
        if (config.ttsReferenceDescription)
          ResidentVoiceMode.referenceDescription,
      ],
    ];
    return modes.toSet().toList(growable: false);
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

  /// 按住民选的方式把 `voiceRef` 定下来。
  ///
  /// `description` 每次都重新算（描述改了就换声）；参考音频类沿用已生成的
  /// `voiceRef`，没有就现场注册一次。
  Future<String> resolve(CustomResident resident) async {
    if (!resident.voiceEnabled) return '';
    switch (resident.voiceMode) {
      case ResidentVoiceMode.description:
        final sid = ResidentVoice.localSidOf(resident.voiceRef) ??
            ResidentVoice.sidFor(resident.id);
        return 'local:$sid';
      case ResidentVoiceMode.cloudDescription:
        return fromDescription(resident.voiceDescription);
      case ResidentVoiceMode.referenceTranscript:
        if (resident.voiceRef.trim().isNotEmpty) return resident.voiceRef.trim();
        if (resident.voiceSamplePath.trim().isNotEmpty &&
            resident.voiceSampleText.trim().isNotEmpty) {
          // 本机 ZipVoice 不需要先向服务商注册，只要有音频和逐字稿。
          return 'local:zipvoice';
        }
        throw StateError('还没有参考音频或转录文本');
      case ResidentVoiceMode.referenceOnly:
        throw StateError('当前语音服务不支持“只给参考音频”');
      case ResidentVoiceMode.referenceDescription:
        throw StateError('当前语音服务不支持“参考音频 + 文字描述”');
    }
  }

  /// 上传参考音频注册音色，返回 `cloud:...`。
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
    final client = gateway;
    if (client == null) {
      throw StateError('还没有配置语音服务');
    }
    final uri = await client.cloneVoice(
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
