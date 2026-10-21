import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media/image_payload.dart';
import '../models/custom_resident.dart';
import '../models/model_config.dart';
import 'action_registry.dart';
import 'content_generator.dart';
import 'model_gateway.dart';

/// 这一轮选中的表情包。
///
/// 工具只做“选哪张”的决策；真正落库由 DirectMessageService 通过
/// ActionRegistry 统一写入，保住幂等和动作日志。
class ResidentStickerChoice {
  const ResidentStickerChoice({
    required this.callId,
    required this.id,
    required this.path,
  });

  final String callId;
  final String id;
  final String path;
}

/// 固定住民这一轮要发的东西：一句话 + 最多一张表情包。
class ResidentReply {
  const ResidentReply({this.text = '', this.stickers = const []});

  final String text;
  final List<ResidentStickerChoice> stickers;
}

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
  Future<ResidentReply?> reply({
    required CustomResident resident,
    required ModelConfig config,
    required List<DirectTurn> recent,
    required String latestUserMessage,
    DateTime? at,
  }) async {
    final deadline = DateTime.now().add(totalTimeout);
    final memoryLines = await _prefetch(resident);
    final stickers = <ResidentStickerChoice>[];
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': _systemPrompt(resident),
      },
      ...await _historyMessages(
        recent: recent,
        config: config,
        latest: latestUserMessage,
        memoryLines: memoryLines,
        at: at,
      ),
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
        return ResidentReply(
          text: result.content.trim(),
          stickers: stickers,
        );
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
        final ActionOutcome outcome;
        if (call.name == 'send_sticker' && stickers.isNotEmpty) {
          outcome = const ActionOutcome(
            ok: false,
            message: '一次回复最多发一张表情包',
          );
        } else {
          outcome = await _execute(
            resident: resident,
            call: call,
            latestUserMessage: latestUserMessage,
          );
          if (call.name == 'send_sticker' && outcome.ok) {
            final id = outcome.data['sticker_id'];
            final path = outcome.data['path'];
            if (id is String && path is String) {
              stickers.add(
                ResidentStickerChoice(
                  callId: call.id,
                  id: id,
                  path: path,
                ),
              );
            }
          }
        }
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
      if (left <= const Duration(seconds: 1)) {
        return ResidentReply(stickers: stickers);
      }
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
      return ResidentReply(
        text: finalResult.content.trim(),
        stickers: stickers,
      );
    } catch (error) {
      debugPrint('[工具] 收尾也没成：$error');
      return ResidentReply(stickers: stickers);
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
- 想发表情包时，先用 list_stickers 看目录，再用 send_sticker 选一张；
  一次回复最多一张，没有合适的就纯文字。
- 对方难过、求助时，只能选安慰/抱抱/陪伴/鼓励这类标签，不要用吐槽/看戏类。
''';
  }

  /// 把最近几轮组装成真正的 user/assistant 消息。
  ///
  /// - system 只放人设和规则，逐字节稳定；
  /// - 历史原样保留，图片留在它被发出来的那一轮；
  /// - 时间、记忆、这一轮的提示放在**最后一条 user 消息**里，
  ///   不会因为每轮都变而把前缀打碎。
  Future<List<Map<String, dynamic>>> _historyMessages({
    required List<DirectTurn> recent,
    required ModelConfig config,
    required String latest,
    required String memoryLines,
    DateTime? at,
  }) async {
    final messages = <Map<String, dynamic>>[];

    for (final turn in recent) {
      if (turn.fromMe) {
        messages.add({
          'role': 'assistant',
          'content': turn.text.trim().isEmpty ? '[表情包]' : turn.text.trim(),
        });
        continue;
      }

      final text = turn.text.trim().isEmpty
          ? '[对方发来一张图片]'
          : turn.text.trim();
      Map<String, dynamic>? image;
      if (turn.imageRef != null && config.supportsVision) {
        image = await ImagePayload.partFromRef(turn.imageRef!);
      }
      messages.add({
        'role': 'user',
        'content': image == null
            ? text
            : [
                {'type': 'text', 'text': text},
                image,
              ],
      });
    }

    final tail = StringBuffer()
      ..writeln('现在：${_timeLabel(at ?? DateTime.now())}');
    if (memoryLines.isNotEmpty) {
      tail
        ..writeln('你们以前聊过（仅供参考）：')
        ..writeln(memoryLines);
    }
    if (latest.trim().isNotEmpty &&
        (recent.isEmpty || recent.last.fromMe)) {
      tail.writeln('他刚说：${latest.trim()}');
    }
    tail.writeln('直接回他一句。');

    final tailText = tail.toString().trim();
    if (messages.isNotEmpty && messages.last['role'] == 'user') {
      final content = messages.last['content'];
      if (content is String) {
        messages.last['content'] = [
          {'type': 'text', 'text': '$content\n\n$tailText'},
        ];
      } else if (content is List) {
        content.add({'type': 'text', 'text': tailText});
      }
    } else {
      messages.add({'role': 'user', 'content': tailText});
    }
    return messages;
  }

  static String _timeLabel(DateTime at) {
    final phase = switch (at.hour) {
      >= 5 && < 8 => '清晨',
      >= 8 && < 11 => '上午',
      >= 11 && < 14 => '中午',
      >= 14 && < 17 => '下午',
      >= 17 && < 19 => '傍晚',
      >= 19 && < 23 => '晚上',
      _ => '深夜',
    };
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '${at.month}月${at.day}日 $phase $hh:$mm';
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
      case 'list_stickers':
        return actions.listStickers();
      case 'send_sticker':
        return actions.chooseSticker(
          id: (args['sticker_id'] as String?) ?? '',
          tag: (args['tag'] as String?) ?? '',
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
    {
      'type': 'function',
      'function': {
        'name': 'list_stickers',
        'description': '看看当前有哪些带标签的表情包可用（id、名称、标签）。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'send_sticker',
        'description':
            '发一张表情包。一次回复最多一张；对方难过时只选安慰/陪伴类标签。',
        'parameters': {
          'type': 'object',
          'properties': {
            'sticker_id': {
              'type': 'string',
              'description': 'list_stickers 返回的 id，优先用它',
            },
            'tag': {
              'type': 'string',
              'description': '没给 id 时按标签匹配；匹配到多张会要求重选',
            },
          },
        },
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
