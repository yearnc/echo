import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 模型调用的公共小工具。
///
/// 探测（`ModelProbe`）与业务调用（`ModelGateway`）打的是同一个接口、
/// 撞的是同一批错误码。这些函数只留一份——同一个毛病的说法在两个地方
/// 不一样，用户会以为是两个问题。

/// 去掉地址末尾的斜杠，好拼 `/chat/completions`。
String normalizeBaseUrl(String baseUrl) {
  final trimmed = baseUrl.trim();
  return trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

/// 除了本机与内网，一律要求 https。
///
/// 明文 http 会让 API Key 在网络上一路可见，而"从网上抄来的免费中转地址"
/// 恰恰是这类配置最容易出现的地方。本机与内网放行——那是用户自己跑的服务，
/// 请求出不了他自己的局域网。
bool isSecureBaseUrl(String baseUrl) {
  if (baseUrl.startsWith('https://')) return true;

  final host = Uri.tryParse(baseUrl)?.host ?? '';
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') return true;
  if (host.startsWith('192.168.') || host.startsWith('10.')) return true;
  if (host.startsWith('172.')) {
    final second = int.tryParse(host.split('.').elementAt(1));
    return second != null && second >= 16 && second <= 31;
  }
  return false;
}

/// 地址本身有没有毛病——返回 `null` 表示没问题。
///
/// 分两种说：**没写协议头**（从文档里复制一段域名粘进来，最常见）和
/// **写了明文 http**。这两种在 dio 那里都会撞成同一个 `connectionError`，
/// 翻译出来是"连不上这个地址，检查网络"——用户于是跑去查网络，
/// 而问题其实一直在地址栏里。所以测试连接和正经调用都先过一道这里。
String? describeBaseUrlProblem(String baseUrl) {
  final trimmed = baseUrl.trim();
  if (trimmed.isEmpty) return '还没填地址';
  if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
    return '地址要带协议头：写成 https://… 的样子';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) {
    return '这个地址看着不像网址，检查一下有没有多余的空格';
  }
  if (!isSecureBaseUrl(trimmed)) {
    return '这个地址是明文 http，密钥会在网络上裸奔。换成 https 地址再试。';
  }
  return null;
}

/// 把 dio 的错误翻译成用户看得懂的中文。
///
/// 给了 [baseUrl] 就在"连不上"那句里把它带出来——地址差一个字符和真的断网，
/// 在这句话之前长得一模一样。
String describeModelError(DioException error, {String? baseUrl}) {
  final status = error.response?.statusCode;
  if (status == 401 || status == 403) {
    return '密钥被拒绝了（HTTP $status），检查一下 API Key';
  }
  if (status == 404) return '地址不对（HTTP 404），检查 base url 和模型名';
  if (status == 429) return '请求太频繁，或者额度用完了（HTTP 429）';
  if (status != null) {
    // 刻意不回显对方返回的正文。第三方端点里返回什么由不得我们，
    // 而有些中转服务会把请求头原样回显——那里面正带着 API Key。
    return '对方返回了 HTTP $status，检查一下服务商状态或稍后再试';
  }
  return switch (error.type) {
    DioExceptionType.connectionTimeout => '连接超时，检查网络或代理',
    DioExceptionType.receiveTimeout => '对方太久没回，可能太慢',
    DioExceptionType.connectionError => baseUrl == null
        ? '连不上这个地址，检查网络'
        : '连不上 $baseUrl —— 检查网络，也看一遍地址有没有写全（要带 https://）',
    _ => error.message ?? '请求失败',
  };
}

/// 从文生图的返回里挑出第一张图。
///
/// 各家形状不一：`data` / `images` 两个壳都见过，里面可能是对象
/// （带 `url` 或 `b64_json`），也可能干脆就是一串 URL。认形状是我们这边的事，
/// 所以探测与正经出图共用这一个函数。
Map<String, dynamic>? firstImageEntry(Map<String, dynamic>? body) {
  for (final key in const ['data', 'images']) {
    final list = body?[key];
    if (list is! List || list.isEmpty) continue;

    final first = list.first;
    if (first is Map) return Map<String, dynamic>.from(first);
    // 有的服务端直接给一串 URL 字符串
    if (first is String && first.isNotEmpty) return {'url': first};
  }
  return null;
}

/// 一次请求的 token 账。缓存命中与否只能从这里看出来。
///
/// 各家字段名不一样，但说的是同一件事：
/// - OpenAI：`prompt_tokens_details.cached_tokens`
/// - DeepSeek：`prompt_cache_hit_tokens`
/// - Anthropic：`cache_read_input_tokens` / `cache_creation_input_tokens`
///
/// 没给就是 0——**不猜**。服务商不回 usage 时，命中率未知比编一个数字好。
class ModelUsage {
  const ModelUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cachedTokens = 0,
    this.cacheWriteTokens = 0,
  });

  final int promptTokens;
  final int completionTokens;
  final int cachedTokens;
  final int cacheWriteTokens;

  static const ModelUsage zero = ModelUsage();

  bool get hasData => promptTokens > 0 || completionTokens > 0;
  int get cacheHitRate =>
      promptTokens == 0 ? 0 : (cachedTokens / promptTokens * 100).round();

  /// 一行日志：排查"怎么一直没命中"时，就靠它。
  String get summary =>
      '输入 $promptTokens（缓存命中 $cachedTokens，$cacheHitRate%'
      '${cacheWriteTokens > 0 ? '，写入 $cacheWriteTokens' : ''}）'
      '｜输出 $completionTokens';

  static ModelUsage fromBody(Map<String, dynamic>? body) {
    final usage = body?['usage'];
    if (usage is! Map) return zero;

    int pick(List<String> keys) {
      for (final key in keys) {
        final value = usage[key];
        if (value is num) return value.toInt();
      }
      return 0;
    }

    final details = usage['prompt_tokens_details'];
    var cached = 0;
    if (details is Map) {
      final value = details['cached_tokens'];
      if (value is num) cached = value.toInt();
    }

    return ModelUsage(
      promptTokens: pick(const ['prompt_tokens', 'input_tokens']),
      completionTokens: pick(const ['completion_tokens', 'output_tokens']),
      cachedTokens: cached == 0
          ? pick(const [
              'prompt_cache_hit_tokens',
              'cache_read_input_tokens',
            ])
          : cached,
      cacheWriteTokens: pick(const ['cache_creation_input_tokens']),
    );
  }
}

void logModelUsage(String label, ModelUsage usage) {
  if (!usage.hasData) return;
  debugPrint('[缓存] $label：${usage.summary}');
}

/// 从 OpenAI 兼容的响应里取出助手的第一条回复文本。
///
/// 各家的返回大同小异，但"choices 为空""content 不是字符串"（比如被内容过滤
/// 截断）都真实存在，所以这里宁可返回 null 也不抛。
String? extractAssistantContent(Map<String, dynamic>? data) {
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
