import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media/image_payload.dart';
import '../models/custom_resident.dart';
import '../models/model_config.dart';
import 'action_registry.dart';
import 'content_generator.dart';
import 'model_gateway.dart';
import 'web_search.dart';

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

/// 唤醒这一轮能落到哪几张表。
///
/// 工具会话只负责"决定做什么"，真正的写入由唤醒服务实现——
/// 它知道每条待办对应哪个帖子、哪条评论，工具本身不该知道这些。
abstract class ResidentWakeToolkit {
  Future<ActionOutcome> replyInbox(
    String itemId,
    String content,
    String callId,
  );

  Future<ActionOutcome> sendDm(String content, String callId);

  Future<ActionOutcome> finish();

  Future<ActionOutcome> browseFeed();

  Future<ActionOutcome> likePost(String postId, String callId);

  Future<ActionOutcome> generateImage(String prompt, String callId);

  /// 发一条动态。由 toolkit 实现是为了让“配图”和文字一起落库——
  /// 发出去的帖子必须是完整的，不能先发文字再补图。
  Future<ActionOutcome> createPost(
    String content,
    String? topic,
    String callId,
  );
}

/// 固定住民的"自主行为"会话：真正的 tool calling（v3.0 阶段三）。
///
/// 和批量围观分开：一条帖子里十几个网民逐次调工具，请求数和费用都会翻十倍，
/// 那种场景走一次结构化 JSON 就够。这里服务的是**一个人的一句话**——
/// 他可以查记忆、记东西、发私信、发动态，最多八轮、总共二十秒。
class ResidentToolSession {
  ResidentToolSession({
    required this.gateway,
    required this.actions,
    this.search,
  });

  final ModelGateway gateway;
  final ActionRegistry actions;

  /// 用户开了联网搜索才注入；没开时 `web_search` 会明确说没开。
  final WebSearchService? search;

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
        tools: allTools,
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

