import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/model_config_repository.dart';
import '../models/model_config.dart';
import 'model_call_common.dart';

/// 一次业务调用失败。[message] 是可以直接显示给用户的中文。
class ModelCallException implements Exception {
  const ModelCallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 业务侧调用模型的通道。
///
/// 阶段 A 只有 [ModelProbe]：点一次"测试连接"，真发一句过去看回不回。
/// 阶段 B 开始有东西真的需要模型（先是内容审核，之后是评论与动态生成），
/// 它们要的是同一件事——拿"启用的那条配置 + 它的密钥"发一轮对话，取回复文本。
///
/// **这里不做重试、不做缓存、不做降级**：那些是调用方的事。
/// 审核遇到超时该放行、生成遇到超时该退回样本，两者的处置完全不同，
/// 塞进网关只会让双方都难受。
class ModelGateway {
  ModelGateway(this._configs, {Dio? dio}) : _dio = dio ?? Dio();

  final ModelConfigRepository _configs;
  final Dio _dio;

  /// 当前真正能用的那条配置：用途对得上、已启用、地址与模型名完整、密钥填过。
  ///
  /// 三样缺一不可，所以逐个查而不是只看 `enabled`——配置页允许先存一条空配置
  /// 再慢慢填，"已启用但没填密钥"是常态而不是异常。
  ///
  /// [kind] 分开查：聊天和文生图是两条独立的配置，用户可能只配了其中一个。
  Future<ModelConfig?> activeConfig({ModelKind kind = ModelKind.chat}) async {
    final configs = await _configs.findAll();
    for (final config in configs) {
      if (config.kind != kind) continue;
      if (!config.enabled || !config.isComplete) continue;
      if (await _configs.hasKey(config.id)) return config;
    }
    return null;
  }

  /// 发一轮对话，返回助手的回复文本。
  ///
  /// [maxTokens] 不设默认值：审核只要几十个字、生成评论要几百个，
  /// 统一默认值对谁都不合适，交给调用方按自己的用量给。
  Future<String> complete({
    required ModelConfig config,
    required List<Map<String, String>> messages,
    double temperature = 0.2,
    int? maxTokens,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final apiKey = (await _configs.readKey(config.id))?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw const ModelCallException('这条配置还没有填 API Key');
    }

    final baseUrl = normalizeBaseUrl(config.baseUrl);
    final problem = describeBaseUrlProblem(baseUrl);
    if (problem != null) throw ModelCallException(problem);

    final body = <String, dynamic>{
      'model': config.model,
      'messages': messages,
      'temperature': temperature,
    };
    if (maxTokens != null) body['max_tokens'] = maxTokens;

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/chat/completions',
        data: body,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );

      final content = extractAssistantContent(response.data);
      if (content == null) {
        throw const ModelCallException('模型没有返回内容');
      }
      return content;
    } on DioException catch (error) {
      throw ModelCallException(describeModelError(error, baseUrl: baseUrl));
    }
  }

  /// 生成一张图，返回图片数据本身。
  ///
  /// OpenAI 兼容的图片接口是 `/images/generations`，跟对话不是同一条路径；
  /// 返回里可能给 base64、也可能给一条 URL，两种都得认——
  /// 各家在这件事上并没有对齐。
  Future<Uint8List> generateImage({
    required ModelConfig config,
    required String prompt,
    String? size,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final apiKey = (await _configs.readKey(config.id))?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw const ModelCallException('这条配置还没有填 API Key');
    }

    final baseUrl = normalizeBaseUrl(config.baseUrl);
    final problem = describeBaseUrlProblem(baseUrl);
    if (problem != null) throw ModelCallException(problem);

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/images/generations',
        data: {
          'model': config.model,
          'prompt': prompt,
          // 刻意不带 n，也不带 response_format：不是每家都认这两个参数
          // （智谱的图片接口就没有 n），发了可能被 400 挡回来。
          // 返回值有几种形状，认形状是我们这边的事。
          if (size != null && size.isNotEmpty) 'size': size,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          // 出图比回一句话慢得多，超时给得宽一些
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );

      final entry = firstImageEntry(response.data);
      if (entry == null) {
        throw const ModelCallException('模型没有返回图片');
      }

      final encoded = entry['b64_json'];
      if (encoded is String && encoded.isNotEmpty) {
        try {
          return base64Decode(encoded);
        } catch (_) {
          throw const ModelCallException('返回的图片数据解不开');
        }
      }

      final url = entry['url'];
      if (url is String && url.isNotEmpty) {
        return await _downloadImage(url, timeout: timeout);
      }

      throw const ModelCallException('返回里既没有图片数据也没有链接');
    } on DioException catch (error) {
      throw ModelCallException(describeModelError(error, baseUrl: baseUrl));
    }
  }

  /// 有些服务端给的是图片链接（有效期常常只有几十分钟），那就再取一次。
  Future<Uint8List> _downloadImage(
    String url, {
    required Duration timeout,
  }) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw const ModelCallException('图片取回来是空的');
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (error) {
      throw ModelCallException(describeModelError(error));
    }
  }
}

final modelGatewayProvider = Provider<ModelGateway>(
  (ref) => ModelGateway(ref.watch(modelConfigRepositoryProvider)),
);
