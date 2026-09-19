import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'model_call_common.dart';

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
    final url = '${normalizeBaseUrl(baseUrl)}/chat/completions';
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
      final reply = extractAssistantContent(response.data);

      return ProbeResult(
        ok: true,
        message: reply == null ? '连接成功，但没读到回复内容' : '连接成功',
        reply: reply,
        elapsedMs: elapsed,
      );
    } on DioException catch (error) {
      return ProbeResult(
        ok: false,
        message: describeModelError(error),
        elapsedMs: DateTime.now().difference(started).inMilliseconds,
      );
    } catch (error) {
      return ProbeResult(ok: false, message: '出错了：$error');
    }
  }

}

final modelProbeProvider = Provider<ModelProbe>((ref) => ModelProbe());