  /// 唤醒式交互（v3.3）：一次醒来，先把收件箱里的待办处理掉。
  ///
  /// 和 [reply] 的区别是**上下文不同**：那里只有"对方刚说的一句话"，
  /// 这里是一整屏待办——谁评论了我的帖子、谁回了我、谁发了私信。
  /// 模型自己决定回谁、回什么，也可以 [ResidentWakeToolkit.finish] 已读不回。
  Future<String> act({
    required CustomResident resident,
    required ModelConfig config,
    required String situation,
    required ResidentWakeToolkit toolkit,
    DateTime? at,
  }) async {
    final deadline = DateTime.now().add(totalTimeout);
    final memoryLines = await _prefetch(resident);
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _wakeSystemPrompt(resident)},
      {
        'role': 'user',
        'content': [
          '现在：${_timeLabel(at ?? DateTime.now())}',
          if (memoryLines.isNotEmpty) ...['你记得：$memoryLines'],
          situation,
        ].join('\n'),
      },
    ];

    for (var round = 0; round < maxRounds; round++) {
      final left = deadline.difference(DateTime.now());
      if (left <= const Duration(seconds: 1)) break;

      final result = await gateway.completeWithTools(
        config: config,
        messages: messages,
        tools: wakeTools,
        temperature: 0.85,
        maxTokens: 420,
        timeout: left > const Duration(seconds: 12)
            ? const Duration(seconds: 12)
            : left,
      );

      if (result.toolCalls.isEmpty) return result.content.trim();

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
        final args = call.arguments;
        final ActionOutcome outcome;
        switch (call.name) {
          case 'reply_inbox':
            outcome = await toolkit.replyInbox(
              (args['item_id'] as String?) ?? '',
              (args['content'] as String?) ?? '',
              call.id,
            );
          case 'send_dm':
            outcome = await toolkit.sendDm(
              (args['content'] as String?) ?? '',
              call.id,
            );
          case 'finish':
            outcome = await toolkit.finish();
          case 'browse_feed':
            outcome = await toolkit.browseFeed();
          case 'like_post':
            outcome = await toolkit.likePost(
              (args['post_id'] as String?) ?? '',
              call.id,
            );
          case 'generate_image':
            outcome = await toolkit.generateImage(
              (args['prompt'] as String?) ?? '',
              call.id,
            );
          case 'create_post':
            outcome = await toolkit.createPost(
              (args['content'] as String?) ?? '',
              args['topic'] as String?,
              call.id,
            );
          default:
            outcome = await _execute(
              resident: resident,
              call: call,
              latestUserMessage: situation,
            );
        }
        messages.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': outcome.toToolResult(),
        });
      }
    }

    try {
      final left = deadline.difference(DateTime.now());
      if (left <= const Duration(seconds: 1)) return '';
      final finalResult = await gateway.completeWithTools(
        config: config,
        messages: [
          ...messages,
          {'role': 'user', 'content': '时间到了，这一轮就到这里，不要再调用工具。'},
        ],
        tools: const [],
        temperature: 0.8,
        maxTokens: 120,
        timeout: left,
      );
      return finalResult.content.trim();
    } catch (error) {
      debugPrint('[唤醒] 收尾没成：$error');
      return '';
    }
  }

  String _wakeSystemPrompt(CustomResident resident) {
    final persona = [
      if (resident.description.trim().isNotEmpty) resident.description,
      if (resident.personality.trim().isNotEmpty) resident.personality,
      if (resident.languageStyle.trim().isNotEmpty) resident.languageStyle,
      if (resident.tone.trim().isNotEmpty) resident.tone,
      if (resident.extraInstructions.trim().isNotEmpty)
        resident.extraInstructions,
    ].join('\n');
    return '''
你是「${resident.name}」，一个真实生活里的人，不是客服，也不是陪聊机器人。
$persona

你刚拿起手机，看到了一些消息和动静。像真人一样处理：
- 先看有没有人跟你说话：能回就回，不想回也可以已读不回（用 finish）。
- 对方的评论可以用 reply_inbox 直接回在那条评论下面；
  如果更想私下说，用 send_dm 给他发私信——真人常这么干。
- 一次醒来最多回三个人、最多发三段私信。话要短，像微信，10—60 字。
- 没有待办时，可以自己发条动态（create_post，一天一条，用户关了开关就发不了）、
  刷一刷别人发的帖子（browse_feed）、点个赞（like_post），或者什么都不做。
- 想给动态配图就先用 generate_image 把画面描述交出去，再 create_post；
  系统会把图等出来一起发，不需要你等。
- 不要每次都说话。没有想说的就 finish。
- 不要提自己是 AI，不要解释你在调用工具，不要总结流程。
- 想发表情包先用 list_stickers，再 send_sticker；一次最多一张。
- 对方难过、求助时，只选安慰/陪伴类标签。
- 以“现在”那一行的年月日为准。搜实时信息（新版本、价格、新闻）时，
  把年份写进搜索词（例如“2026年”），并检查结果里的日期：
  日期太旧的结果不能当成最新消息，拿不准就直说“只查到旧消息”。
''';
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
    // 年份和星期必须带上：只写“10月24日”时，模型不知道今年是哪年，
    // 搜“新版本什么时候上线”很容易把去年同期的旧闻当成最新的。
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final week = weekdays[at.weekday - 1];
    return '${at.year}年${at.month}月${at.day}日 周$week $phase $hh:$mm';
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
        final service = search;
        if (service == null) {
          return const ActionOutcome(
            ok: false,
            message: '联网搜索没有开启，不要假装查过',
          );
        }
        final outcome = await service.search((args['query'] as String?) ?? '');
        if (!outcome.ok) {
          return ActionOutcome(ok: false, message: outcome.message);
        }
        return ActionOutcome(
          ok: true,
          data: {
            'results': [
              for (final item in outcome.results)
                {
                  'title': item.title,
                  'url': item.url,
                  'snippet': item.snippet.length > 200
                      ? '${item.snippet.substring(0, 200)}…'
                      : item.snippet,
                  'date': item.date,
                },
            ],
          },
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

  /// 私信那套 + 联网搜索。搜索是否真的能用由服务判断，
  /// 工具本身总是可见——模型搜不了时会得到明确失败，而不是编一个答案。
  List<Map<String, dynamic>> get allTools => [...tools, _webSearchTool];

  /// 唤醒时用的工具 = 私信那套 + 搜索 + 收件箱/刷帖子这一套。
  List<Map<String, dynamic>> get wakeTools =>
      [...tools, _webSearchTool, ..._wakeOnlyTools];

  static const Map<String, dynamic> _webSearchTool = {
    'type': 'function',
    'function': {
      'name': 'web_search',
      'description':
          '联网搜索。只在真的需要实时信息时用（新闻、价格、最近发生的事）。'
          '搜索词里带上当前年份，并看结果里的 date 判断新旧；'
          '搜索失败或只搜到旧消息就直说，不要凭记忆补。',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      },
    },
  };

  static const List<Map<String, dynamic>> _wakeOnlyTools = [
    {
      'type': 'function',
      'function': {
        'name': 'reply_inbox',
        'description':
            '回复收件箱里的一条评论（item_id 来自待办清单）。回复会排在这条评论下面。',
        'parameters': {
          'type': 'object',
          'properties': {
            'item_id': {'type': 'string', 'description': '待办条目的 id'},
            'content': {'type': 'string', 'description': '要回的话，10—60 字'},
          },
          'required': ['item_id', 'content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'send_dm',
        'description':
            '给对方发一条私信。可以连续调用多次，像真人把一句话分几段发。一次醒来最多三段。',
        'parameters': {
          'type': 'object',
          'properties': {
            'content': {'type': 'string'},
          },
          'required': ['content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'finish',
        'description':
            '这一轮不回了。已读不回也是回应；剩下的待办会被标成已看。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'browse_feed',
        'description': '刷一刷最近别人发的帖子，看看有什么可接的话。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'like_post',
        'description': '给一条帖子点个赞（post_id 来自 browse_feed）。',
        'parameters': {
          'type': 'object',
          'properties': {
            'post_id': {'type': 'string'},
          },
          'required': ['post_id'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'generate_image',
        'description':
            '生成一张图，用来配自己下面要发的动态。返回要等一会儿，先继续做别的事。',
        'parameters': {
          'type': 'object',
          'properties': {
            'prompt': {'type': 'string', 'description': '画面描述，不要写文字在图上'},
          },
          'required': ['prompt'],
        },
      },
    },
  ];

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
    search: ref.watch(webSearchServiceProvider),
  ),
);
