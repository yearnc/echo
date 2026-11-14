import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/model_config_repository.dart';
import 'asr_worker.dart';
import 'model_call_common.dart';
import 'speech_models.dart';
import 'speech_runtime.dart';
import 'wav_pcm.dart';

/// 语音识别（v4.0 本机 / v4.12 云端兜底）。
///
/// 默认整条路不联网：录音 → wav → 采样 → 离线识别。只有用户自己在设置里
/// 打开「语音识别用云端」后，本机模型缺失或识别失败时才会把音频发给
/// DeepSeek 的 `/v1/tools/asr`。
class AsrService {
  AsrService({
    SpeechModelStore? store,
    this.db,
    this.configs,
    Dio? dio,
  }) : _store = store ?? SpeechModelStore(),
       _dio = dio ?? Dio();

  final SpeechModelStore _store;
  final AppDatabase? db;
  final ModelConfigRepository? configs;
  final Dio _dio;

  /// 云端识别开关（默认关）。key 存在 app_settings，和别的设置一样。
  static const String cloudKey = 'asr.cloud.enabled';

  /// DeepSeek ASR 的限制：8 MiB / 120 秒。超过就不发，免得白跑一趟。
  static const int cloudMaxBytes = 8 * 1024 * 1024;
  static const int cloudMaxMs = 120 * 1000;

  Future<bool> cloudEnabled() async {
    final database = db;
    if (database == null) return false;
    final row =
        await (database.select(database.appSettings)
              ..where((t) => t.key.equals(cloudKey)))
            .getSingleOrNull();
    return row?.value == 'true';
  }

  Future<void> setCloudEnabled(bool value) async {
    final database = db;
    if (database == null) return;
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: cloudKey,
            value: value ? 'true' : 'false',
          ),
        );
  }

  /// 识别一段 wav。先本机，失败且用户开了云端时再走 DeepSeek。
  ///
  /// 失败时抛异常，调用方把原因告诉用户。
  Future<AsrResult> transcribeWav(String wavPath) async {
    final bytes = await File(wavPath).readAsBytes();
    final pcm = WavPcm.tryParse(bytes);
    if (pcm == null) {
      throw StateError('这段录音读不出来，换个格式或重录一次');
    }
    if (pcm.samples.length < 16000 * 0.3) {
      throw StateError('录音太短了，再说一句吧');
    }

    Object? localError;
    try {
      return await _transcribeLocal(pcm);
    } catch (error) {
      localError = error;
    }

    if (await cloudEnabled()) {
      try {
        return await _transcribeCloud(bytes, pcm);
      } catch (cloudError) {
        // 两条路都失败时，优先把本机的原因交给用户：
        // 多数情况下是“模型没下载”，比服务商的网络错误更可操作。
        throw StateError(
          '本机没识别出来（$localError），云端也没成功（$cloudError）',
        );
      }
    }
    if (localError is StateError) throw localError;
    throw StateError('$localError');
  }

  Future<AsrResult> _transcribeLocal(WavPcm pcm) async {
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

  Future<AsrResult> _transcribeCloud(
    List<int> bytes,
    WavPcm pcm,
  ) async {
    if (bytes.length > cloudMaxBytes) {
      throw StateError('录音超过 8MB，云端不收；换一段短一点的');
    }
    final duration = _durationMs(pcm);
    if (duration > cloudMaxMs) {
      throw StateError('录音超过 120 秒，云端不收；换一段短一点的');
    }
    final repo = configs;
    if (repo == null) {
      throw StateError('没有可用的 DeepSeek 配置，打不开云端识别');
    }
    final config = await repo.firstUsableDeepSeek();
    if (config == null) {
      throw StateError('没有可用的 DeepSeek 配置，打不开云端识别');
    }
    final key = (await repo.readKey(config.id))?.trim() ?? '';
    if (key.isEmpty) throw StateError('DeepSeek 的密钥是空的');

    final response = await _dio.post<Map<String, dynamic>>(
      deepSeekToolsEndpoint(config.baseUrl, 'asr'),
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: 'speech.wav'),
      }),
      options: Options(
        headers: {'Authorization': 'Bearer $key'},
        sendTimeout: const Duration(seconds: 90),
        receiveTimeout: const Duration(seconds: 90),
      ),
    );

    final payload = response.data ?? const <String, dynamic>{};
    final text = payload['text'];
    if (text is! String || text.trim().isEmpty) {
      throw StateError('云端没听清，再说一遍试试');
    }
    final serverMs = payload['duration_ms'];
    return AsrResult(
      text: text.trim(),
      durationMs: serverMs is num ? serverMs.toInt() : duration,
    );
  }

  static int _durationMs(WavPcm pcm) =>
      (pcm.samples.length / pcm.sampleRate * 1000).round();
}

class AsrResult {
  const AsrResult({required this.text, required this.durationMs});

  final String text;
  final int durationMs;
}

final asrServiceProvider = Provider<AsrService>(
  (ref) => AsrService(
    db: ref.watch(databaseProvider),
    configs: ref.watch(modelConfigRepositoryProvider),
  ),
);
