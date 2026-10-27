import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 聊天记录里的一段话。
///
/// [fromUser] 是“对方说的”还是“模型说的”——固定住民要记住的是前者，
/// 但后者里的上下文也可能有用，所以两半都保留。
class ImportedTurn {
  const ImportedTurn({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;
}

class ChatImportException implements Exception {
  const ChatImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 把 DeepSeek 分享页 / 粘贴的对话整理成一段段话（v3.9）。
///
/// 分享页是单页应用，真正的内容藏在页面内嵌的 JSON 里；这里做两件事：
/// 1. 抓 HTML，把所有内嵌 JSON 找出来，递归寻找带 role + content 的对象；
/// 2. 抓不到就明确失败，让用户改用“粘贴对话文本”那条路——不假装成功。
class ChatTranscriptImporter {
  ChatTranscriptImporter({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// 从分享链接读取。失败抛 [ChatImportException]。
  Future<List<ImportedTurn>> fromShareLink(String url) async {
    final clean = url.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      throw const ChatImportException('链接要以 http:// 或 https:// 开头');
    }
    final shareId = _shareIdOf(clean);
    if (shareId.isEmpty) {
      throw const ChatImportException('没有从链接里认出分享 id');
    }

    const headers = {
      // 分享页对浏览器 UA 更友好；不带 UA 容易被当成爬虫。
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/124.0 Safari/537.36',
      'Accept': 'application/json, text/html',
    };

    // DeepSeek 的分享页是单页应用，正文不在 HTML 里，而在
    // GET /api/v0/share/content?share_id=... 的 JSON 里。
    // 先走这个接口；结构变了再退回“从 HTML 里找内嵌 JSON”。
    try {
      final response = await _dio.get<String>(
        'https://chat.deepseek.com/api/v0/share/content',
        queryParameters: {'share_id': shareId},
        options: Options(responseType: ResponseType.plain, headers: headers),
      );
      final raw = response.data ?? '';
      final turns = turnsFromShareJson(raw);
      if (turns.isNotEmpty) return turns;
    } on DioException catch (error) {
      throw ChatImportException('打不开这个链接：${_dioReason(error)}');
    } catch (_) {
      // 解析失败继续尝试 HTML 那条路。
    }

    final Response<String> page;
    try {
      page = await _dio.get<String>(
        clean,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          headers: headers,
        ),
      );
    } on DioException catch (error) {
      throw ChatImportException('打不开这个链接：${_dioReason(error)}');
    }
    final html = page.data ?? '';
    final turns = _turnsFromHtml(html);
    if (turns.isEmpty) {
      throw const ChatImportException(
        '没有读到对话内容。链接可能已失效、需要登录，或者分享页改了结构；'
        '请改用「粘贴对话文本」。',
      );
    }
    return turns;
  }

  /// 解析 DeepSeek 的原始分享 JSON。
  ///
  /// 结构（2026-10 实测）：
  /// `data.biz_data.messages[].fragments[]`，
  /// fragment 的 `type` 是 REQUEST（用户）/ RESPONSE（AI）/ THINK（思考过程，
  /// 不进记忆）。只保留 REQUEST 与 RESPONSE。
  List<ImportedTurn> turnsFromShareJson(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
    if (decoded is! Map) return const [];
    final data = decoded['data'];
    final bizData = data is Map ? data['biz_data'] : null;
    final messages = bizData is Map ? bizData['messages'] : null;
    if (messages is! List) return const [];

    final turns = <ImportedTurn>[];
    for (final message in messages) {
      if (message is! Map) continue;
      final role = (message['role'] as String?)?.toUpperCase();
      final fromUser = switch (role) {
        'USER' => true,
        'ASSISTANT' => false,
        _ => null,
      };
      if (fromUser == null) continue;

      final fragments = message['fragments'];
      final buffer = StringBuffer();
      if (fragments is List) {
        for (final fragment in fragments) {
          if (fragment is! Map) continue;
          final type = (fragment['type'] as String?)?.toUpperCase();
          final wanted = fromUser ? 'REQUEST' : 'RESPONSE';
          if (type != wanted) continue;
          final text = _textOf(fragment['content']);
          if (text == null || text.trim().isEmpty) continue;
          if (buffer.isNotEmpty) buffer.write('\n');
          buffer.write(text.trim());
        }
      }
      if (buffer.isEmpty) {
        // 老结构：内容直接挂在 message.content 上。
        final text = _textOf(message['content'] ?? message['text']);
        if (text != null && text.trim().isNotEmpty) {
          buffer.write(text.trim());
        }
      }
      if (buffer.isEmpty) continue;
      turns.add(ImportedTurn(fromUser: fromUser, text: buffer.toString()));
    }
    return _limit(turns);
  }

  /// `https://chat.deepseek.com/share/xxx` → `xxx`。
  static String _shareIdOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final fromQuery = uri.queryParameters['share_id'];
    if (fromQuery != null && fromQuery.trim().isNotEmpty) {
      return fromQuery.trim();
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return '';
    return segments.last.trim();
  }

  /// 粘贴的文本。支持“我：/ AI：/ User: / Assistant:”这类前缀。
  List<ImportedTurn> fromPlainText(String raw) {
    final lines = raw.replaceAll('\r\n', '\n').split('\n');
    final turns = <ImportedTurn>[];
    bool? currentFromUser;
    final buffer = StringBuffer();

    void flush() {
      final text = buffer.toString().trim();
      buffer.clear();
      if (text.isEmpty || currentFromUser == null) return;
      turns.add(ImportedTurn(fromUser: currentFromUser, text: text));
    }

    for (final line in lines) {
      final match = _speakerPrefix.firstMatch(line);
      if (match != null) {
        flush();
        currentFromUser = _isUserRole(match.group(1)!);
        buffer.write(match.group(2)!.trimLeft());
      } else if (currentFromUser != null) {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(line);
      }
    }
    flush();

    if (turns.isEmpty) {
      throw const ChatImportException('没有认出对话格式。每段前请写「我：」或「AI：」，一行一段。');
    }
    return _limit(turns);
  }

  List<ImportedTurn> _turnsFromHtml(String html) {
    final blocks = <String>{};
    // Next.js 的整页数据。
    for (final match in RegExp(
      r'<script[^>]*id="__NEXT_DATA__"[^>]*>([\s\S]*?)</script>',
      caseSensitive: false,
    ).allMatches(html)) {
      blocks.add(match.group(1) ?? '');
    }
    // 其它 application/json 块（很多 SPA 的分享页会放一份）。
    for (final match in RegExp(
      r'<script[^>]*type="application/json"[^>]*>([\s\S]*?)</script>',
      caseSensitive: false,
    ).allMatches(html)) {
      blocks.add(match.group(1) ?? '');
    }

    final turns = <ImportedTurn>[];
    final seen = <String>{};
    for (final block in blocks) {
      final text = block.trim();
      if (text.isEmpty) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        continue;
      }
      _walk(decoded, (fromUser, content) {
        final key = '${fromUser ? 'u' : 'a'}:$content';
        if (!seen.add(key)) return;
        turns.add(ImportedTurn(fromUser: fromUser, text: content));
      });
    }
    return _limit(turns);
  }

  /// 在任意 JSON 里找“角色 + 内容”对。分享页的字段命名各版本不同，
  /// 所以只认几种常见组合，找不到就继续往下钻。
  void _walk(Object? node, void Function(bool fromUser, String text) onTurn) {
    if (node is List) {
      for (final item in node) {
        _walk(item, onTurn);
      }
      return;
    }
    if (node is! Map) return;

    final role = _roleOf(
      node['role'] ?? node['sender'] ?? node['author'] ?? node['from'],
    );
    if (role != null) {
      final content =
          node['content'] ??
          node['text'] ??
          node['message'] ??
          node['parts'] ??
          node['markdown'];
      final text = _textOf(content)?.trim();
      if (text != null && text.isNotEmpty) {
        onTurn(role, text);
        return;
      }
    }
    for (final value in node.values) {
      _walk(value, onTurn);
    }
  }

  static bool? _roleOf(Object? raw) {
    if (raw is! String) {
      if (raw is Map) {
        return _roleOf(raw['role'] ?? raw['type'] ?? raw['name']);
      }
      return null;
    }
    final role = raw.toLowerCase();
    if (role == 'user' || role == 'human' || role == 'me') return true;
    if (role == 'assistant' ||
        role == 'ai' ||
        role == 'bot' ||
        role == 'model' ||
        role == 'deepseek') {
      return false;
    }
    return null;
  }

  static String? _textOf(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final parts = [
        for (final item in content)
          if (_textOf(item) case final String text when text.trim().isNotEmpty)
            text,
      ];
      return parts.isEmpty ? null : parts.join('\n');
    }
    if (content is Map) {
      // DeepSeek 的思考过程单独放在 reasoning_content，不进记忆。
      for (final key in ['text', 'content', 'value', 'markdown']) {
        final value = content[key];
        if (value is String && value.trim().isNotEmpty) return value;
      }
      for (final key in ['parts', 'items', 'blocks']) {
        final value = content[key];
        final text = _textOf(value);
        if (text != null && text.trim().isNotEmpty) return text;
      }
    }
    return null;
  }

  static final RegExp _speakerPrefix = RegExp(
    r'^\s*(我|你|用户|对方|user|human|me|ai|assistant|bot|deepseek|助手)\s*[:：]\s*(.*)$',
    caseSensitive: false,
  );

  static bool _isUserRole(String raw) {
    final role = raw.toLowerCase();
    return role == '我' ||
        role == '你' ||
        role == '用户' ||
        role == '对方' ||
        role == 'user' ||
        role == 'human' ||
        role == 'me';
  }

  /// 只取最近的一段：几百条旧对话对“写记忆”没有帮助，反而会挤爆上下文。
  static List<ImportedTurn> _limit(List<ImportedTurn> turns) {
    const maxTurns = 400;
    const maxChars = 24000;
    var used = 0;
    final kept = <ImportedTurn>[];
    for (final turn in turns.reversed) {
      final text = turn.text.trim();
      if (text.isEmpty) continue;
      if (kept.length >= maxTurns || used >= maxChars) break;
      final clipped = text.length > 2000 ? '${text.substring(0, 2000)}…' : text;
      used += clipped.length;
      kept.add(ImportedTurn(fromUser: turn.fromUser, text: clipped));
    }
    return kept.reversed.toList(growable: false);
  }

  static String _dioReason(DioException error) {
    final code = error.response?.statusCode;
    if (code == 401 || code == 403) return '链接需要登录（HTTP $code）';
    if (code == 404) return '链接不存在或已失效（HTTP 404）';
    if (code != null) return 'HTTP $code';
    final type = error.type;
    return switch (type) {
      DioExceptionType.connectionTimeout => '连接超时',
      DioExceptionType.receiveTimeout => '读取超时',
      DioExceptionType.connectionError => '连不上服务器',
      _ => error.message ?? '网络错误',
    };
  }
}

final chatTranscriptImporterProvider = Provider<ChatTranscriptImporter>(
  (ref) => ChatTranscriptImporter(),
);
