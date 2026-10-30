import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/model_resource.dart';

/// 模型资源的目录（v4.4）。
///
/// 内置一份清单，保证断网也能下载当前版本；同时允许从仓库里的
/// `resources/manifest.json` 拿新版本号，实现“资源增量更新”——
/// 只下载版本变了的资源，没变的继续用手机里那份。
class ResourceCatalog {
  ResourceCatalog({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// 资源 release 的固定标签。以后发新资源就改成 models-v2。
  static const String releaseTag = 'models-v1';

  static const String remoteManifestUrl =
      'https://raw.githubusercontent.com/yearnc/echo/main/resources/manifest.json';

  static String _assetUrl(String id) =>
      'https://github.com/yearnc/echo/releases/download/$releaseTag/'
      'echo-models-$id-v1.zip';

  static String _mirror(String url) => 'https://gh-proxy.com/$url';

  static List<ModelResource> get builtIn {
    final asr = _assetUrl('asr');
    final tts = _assetUrl('tts');
    final zipvoice = _assetUrl('zipvoice');
    final asrStream = _assetUrl('asr-stream');
    return [
      ModelResource(
        id: 'asr',
        name: '语音识别（SenseVoice）',
        description: '按住说话转文字、私信语音转写。约 229 MB。',
        storageDir: 'asr',
        requiredFiles: const ['model.int8.onnx', 'tokens.txt'],
        version: 1,
        bytes: 229 * 1024 * 1024,
        url: asr,
        mirrorUrl: _mirror(asr),
      ),
      ModelResource(
        id: 'tts',
        name: '文字语音（VITS 中文）',
        description: '住民用文字描述说话时的本机嗓音，5 个中文声线。约 117 MB。',
        storageDir: 'vits-zh-ll',
        requiredFiles: const [
          'model.onnx',
          'lexicon.txt',
          'tokens.txt',
          'date.fst',
          'number.fst',
          'phone.fst',
        ],
        version: 1,
        bytes: 117 * 1024 * 1024,
        url: tts,
        mirrorUrl: _mirror(tts),
      ),
      ModelResource(
        id: 'zipvoice',
        name: '音色克隆（ZipVoice）',
        description: '上传参考音频后，用同一把嗓子说话。约 187 MB。',
        storageDir: 'zipvoice',
        requiredFiles: const [
          'encoder.int8.onnx',
          'decoder.int8.onnx',
          'vocos_24khz.onnx',
          'tokens.txt',
          'lexicon.txt',
          'espeak-ng-data.zip',
        ],
        version: 1,
        bytes: 187 * 1024 * 1024,
        url: zipvoice,
        mirrorUrl: _mirror(zipvoice),
      ),
      ModelResource(
        id: 'asr-stream',
        name: '流式识别（通话用）',
        description: '通话时边说边出字；不装也能用普通语音消息。约 190 MB。',
        storageDir: 'asr-stream',
        requiredFiles: const [
          'encoder.int8.onnx',
          'decoder.int8.onnx',
          'joiner.int8.onnx',
          'tokens.txt',
        ],
        version: 1,
        bytes: 190 * 1024 * 1024,
        url: asrStream,
        mirrorUrl: _mirror(asrStream),
      ),
    ];
  }

  /// 拉取远程清单；失败就安静地用内置那份。
  Future<List<ModelResource>> load({bool refresh = false}) async {
    final base = {
      for (final item in builtIn) item.id: item,
    };
    if (!refresh) return base.values.toList(growable: false);
    try {
      final response = await _dio.get<String>(
        remoteManifestUrl,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 12),
          headers: const {'Cache-Control': 'no-cache'},
        ),
      );
      final raw = response.data ?? '';
      if (raw.trim().isEmpty) return base.values.toList(growable: false);
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['resources'] is! List) {
        return base.values.toList(growable: false);
      }
      for (final item in decoded['resources'] as List) {
        if (item is! Map) continue;
        final json = {
          for (final entry in item.entries)
            if (entry.key is String) entry.key as String: entry.value,
        };
        final id = json['id'];
        if (id is! String || !base.containsKey(id)) continue;
        base[id] = base[id]!.mergeManifest(json);
      }
      return base.values.toList(growable: false);
    } catch (error) {
      // 离线或 GitHub 抽风时继续用内置清单，不拦下载。
      debugPrint('[资源] 远程清单没拿到，按内置清单走：$error');
      return base.values.toList(growable: false);
    }
  }
}
