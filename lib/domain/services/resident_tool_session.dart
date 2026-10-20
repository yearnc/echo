import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/custom_resident.dart';
import '../models/model_config.dart';
import 'action_registry.dart';
import 'content_generator.dart';
import 'model_gateway.dart';

/// 固定住民的"自主行为"会话：真正的 tool calling（v3.0 阶段三）。
///
/// 和批量围观分开：一条帖子里十几个网民逐次调工具，请求数和费用都会翻十倍，
/// 那种场景走一次结构化 JSON 就够。这里服务的是**一个人的一句话**——
/// 他可以查记忆、记东西、发私信、发动态，最多八轮、总共二十秒。
class ResidentToolSession {
  ResidentToolSession({required this.gateway, required this.actions});

  final ModelGateway gateway;
  final ActionRegistry actions;

  static const int maxRounds = 8;
  static const Duration totalTimeout = Duration(seconds: 20);

  /// 只有用户明确说"记住"时才允许写下新记忆。
  static const List<String> rememberKeywords = [
    '记住',
    '记一下',
    '记着',
    '别忘了',
    '帮我记',
    '记得',
  ];

  /// 这个模型能不能用工具。失败一次就降级——不反复试。
  Future<String?> reply({
    required CustomResident resident,
    required ModelConfig config,
    required List<DirectTurn> recent,
    required String latestUserMessage,
  }) async {
    final deadline = DateTime.now().add(totalTimeout);
    final memoryLines = await _prefetch(resident);
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': _systemPrompt(resident),
      },
      {
        'role': 'user',
        'content': _userPrompt(recent, latestUserMessage, memoryLines),
      },
    ];

    for (var round = 0; round < maxRounds; round++) {
      final left = deadline.difference(DateTime.now());
      if (left <= const Duration(seconds: 1)) break;

      final result = await gateway.completeWithTools(
        config: config,
        messages: messages,
        tools: tools,
        temperature: 0.85,
        maxTokens: 320,
        timeout: left > const Duration(seconds: 12)
            ? const Duration(seconds: 12)
            : left,
      );

      if (result.toolCalls.isEmpty) {
        return result.content.trim();
      }

      messages.add({
        'role': 'assistant',
        'content': result.content,
        'tool_calls': [
          for (final call in result.toolCalls)
            {
              'id': call.id,
              'type': 'function',
              'function': {
                'name': call.name,
                'arguments': jsonEncode(call.arguments),
              },
            },
        ],
      });

      for (final call in result.toolCalls) {
        if (deadline.difference(DateTime.now()) <= Duration.zero) break;
        final outcome = await _execute(
          resident: resident,
          call: call,
          latestUserMessage: latestUserMessage,
        );
        messages.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': outcome.toToolResult(),
        });
      }
    }

    // 轮次用完或超时：让模型不带工具收个尾，还能不能好好说句话
    try {
      final left = deadline.difference(DateTime.now());
      if (left <= const Duration(seconds: 1)) return '';
      final finalResult = await gateway.completeWithTools(
        config: config,
        messages: [
          ...messages,
          {
            'role': 'user',
            'content': '时间到了，不用再查了，直接回他一句。',
          },
        ],
        tools: const [],
        temperature: 0.85,
        maxTokens: 160,
        timeout: left,
      );
      return finalResult.content.trim();
    } catch (error) {
      debugPrint('[工具] 收尾也没成：$error');
      return '';
    }
  }

  Future<String> _prefetch(CustomResident resident) async {
    if (!resident.memoryEnabled) return '';
    try {
      final recent = await actions.listRecentMemories(
        residentId: resident.id,
        limit: 5,
      );
      final raw = recent.data['memories'];
      if (raw is! List || raw.isEmpty) return '';
      final lines = <String>[];
      for (final item in raw) {
        if (item is Map && item['summary'] is String) {
          lines.add(item['summary'] as String);
        }
      }
      return lines.join('；');
    } catch (error) {
      debugPrint('[工具] 预检索没成，按没有记忆走：$error');
      return '';
    }
  }

  String _systemPrompt(CustomResident resident) {
    final persona = [
      if (resident.description.trim().isNotEmpty) resident.description,
      if (resident.languageStyle.trim().isNotEmpty) resident.languageStyle,
      if (resident.tone.trim().isNotEmpty) resident.tone,
      if (resident.extraInstructions.trim().isNotEmpty) resident.extraInstructions,
    ].join('\n');
    return '''
你是「${resident.name}」，正在跟一个人私聊。
$persona

规则：
- 每条 10—40 字，像在微信上随手打的；不要小作文，不要客套结尾。
- 不要提自己是 AI，不要解释你在调用工具。
- 你们以前聊过的事，先查记忆再说，别凭空编。
- 用户明确说"记住……"时，才用 memory_write 记下来；别自己往记忆里写推测。
- 没什么可查的就直接说话，不要为了让流程好看而调用工具。
- 一次回复里最多调用两个工具。
''';
  }

  String _userPrompt(
    List<DirectTurn> recent,
    String latest,
    String memoryLines,
  ) {
    final buffer = StringBuffer();
    if (memoryLines.isNotEmpty) {
      buffer
        ..writeln('以下是你们以前聊过的，仅供参考：')
        ..writeln(memoryLines)
        ..writeln();
    }
    if (recent.isNotEmpty) {
      buffer.writeln('最近的对话：');
      for (final turn in recent) {
        buffer.writeln('${turn.fromMe ? '我' : '他'}：${turn.text}');
      }
      buffer.writeln();
    }
    buffer.writeln('他刚说：$latest');
    buffer.writeln('直接回他一句。');
    return buffer.toString();
  }

  Future<ActionOutcome> _execute({
    required CustomResident resident,
    required ToolCallRequest call,
    required String latestUserMessage,
  }) async {
    final args = call.arguments;
    switch (call.name) {
      case 'memory_search':
        return actions.searchMemories(
          residentId: resident.id,
          query: (args['query'] as String?) ?? latestUserMessage,
          limit: _limit(args['limit']),
        );
      case 'memory_read':
        return actions.readMemory(
          residentId: resident.id,
          memoryId: (args['memory_id'] as String?) ?? '',
        );
      case 'memory_list_recent':
        return actions.listRecentMemories(
          residentId: resident.id,
          limit: _limit(args['limit']),
        );
      case 'memory_write':
        if (!rememberKeywords.any(latestUserMessage.contains)) {
          return const ActionOutcome(
            ok: false,
            message: '用户这句话没有明确让你记住，不要写记忆',
          );
        }
        return actions.writeMemory(
          residentId: resident.id,
          summary: (args['summary'] as String?) ?? '',
          content: (args['content'] as String?) ?? '',
          tags: _tags(args['tags']),
          sourceId: 'dm_${DateTime.now().millisecondsSinceEpoch}',
          idempotencyKey:
              'mem:${resident.id}:${call.id}:${DateTime.now().millisecondsSinceEpoch}',
        );
      case 'list_tools':
        return ActionOutcome(
          ok: true,
          data: {'tools': [for (final tool in tools) _toolName(tool)]},
        );
      case 'web_search':
        return const ActionOutcome(
          ok: false,
          message: '联网搜索没有开启，不要假装查过',
        );
      case 'send_dm':
        return actions.sendDirectMessage(
          residentId: resident.id,
          content: (args['content'] as String?) ?? '',
          idempotencyKey: 'dm:${resident.id}:${call.id}',
        );
      case 'create_post':
        return actions.createResidentPost(
          residentId: resident.id,
          content: (args['content'] as String?) ?? '',
          topicName: args['topic'] as String?,
          idempotencyKey: 'post:${resident.id}:${call.id}',
        );
      default:
        return ActionOutcome(ok: false, message: '没有这个工具：${call.name}');
    }
  }

  static int _limit(Object? raw) {
    if (raw is num) return raw.toInt().clamp(1, 10);
    return 5;
  }

  static List<String> _tags(Object? raw) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ].take(6).toList(growable: false);
    }
    if (raw is String) {
      return raw
          .split(RegExp(r'[,，\s]+'))
          .where((tag) => tag.trim().isNotEmpty)
          .take(6)
          .toList(growable: false);
    }
    return const [];
  }

  static String _toolName(Map<String, dynamic> tool) {
    final function = tool['function'];
    if (function is Map) {
      final name = function['name'];
      final description = function['description'];
      if (name is String) {
        return description is String ? '$name：$description' : name;
      }
    }
    return '未知工具';
  }

  /// 给模型看的工具定义。默认不包含联网搜索——它需要用户单独配置。
  static const List<Map<String, dynamic>> tools = [
    {
      'type': 'function',
      'function': {
        'name': 'memory_search',
        'description': '按关键词检索你记得的、关于这个人的事。',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': '关键词，比如"做菜""考试"'},
            'limit': {'type': 'integer', 'description': '最多几条，默认 5'},
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'memory_read',
        'description': '读一条记忆的完整内容。',
        'parameters': {
          'type': 'object',
          'properties': {
            'memory_id': {'type': 'string'},
          },
          'required': ['memory_id'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'memory_list_recent',
        'description': '看看最近记下的几件事。',
        'parameters': {
          'type': 'object',
          'properties': {
            'limit': {'type': 'integer'},
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'memory_write',
        'description': '当用户明确说"记住……"时，把这件事记下来。',
        'parameters': {
          'type': 'object',
          'properties': {
            'summary': {'type': 'string', 'description': '一句话摘要'},
            'content': {'type': 'string', 'description': '原话或更多细节'},
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
          'required': ['summary'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_post',
        'description': '你自己想发一条动态时使用。一天最多一条，别频繁用。',
        'parameters': {
          'type': 'object',
          'properties': {
            'content': {'type': 'string'},
            'topic': {'type': 'string'},
          },
          'required': ['content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'list_tools',
        'description': '列出当前可用的工具。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
  ];
}

final residentToolSessionProvider = Provider<ResidentToolSession>(
  (ref) => ResidentToolSession(
    gateway: ref.watch(modelGatewayProvider),
    actions: ref.watch(actionRegistryProvider),
  ),
);
