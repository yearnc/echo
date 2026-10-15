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
    // 地址本身就不对的话不必真发出去：那一定只剩"连不上这个地址"，
    // 而这句话会把用户引到网络上去——手机端"连不上"有一半是地址没写全
    final problem = describeBaseUrlProblem(baseUrl);
    if (problem != null) return ProbeResult(ok: false, message: problem);

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
        message: describeModelError(error, baseUrl: baseUrl),
        elapsedMs: DateTime.now().difference(started).inMilliseconds,
      );
    } catch (error) {
      return ProbeResult(ok: false, message: '出错了：$error');
    }
  }

  /// 测一次文生图。
  ///
  /// 对话模型靠一句"你好"就能验，图片模型不行——得真让它画点什么。
  /// 提示词给最小的一条，只看它回不回得来图，画得好不好看不管。
  ///
  /// 走的是和正经出图同一个接口（`/images/generations`），
  /// 所以它能通，住民发图文帖那条路就能通。
  Future<ProbeResult> testImage({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final problem = describeBaseUrlProblem(baseUrl);
    if (problem != null) return ProbeResult(ok: false, message: problem);

    final url = '${normalizeBaseUrl(baseUrl)}/images/generations';
    final started = DateTime.now();

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        url,
        data: {'model': model, 'prompt': '一只趴在窗台上的猫'},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          // 出图比回一句话慢得多，超时给得宽一些
          sendTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );

      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final entry = firstImageEntry(response.data);

      return ProbeResult(
        ok: entry != null,
        message: entry != null ? '连接成功，能出图' : '连上了，但返回里没读到图片',
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
