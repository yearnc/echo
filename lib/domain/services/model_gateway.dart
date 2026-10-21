import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/model_config_repository.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../models/model_config.dart';
import 'model_call_common.dart';
import 'user_identity_prompt.dart';

/// 模型要调用一个工具。
class ToolCallRequest {
  const ToolCallRequest({
    required this.id,
    required this.name,
    this.arguments = const {},
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

/// 带工具的一轮回复：要么给了话，要么给了要调用的工具。
class ToolChatResult {
  const ToolChatResult({this.content = '', this.toolCalls = const []});

  final String content;
  final List<ToolCallRequest> toolCalls;
}

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
  ModelGateway(this._configs, {Dio? dio, this.profiles})
    : _dio = dio ?? Dio();

  final ModelConfigRepository _configs;
  final Dio _dio;

  /// 本机用户的身份资料。每次请求把它拼到 system 最前面——
  /// 内容稳定，所以缓存前缀不会因为“这是哪一轮”而分叉。
  final UserProfileRepository? profiles;

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
  }) => _completeMessages(
    config: config,
    messages: [
      for (final message in messages) Map<String, dynamic>.from(message),
    ],
    temperature: temperature,
    maxTokens: maxTokens,
    timeout: timeout,
  );

  /// 带图片的对话：messages 里可以放 `image_url` 内容块。
  ///
  /// 与 [complete] 分开是为了不破坏现有调用方的 `Map<String, String>`；
  /// 图片只走需要它的解析/私信路径。
  Future<String> completeRich({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.2,
    int? maxTokens,
    Duration timeout = const Duration(seconds: 20),
  }) => _completeMessages(
    config: config,
    messages: messages,
    temperature: temperature,
    maxTokens: maxTokens,
    timeout: timeout,
  );

  Future<String> _completeMessages({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required int? maxTokens,
    required Duration timeout,
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
      'messages': await _withIdentity(messages),
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

      // 缓存命中只能从 usage 看出来。没命中和没数据显示上都是"0"，
      // 但这里不编数字：服务商不回 usage，就当不知道。
      logModelUsage(config.model, ModelUsage.fromBody(response.data));

      final content = extractAssistantContent(response.data);
      if (content == null) {
        throw const ModelCallException('模型没有返回内容');
      }
      return content;
    } on DioException catch (error) {
      throw ModelCallException(describeModelError(error, baseUrl: baseUrl));
    }
  }

  /// 把身份块拼到 system 最前面。
  ///
  /// anthropic 风格要求 system 是独立块；OpenAI 兼容端则把 system 当普通
  /// 消息。这里统一成“第一条消息是 system”，身份作为它的开头文本，
  /// 后面的规则/帖子原样不动——共享前缀因此保持稳定。
  Future<List<Map<String, dynamic>>> _withIdentity(
    List<Map<String, dynamic>> raw,
  ) async {
    final messages = [
      for (final message in raw) Map<String, dynamic>.from(message),
    ];
    final identity = UserIdentityPrompt.build(await profiles?.load());
    if (identity.isEmpty) return messages;
    if (messages.isEmpty) {
      return [
        {'role': 'system', 'content': identity},
      ];
    }

    final first = messages.first;
    if (first['role'] == 'system') {
      final content = first['content'];
      if (content is List) {
        first['content'] = [
          {'type': 'text', 'text': identity},
          ...content,
        ];
      } else if (content is String) {
        first['content'] = '$identity$content';
      } else {
        first['content'] = identity;
      }
      return messages;
    }

    return [
      {'role': 'system', 'content': identity},
      ...messages,
    ];
  }

  /// 带 tools 的一轮对话（OpenAI 兼容的 function calling）。
  ///
  /// 不支持 tools 的服务商会直接 400——调用方据此退回"本地预检索"，
  /// 所以这里不猜"这家支不支持"，试一次最省事。
  Future<ToolChatResult> completeWithTools({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    double temperature = 0.8,
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
      'messages': await _withIdentity(messages),
      'temperature': temperature,
      'tools': tools,
      'tool_choice': 'auto',
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

      logModelUsage('${config.model}（tools）', ModelUsage.fromBody(response.data));

      final choices = response.data?['choices'];
      if (choices is! List || choices.isEmpty) {
        throw const ModelCallException('模型没有返回内容');
      }
      final message = (choices.first as Map)['message'];
      if (message is! Map) {
        throw const ModelCallException('模型返回的形状不认识');
      }

      final calls = <ToolCallRequest>[];
      final rawCalls = message['tool_calls'];
      if (rawCalls is List) {
        for (final raw in rawCalls) {
          if (raw is! Map) continue;
          final function = raw['function'];
          if (function is! Map) continue;
          final name = function['name'];
          if (name is! String || name.isEmpty) continue;
          calls.add(
            ToolCallRequest(
              id: (raw['id'] as String?) ?? 'call_${calls.length}',
              name: name,
              arguments: _parseArguments(function['arguments']),
            ),
          );
        }
      }

      return ToolChatResult(
        content: (message['content'] as String?)?.trim() ?? '',
        toolCalls: calls,
      );
    } on DioException catch (error) {
      throw ModelCallException(describeModelError(error, baseUrl: baseUrl));
    }
  }

  static Map<String, dynamic> _parseArguments(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is! String || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  /// 云端语音合成，返回音频字节（OpenAI 兼容的 `/audio/speech`）。
  ///
  /// 和对话、出图一样，这里只负责"发出去、把东西拿回来"；
  /// 选哪条配置、失败后要不要退回本机，都是调用方的事。
  Future<Uint8List> speech({
    required ModelConfig config,
    required String text,
    String voice = 'alloy',
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final apiKey = (await _configs.readKey(config.id))?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw const ModelCallException('这条配置还没有填 API Key');
    }

    final baseUrl = normalizeBaseUrl(config.baseUrl);
    final problem = describeBaseUrlProblem(baseUrl);
    if (problem != null) throw ModelCallException(problem);

    try {
      final response = await _dio.post<List<int>>(
        '$baseUrl/audio/speech',
        data: {'model': config.model, 'input': text, 'voice': voice},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          // 要的是二进制音频，不是 JSON
          responseType: ResponseType.bytes,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );

      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw const ModelCallException('语音服务没有返回音频');
      }

      // 有的兼容端点在出错时仍然回 200 + JSON。这里认一下：
      // 音频字节不会以 `{` 开头，也不该是 text/json。
      final contentType =
          response.headers.value(Headers.contentTypeHeader) ?? '';
      final looksLikeJson =
          contentType.contains('json') || (bytes.length < 1024 && bytes[0] == 0x7B);
      if (looksLikeJson) {
        final raw = String.fromCharCodes(bytes.take(120));
        throw ModelCallException('语音服务返回了错误：$raw');
      }

      return Uint8List.fromList(bytes);
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
  (ref) => ModelGateway(
    ref.watch(modelConfigRepositoryProvider),
    profiles: ref.watch(userProfileRepositoryProvider),
  ),
);

/// 当前真正可用的云端 TTS 配置；没配就是 null。
///
/// 设置页拿它回答"能不能选云端"，TtsService 拿它决定走哪条路。
/// 订阅配置列表是为了：用户在模型页配好一条之后，回来就能立刻选云端。
final cloudTtsConfigProvider = FutureProvider<ModelConfig?>((ref) async {
  ref.watch(modelConfigsProvider);
  return ref.watch(modelGatewayProvider).activeConfig(kind: ModelKind.tts);
});
