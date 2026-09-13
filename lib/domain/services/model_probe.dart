import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 一次连通性测试的结果。
class ProbeResult {
  const ProbeResult({
    required this.ok,
    required this.message,
    this.reply,
    this.elapsedMs = 0,
  });

  final bool ok;
  final String message;
  final String? reply;
  final int elapsedMs;
}

/// 模型连通性测试：真发一句过去，看对方回不回。
///
/// 只做这一件事——不缓存、不重试、不猜。用户点"测试"就该是一次真实的往返，
/// 成功了才说明地址、密钥、模型名这三样同时是对的。
class ModelProbe {
  ModelProbe({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<ProbeResult> test({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final url = '${_normalize(baseUrl)}/chat/completions';
    final started = DateTime.now();

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        url,
        data: {
          'model': model,
          'messages': [
            {'role': 'user', 'content': '用一句话打个招呼就好'},
          ],
          // 刻意不发 max_tokens：OpenAI 已把它换成 max_completion_tokens
          // 且 o 系列不认旧名，而大多数兼容端点还没跟上新名。
          // 测试连接只要它能回话就行，长度由提示词管着。
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final reply = _extractReply(response.data);

      return ProbeResult(
        ok: true,
        message: reply == null ? '连接成功，但没读到回复内容' : '连接成功',
        reply: reply,
        elapsedMs: elapsed,
      );
    } on DioException catch (error) {
      return ProbeResult(
        ok: false,
        message: _describe(error),
        elapsedMs: DateTime.now().difference(started).inMilliseconds,
      );
    } catch (error) {
      return ProbeResult(ok: false, message: '出错了：$error');
    }
  }

  static String _normalize(String baseUrl) {
    final trimmed = baseUrl.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  static String? _extractReply(Map<String, dynamic>? data) {
    final choices = data?['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is Map) {
      final content = message['content'];
      if (content is String && content.trim().isNotEmpty) return content.trim();
    }
    return null;
  }

  static String _describe(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return '密钥被拒绝了（HTTP $status），检查一下 API Key';
    }
    if (status == 404) return '地址不对（HTTP 404），检查 base url 和模型名';
    if (status == 429) return '请求太频繁，或者额度用完了（HTTP 429）';
    if (status != null) {
      final data = error.response?.data;
      final detail = data is Map ? data['error'] : null;
      return 'HTTP $status：${detail ?? error.message ?? ''}';
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout => '连接超时，检查网络或代理',
      DioExceptionType.receiveTimeout => '对方太久没回，可能太慢',
      DioExceptionType.connectionError => '连不上这个地址，检查网络',
      _ => error.message ?? '请求失败',
    };
  }
}

final modelProbeProvider = Provider<ModelProbe>((ref) => ModelProbe());
