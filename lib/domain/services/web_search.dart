import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/model_config_repository.dart';
import '../models/model_config.dart';
import 'model_call_common.dart';

class WebSearchResult {
  const WebSearchResult({
    required this.title,
    required this.url,
    this.snippet = '',
    this.date = '',
  });

  final String title;
  final String url;
  final String snippet;

  /// 来源标注的发布时间（各家的字段名和格式不统一，原样保留）。
  /// 模型靠它判断“这是不是最新消息”，比只看标题可靠。
  final String date;
}

class WebSearchOutcome {
  const WebSearchOutcome({
    required this.ok,
    this.provider = '',
    this.results = const [],
    this.message = '',
  });

  final bool ok;
  final String provider;
  final List<WebSearchResult> results;
  final String message;
}

/// 联网搜索（v3.3）。
///
/// 三条真正可用的路：
///
/// - **DeepSeek 官方 Search API**：`POST /v1/tools/search`，独立于对话模型，
///   直接返回 `results[{title,url,snippet,summary,...}]`。这是最干净的一条：
///   不需要模型配合，也不会让模型“假装查过”。按成功请求次数计费。
/// - **智谱**：chat/completions 里带 `tools:[{type:web_search}]`
/// - **百炼**：chat/completions 顶层带 `enable_search: true`
///
/// 后两家复用用户已经配好的对话模型与密钥；DeepSeek 需要一条启用的
/// DeepSeek 配置来拿 Key（地址可以按官方端点拼）。搜索失败时必须说
/// “没搜到/没联网”，绝不能让模型拿记忆冒充实时结果。
class WebSearchService {
  WebSearchService({
    required this.configs,
    required this.db,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  final ModelConfigRepository configs;
  final AppDatabase db;
  final Dio _dio;

  static const String providerKey = 'web.search.provider';
  static const String providerDeepseek = 'deepseek';
  static const String providerZhipu = 'zhipu';
  static const String providerDashscope = 'dashscope';

  static bool _known(String value) =>
      value == providerDeepseek ||
      value == providerZhipu ||
      value == providerDashscope;

  static const Duration timeout = Duration(seconds: 25);

  Future<String> provider() async {
    final query = db.select(db.appSettings)
      ..where((t) => t.key.equals(providerKey));
    final row = await query.getSingleOrNull();
    final value = row?.value.trim() ?? '';
    return _known(value) ? value : '';
  }

  Future<void> setProvider(String value) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: providerKey,
            value: _known(value) ? value : '',
          ),
        );
  }

  Future<WebSearchOutcome> search(String query) async {
    final text = query.trim();
    if (text.isEmpty) {
      return const WebSearchOutcome(ok: false, message: '搜索词是空的');
    }
    final which = await provider();
    if (which.isEmpty) {
      return const WebSearchOutcome(ok: false, message: '联网搜索没有开启');
    }

    // DeepSeek 是独立工具 API，不走 chat/completions。
    if (which == providerDeepseek) {
      return _searchDeepseek(text);
    }

    // 智谱 / 百炼的搜索是**对话接口带的参数**，所以必须用同一家的配置：
    // 拿 DeepSeek 的地址发智谱的 web_search 参数，只会换回一个 400。
    final wanted = which == providerZhipu ? 'zhipu' : 'qwen';
    final label = which == providerZhipu ? '智谱' : '百炼（通义千问）';
    final configsAll = await configs.findAll();
    ModelConfig? config;
    ModelConfig? fallback;
    for (final item in configsAll) {
      if (item.kind != ModelKind.chat) continue;
      if (item.provider != wanted) continue;
      if (!item.isComplete || !await configs.hasKey(item.id)) continue;
      if (item.enabled) {
        config = item;
        break;
      }
      fallback ??= item;
    }
    config ??= fallback;
    if (config == null) {
      return WebSearchOutcome(
        ok: false,
        provider: which,
        message: '选用 $label 搜索，但模型配置里没有可用的 $label 配置（填好地址和 Key 即可，不需要启用）',
      );
    }
    final key = await configs.readKey(config.id);
    if (key == null || key.trim().isEmpty) {
      return const WebSearchOutcome(ok: false, message: '模型密钥是空的');
    }

    final baseUrl = normalizeBaseUrl(config.baseUrl);
    final problem = describeBaseUrlProblem(baseUrl);
    if (problem != null) {
      return WebSearchOutcome(ok: false, message: problem);
    }

    try {
      final body = <String, dynamic>{
        'model': config.model,
        'messages': [
          {
            'role': 'user',
            'content': '帮我搜索：$text\n只按搜索结果回答，不要凭记忆补。',
          },
        ],
        'temperature': 0.2,
        if (which == providerZhipu)
          'tools': [
            {
              'type': 'web_search',
              'web_search': {
                'enable': true,
                'search_engine': 'search_std',
                'count': 8,
              },
            },
          ],
        if (which == providerDashscope) 'enable_search': true,
      };

      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/chat/completions',
        data: body,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${key.trim()}',
            'Content-Type': 'application/json',
          },
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );

      final payload = response.data ?? const <String, dynamic>{};
      final results = _harvest(payload);
      if (results.isEmpty) {
        return WebSearchOutcome(
          ok: false,
          provider: which,
          message: '这次没有返回搜索结果（可能关键词太窄，或服务商没开搜索）',
        );
      }
      return WebSearchOutcome(ok: true, provider: which, results: results);
    } on DioException catch (error) {
      debugPrint('[搜索] 失败：${error.message}');
      return WebSearchOutcome(
        ok: false,
        provider: which,
        message: describeModelError(error, baseUrl: baseUrl),
      );
    } catch (error) {
      debugPrint('[搜索] 失败：$error');
      return WebSearchOutcome(ok: false, provider: which, message: '$error');
    }
  }

  /// DeepSeek 官方工具 API：`POST /v1/tools/search`。
  ///
  /// 它和对话模型是两回事，所以这里只找一条启用的 DeepSeek 配置来取 Key 与
  /// 地址；返回的 `results` 已经是干净的来源列表，不需要再让模型“复述”。
  Future<WebSearchOutcome> _searchDeepseek(String text) async {
    // DeepSeek 搜索 API 和对话模型是两回事：它只需要这个服务商的 Key。
    // 所以这里**不要求那条配置处于启用状态**——用户完全可能日常用别的模型对话，
    // 但在模型配置里留了一条 DeepSeek 专门给搜索用。
    ModelConfig? config;
    ModelConfig? fallback;
    for (final item in await configs.findAll()) {
      if (item.provider != 'deepseek') continue;
      if (!item.isComplete) continue;
      if (!await configs.hasKey(item.id)) continue;
      if (item.enabled) {
        config = item;
        break;
      }
      fallback ??= item;
    }
    config ??= fallback;
    if (config == null) {
      return const WebSearchOutcome(
        ok: false,
        provider: providerDeepseek,
        message: '选用 DeepSeek 搜索，但模型配置里没有可用的 DeepSeek 配置（填好地址和 Key 即可，不需要启用）',
      );
    }

    final key = (await configs.readKey(config.id))?.trim() ?? '';
    if (key.isEmpty) {
      return const WebSearchOutcome(
        ok: false,
        provider: providerDeepseek,
        message: 'DeepSeek 的密钥是空的',
      );
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _toolsEndpoint(config.baseUrl),
        data: {
          'query': text,
          'count': 8,
          'need_content': false,
          // query 是模型写的搜索词，可能没带年份；ori_question 是“用户到底
          // 想问什么”，这里补上当前年月，帮检索引擎优先理解“现在”。
          'ori_question': '当前是 ${DateTime.now().year} 年 '
              '${DateTime.now().month} 月。$text',
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );

      final payload = response.data ?? const <String, dynamic>{};
      final raw = payload['results'];
      final results = <WebSearchResult>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final title = item['title'];
          final url = item['url'];
          if (title is! String || url is! String) continue;
          // snippet 短、summary 长；给模型读时短摘要就够，长摘要留给需要展开时。
          final snippet = item['snippet'] ?? item['summary'] ?? item['content'];
          final date = item['date'];
          results.add(
            WebSearchResult(
              title: title,
              url: url,
              snippet: snippet is String ? snippet : '',
              date: date is String ? date : '',
            ),
          );
        }
      }

      if (results.isEmpty) {
        return const WebSearchOutcome(
          ok: false,
          provider: providerDeepseek,
          message: '这次没有搜到结果（换几个关键词试试）',
        );
      }
      return WebSearchOutcome(
        ok: true,
        provider: providerDeepseek,
        results: results.take(8).toList(growable: false),
      );
    } on DioException catch (error) {
      debugPrint('[搜索] DeepSeek 失败：${error.message}');
      return WebSearchOutcome(
        ok: false,
        provider: providerDeepseek,
        message: describeModelError(error, baseUrl: config.baseUrl),
      );
    } catch (error) {
      debugPrint('[搜索] DeepSeek 失败：$error');
      return WebSearchOutcome(
        ok: false,
        provider: providerDeepseek,
        message: '$error',
      );
    }
  }

  /// 配置里可能写 `https://api.deepseek.com`、带 `/v1`，甚至带完整
  /// `/chat/completions`。统一收成工具 API 的地址。
  static String _toolsEndpoint(String raw) {
    var base = normalizeBaseUrl(raw);
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    const suffix = '/chat/completions';
    if (base.endsWith(suffix)) {
      base = base.substring(0, base.length - suffix.length);
    }
    return base.endsWith('/v1')
        ? '$base/tools/search'
        : '$base/v1/tools/search';
  }

  /// 两家把来源放在不同位置（`search_result` / `search_info.search_results`），
  /// 这里不猜路径，递归找带 title+url 的列表。
  static List<WebSearchResult> _harvest(Map<String, dynamic> payload) {
    final results = <WebSearchResult>[];
    final seen = <String>{};

    void walk(Object? node) {
      if (node is Map) {
        final title = node['title'];
        final url = node['url'] ?? node['link'];
        if (title is String && url is String && seen.add(url)) {
          final snippet = node['content'] ?? node['snippet'] ?? '';
          final date = node['date'] ?? node['publish_date'] ?? '';
          results.add(
            WebSearchResult(
              title: title,
              url: url,
              snippet: snippet is String ? snippet : '',
              date: date is String ? date : '',
            ),
          );
        }
        for (final value in node.values) {
          walk(value);
        }
      } else if (node is List) {
        for (final value in node) {
          walk(value);
        }
      }
    }

    walk(payload);
    return results.take(8).toList(growable: false);
  }
}

final webSearchServiceProvider = Provider<WebSearchService>(
  (ref) => WebSearchService(
    configs: ref.watch(modelConfigRepositoryProvider),
    db: ref.watch(databaseProvider),
  ),
);
