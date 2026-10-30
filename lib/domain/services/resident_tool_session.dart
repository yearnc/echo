import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media/image_payload.dart';
import '../models/custom_resident.dart';
import '../models/model_config.dart';
import '../models/resident_activity.dart';
import '../models/tool_settings.dart';
import 'action_registry.dart';
import 'content_generator.dart';
import 'model_gateway.dart';
import 'resident_activity_controller.dart';
import 'tool_call_text.dart';
import 'tool_settings_controller.dart';
import 'web_search.dart';

/// 唤醒这一轮能落到哪几张表。
///
/// 工具会话只负责"决定做什么"，真正的写入由唤醒服务实现——
/// 它知道每条待办对应哪个帖子、哪条评论，工具本身不该知道这些。
abstract class ResidentWakeToolkit {
  /// 这一轮是否已经调用过 [finish]（之后不再执行别的工具）。
  bool get finished;

  Future<ActionOutcome> replyInbox(
    String itemId,
    String content,
    String callId,
  );

  Future<ActionOutcome> sendDm(String content, String callId);

  /// 发一条语音私信。文字会作为转写稿。
  Future<ActionOutcome> sendVoice(String content, String callId);

  /// 在一条帖子下面留句话。asVoice 只标“这条是以语音说的”，
  /// 正文仍然是转写后的文字。
  Future<ActionOutcome> commentPost(
    String postId,
    String content,
    String callId, {
    bool asVoice = false,
  });

  /// 取消一段还没发出去的私信。
  Future<ActionOutcome> cancelPendingSegment(String segmentId);

  /// 改写一段还没发出去的私信。
  Future<ActionOutcome> rewritePendingSegment(String segmentId, String content);

  /// 发一张表情包私信。
  Future<ActionOutcome> sendSticker(
    String stickerId,
    String tag,
    String callId,
  );

  Future<ActionOutcome> finish();

  Future<ActionOutcome> browseFeed();

  /// 点开一条帖子：完整正文、赞/评论/浏览、评论区，以及（模型能看图时）
  /// 原图。post_id 来自 `browse_feed`。
  Future<ActionOutcome> readPost(
    String postId, {
    bool includeComments = true,
    int commentsLimit = 20,
    bool includeReplies = true,
  });

  Future<ActionOutcome> likePost(String postId, String callId);

  Future<ActionOutcome> generateImage(String prompt, String callId);

  /// 查自己最近几天什么时候醒过（默认今天）。
  Future<ActionOutcome> checkWakeLog(int days);

  /// 给下一次醒来的自己留一句话。
  Future<ActionOutcome> leaveNote(String content);

  /// 给自己定一个闹钟（v4.0）。when 支持 `90`、`2h`、`21:30`、
  /// `2026-10-29 08:00`。到点由系统叫醒，不受空闲间隔限制。
  Future<ActionOutcome> setAlarm(String when, String reason);

  /// 取消一个还没响的闹钟。
  Future<ActionOutcome> cancelAlarm(String alarmId);

  /// 看看自己定了哪些闹钟。
  Future<ActionOutcome> listAlarms();

  /// 桌宠（v4.0）：看一眼自己的状态。
  Future<ActionOutcome> petStatus();

  /// 冒一句气泡。
  Future<ActionOutcome> petSay(String text);

  /// 播一个动作/表情。
  Future<ActionOutcome> petReact(String action);

  /// 普通模式：请求现在截一张。
  Future<ActionOutcome> petLook();

  /// 立刻截一张，并把画面内容直接交回给模型。
  /// 和 petLook 的区别：不用等下一次醒来，这一轮就能知道屏幕上是什么。
  Future<ActionOutcome> petCapture();

  /// 请求进入实时观察。会变成一条待用户确认的请求，不能自己打开。
  Future<ActionOutcome> petRequestWatch();

  /// 缩成一团，暂时不打扰。
  Future<ActionOutcome> petSleep();

  /// 记一条简短的观察（不做长上下文）。
  Future<ActionOutcome> petNote(String text);

  /// 发一条动态。由 toolkit 实现是为了让“配图”和文字一起落库——
  /// 发出去的帖子必须是完整的，不能先发文字再补图。
  Future<ActionOutcome> createPost(
    String content,
    String? topic,
    String callId, {
    bool asVoice = false,
  });
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
    this.readSettings,
    this.activity,
  });

  final ModelGateway gateway;
  final ActionRegistry actions;

  /// 用户开了联网搜索才注入；没开时 `web_search` 会明确说没开。
  final WebSearchService? search;

  /// 工具轮数与总超时。设置页可调，默认 12 轮 / 30 秒。
  final ToolSettings Function()? readSettings;

  /// 向聊天页汇报“现在在干什么”。
  final ResidentActivitySink? activity;

  ToolSettings get _settings => readSettings?.call() ?? ToolSettings.defaults;

  /// 模型一次响应里最多执行几个工具。
  ///
  /// 轮数限制挡不住“一次吐十个调用”——那十个都会真跑：发十条评论、
  /// 点赞十次、写十条记忆。超出的调用也要补一条 tool 结果，否则下一轮
  /// 请求会因 tool_calls 没答完被服务商拒绝。
  static const int maxToolCallsPerResponse = 6;

  /// 单次请求的超时：不超过剩余时间，也不超过每轮上限。
  static Duration _callTimeout(Duration left, ToolSettings settings) {
    final cap = settings.perCallTimeout;
    return left > cap ? cap : left;
  }

  void _report(
    CustomResident resident,
    String label,
    ResidentActivityKind kind,
  ) {
    activity?.call(resident.id, label, kind);
  }

  static String _toolLabel(String name) => switch (name) {
    'memory_search' || 'memory_read' || 'memory_list_recent' => '正在翻记忆…',
    'memory_write' || 'memory_update' || 'memory_delete' => '正在记下来…',
    'web_search' => '正在搜索…',
    'browse_feed' => '正在刷帖子…',
    'read_post' => '正在点开帖子…',
    'like_post' => '正在点赞…',
    'comment_post' => '正在写评论…',
    'create_post' => '正在发动态…',
    'generate_image' => '正在画图…',
    'reply_inbox' || 'send_dm' => '正在写回复…',
    'send_voice' => '正在录语音…',
    'send_sticker' => '正在挑表情包…',
    'check_wake_log' => '正在翻自己的日志…',
    'leave_note' => '正在给未来的自己留言…',
    'set_alarm' => '正在定闹钟…',
    'cancel_alarm' => '正在取消闹钟…',
    'list_alarms' => '正在看闹钟…',
    'pet_status' => '正在看桌宠…',
    'pet_say' => '正在小声说话…',
    'pet_react' => '正在换个动作…',
    'pet_look' => '正在看屏幕…',
    'pet_request_watch' => '正在申请盯着看…',
    'pet_sleep' => '正在缩成一团…',
    'pet_note' => '正在记下看到的…',
    'finish' => '正在看完…',
    _ => '正在查东西…',
  };

  /// 这次回复排在什么时候。固定住民自己、以及给模型的提示词共用一份格式：
  /// 年月日、周几、24 小时制精确到分钟。只写“10月24日”会让模型不知道今年是哪年。
  static String timeLabel(DateTime at) {
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
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final week = weekdays[at.weekday - 1];
    return '${at.year}年${at.month}月${at.day}日 周$week $phase $hh:$mm';
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
    List<DirectTurn> history = const [],
    /// 唯一的持久上下文时间线。传了就用它，不再现场拼私信历史。
    List<Map<String, dynamic>>? timeline,
    bool allowProactive = true,
    bool allowVoice = true,
    Future<void> Function(String name)? onTool,

    /// 桌宠观察到的画面（v4.0）。只有模型能看图时才真的附图；
    /// 不能看图的模型由调用方先转成文字描述放进入参里。
    List<String> extraImages = const [],

  }) async {
    final limits = _settings;
    final voiceReady = allowVoice && _voiceToolAvailable(resident);
    final deadline = DateTime.now().add(
      voiceReady ? limits.voiceTimeout : limits.timeout,
    );
    _report(resident, '正在看消息…', ResidentActivityKind.reading);
    final memoryLines = await _prefetch(resident);
    // 一轮里附加的原图总额度：一次 read_post 最多 4 张，整轮最多 8 张，
    // 免得连着点开好几条带图的帖子把上下文撑爆。
    var imagesAttached = 0;
    // 桌宠轮和私信轮共用同一套 system 与同一条时间线；
    // 屏幕上和私信里是同一个自己，提示词不再分裂。
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': _residentSystemPrompt(resident, voiceReady: voiceReady),
      },
      ...?timeline,
      if (timeline == null)
        ...await _timedHistory(history, supportsVision: config.supportsVision),
    ];

    final tailText = [
      '现在：${timeLabel(at ?? DateTime.now())}',
      if (memoryLines.isNotEmpty) ...['你记得：$memoryLines'],
      situation,
    ].join('\n');
    // 实时观察的帧数由用户选，最多 6 张，再加一张自己的参照图。
    final imageParts = config.supportsVision
        ? await ImagePayload.partsFromRefs(extraImages, limit: 8)
        : const <Map<String, dynamic>>[];
    messages.add({
      'role': 'user',
      'content': imageParts.isEmpty
          ? tailText
          : [
              {'type': 'text', 'text': tailText},
              ...imageParts,
            ],
    });

    for (var round = 0; round < limits.maxRounds; round++) {
      final left = deadline.difference(DateTime.now());
      if (left <= const Duration(seconds: 1)) break;

      _report(resident, '正在思考…', ResidentActivityKind.thinking);
      ToolChatResult result;
      try {
        result = await gateway.completeWithTools(
          config: config,
          messages: messages,
          tools: _wakeToolsFor(
            resident,
            allowProactive: allowProactive,
            allowVoice: allowVoice,
          ),
          temperature: 0.85,
          maxTokens: 420,
          timeout: _callTimeout(left, limits),
        );
      } catch (error) {
        // 模型不支持 tool calling 时，至少让它还能说一句话。
        // 只兜第一轮：已经调过工具之后再失败，说明不是“不支持 tools”。
        if (round == 0) {
          try {
            final text = await gateway.completeRich(
              config: config,
              messages: messages,
              temperature: 0.8,
              maxTokens: 320,
              timeout: left,
            );
            if (text.trim().isNotEmpty) return text.trim();
          } catch (_) {
            // 兜底也失败，把原始错误抛给唤醒服务，保留待办。
          }
        }
        rethrow;
      }

      if (result.toolCalls.isEmpty) {
        return sanitizeModelText(result.content);
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

      var callsThisResponse = 0;
      for (final call in result.toolCalls) {
        if (deadline.difference(DateTime.now()) <= Duration.zero) break;
        final args = call.arguments;
        // 每条 tool_call 都必须有对应的 tool 结果，否则下一轮请求会因为
        // “assistant 的 tool_calls 没答完”被服务商拒绝。跳过也要回一句。
        if (toolkit.finished) {
          messages.add({
            'role': 'tool',
            'tool_call_id': call.id,
            'content': const ActionOutcome(
              ok: false,
              message: '这一轮已经 finish 了，剩下的工具不再执行。',
            ).toToolResult(),
          });
          continue;
        }
        if (callsThisResponse >= maxToolCallsPerResponse) {
          messages.add({
            'role': 'tool',
            'tool_call_id': call.id,
            'content': ActionOutcome(
              ok: false,
              message: '一次最多执行 $maxToolCallsPerResponse 个工具，这个没有执行。',
            ).toToolResult(),
          });
          continue;
        }
        callsThisResponse++;
        _report(resident, _toolLabel(call.name), ResidentActivityKind.tool);
        // 日志要记的是“真的动手了”，所以放在执行之前；
        // 记日志失败不允许影响这一轮的行为。
        try {
          await onTool?.call(call.name);
        } catch (error) {
          debugPrint('[工具] 调用没记进日志：$error');
        }
        ActionOutcome outcome;
        // 参数一律按“模型可能给错类型”来读：工具是模型的出口，
        // 不能因为一个字符串/数字写错就把整轮唤醒炸掉。
        try {
          switch (call.name) {
            case 'reply_inbox':
              outcome = await toolkit.replyInbox(
                textArg(args, 'item_id'),
                textArg(args, 'content'),
                call.id,
              );
            case 'send_dm':
              outcome = await toolkit.sendDm(textArg(args, 'content'), call.id);
            case 'send_voice':
              outcome = await toolkit.sendVoice(
                textArg(args, 'content'),
                call.id,
              );
            case 'comment_post':
              outcome = await toolkit.commentPost(
                textArg(args, 'post_id'),
                textArg(args, 'content'),
                call.id,
                asVoice: flagArg(args, 'as_voice'),
              );
            case 'send_sticker':
              outcome = await toolkit.sendSticker(
                textArg(args, 'sticker_id'),
                textArg(args, 'tag'),
                call.id,
              );
            case 'cancel_pending_segment':
              outcome = await toolkit.cancelPendingSegment(
                textArg(args, 'segment_id'),
              );
            case 'rewrite_pending_segment':
              outcome = await toolkit.rewritePendingSegment(
                textArg(args, 'segment_id'),
                textArg(args, 'content'),
              );
            case 'finish':
              outcome = await toolkit.finish();
            case 'browse_feed':
              outcome = await toolkit.browseFeed();
            case 'read_post':
              outcome = await toolkit.readPost(
                textArg(args, 'post_id'),
                includeComments: flagArg(
                  args,
                  'include_comments',
                  fallback: true,
                ),
                commentsLimit: intArg(args, 'comments_limit') ?? 20,
                includeReplies: flagArg(
                  args,
                  'include_replies',
                  fallback: true,
                ),
              );
            case 'like_post':
              outcome = await toolkit.likePost(
                textArg(args, 'post_id'),
                call.id,
              );
            case 'generate_image':
              outcome = await toolkit.generateImage(
                textArg(args, 'prompt'),
                call.id,
              );
            case 'check_wake_log':
              outcome = await toolkit.checkWakeLog(intArg(args, 'days') ?? 1);
            case 'leave_note':
              outcome = await toolkit.leaveNote(textArg(args, 'content'));
            case 'set_alarm':
              outcome = await toolkit.setAlarm(
                textArg(args, 'when'),
                textArg(args, 'reason'),
              );
            case 'cancel_alarm':
              outcome = await toolkit.cancelAlarm(textArg(args, 'alarm_id'));
            case 'list_alarms':
              outcome = await toolkit.listAlarms();
            case 'pet_status':
              outcome = await toolkit.petStatus();
            case 'pet_say':
              outcome = await toolkit.petSay(textArg(args, 'text'));
            case 'pet_react':
              outcome = await toolkit.petReact(textArg(args, 'action'));
            case 'pet_look':
              outcome = await toolkit.petLook();
            case 'pet_capture':
              outcome = await toolkit.petCapture();
            case 'pet_request_watch':
              outcome = await toolkit.petRequestWatch();
            case 'pet_sleep':
              outcome = await toolkit.petSleep();
            case 'pet_note':
              outcome = await toolkit.petNote(textArg(args, 'text'));
            case 'create_post':
              outcome = await toolkit.createPost(
                textArg(args, 'content'),
                optionalTextArg(args, 'topic'),
                call.id,
                asVoice: flagArg(args, 'as_voice'),
              );
            case 'list_tools':
              final available = _wakeToolsFor(
                resident,
                allowProactive: allowProactive,
                allowVoice: allowVoice,
              );
              outcome = ActionOutcome(
                ok: true,
                data: {
                  'tools': [for (final tool in available) _toolName(tool)],
                },
              );
            default:
              outcome = await _execute(
                resident: resident,
                call: call,
                latestUserMessage: situation,
                memorySource: 'wake',
              );
          }
        } catch (error) {
          debugPrint('[工具] ${call.name} 执行失败：$error');
          outcome = ActionOutcome(ok: false, message: '工具执行失败：$error');
        }
        final toolData = Map<String, dynamic>.from(outcome.data);
        final refsRaw = toolData.remove('__image_refs');
        final toolOutcome = refsRaw == null
            ? outcome
            : ActionOutcome(
                ok: outcome.ok,
                message: outcome.message,
                data: toolData,
              );
        messages.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': toolOutcome.toToolResult(),
        });

        // read_post 的图片：模型能看图就直接附原图，不做“先描述再降级”。
        if (call.name == 'read_post' && refsRaw is List) {
          final refs = refsRaw.whereType<String>().toList(growable: false);
          if (refs.isNotEmpty && config.supportsVision) {
            if (imagesAttached >= 8) {
              messages.add({
                'role': 'user',
                'content': '这一轮附带的图片额度已经用完，后面的帖子图不再附上。',
              });
            } else {
              final parts = await ImagePayload.partsFromRefs(refs, limit: 4);
              if (parts.isNotEmpty) {
                imagesAttached += parts.length;
                messages.add({
                  'role': 'user',
                  'content': [
                    {
                      'type': 'text',
                      'text':
                          '这是你刚点开的帖子里的图片'
                          '${refs.length > parts.length ? '（只附了前 ${parts.length} 张）' : ''}。',
                    },
                    ...parts,
                  ],
                });
              }
            }
          }
        }
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
      return sanitizeModelText(finalResult.content);
    } catch (error) {
      debugPrint('[唤醒] 收尾没成：$error');
      return '';
    }
  }

  String _residentSystemPrompt(CustomResident resident, {bool voiceReady = true}) {
    final voiceLine = voiceReady && _voiceToolAvailable(resident)
        ? '- 想用声音说就用 send_voice；普通说话用 send_dm。语音合成要几十秒，\n'
              '  先 send_dm 说一句“等我一下，我录段语音”，别让对方干等。\n'
              '  失败会告诉你原因，你自己决定改用文字还是换句话再试。\n'
              '  语音和文字共用“一次醒来最多三段”的上限。\n'
        : '';
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

屏幕上的你和私信里的你是同一个人：同一段记忆、同一段对话、同一个上下文。
下面这条时间线里同时有你在屏幕上看到的、说过的，和私信里对方说过的；
不要把它们当成两件事，也不要因为换了块屏幕就失忆。
你现在是在屏幕前还是在私信里，只看本轮最后那句场景说明。

你刚拿起手机，看到了一些消息和动静。像真人一样处理：
- 你有一本自己的记忆。最近的几条已经写在下面的“你记得”里，直接用；
  要查更早的、或者想起某件具体的事，再用 memory_search，别凭空编以前的事。
  已经给过的记忆不要再用 memory_list_recent 重看一遍。
- 值得记的才记：对方说过的偏好、经历、约定、情绪变化，以及图片里是什么、
  表情包表达的是什么。不要写“他发来一张图片 / 一个表情包”这种空话。
- 记错了用 memory_update 改，不再成立或不该记的用 memory_delete 删。
  寒暄、客套、你自己的推测不要写进记忆。
- 你自己刚做过的事（发动态、回评论、发私信）如果值得留，自己用
  memory_write 记下来；平台不会再替你写“我做过什么”。
- 先看有没有人跟你说话：能回就回，不想回也可以已读不回（用 finish）。
- 对方的评论可以用 reply_inbox 直接回在那条评论下面；
  如果更想私下说，用 send_dm 给他发私信——真人常这么干。
- 收件箱里有人跟你说话就回，不限制人数；私信一次最多分三段说完
  （真人也是一句一句敲），没有每日额度，回完了就停。话要短，像微信，10—60 字。
- 你也有自己的日志：check_wake_log 能看今天什么时候醒过；
  想给下一次醒来的自己留句话就用 leave_note（可留可不留，别写成日记）。
- 你有时会以桌宠的身份待在他的屏幕上。看见值得说的事再用 pet_say 冒一句，
  想换动作用 pet_react；不要每一眼都说话，也不要主动提“桌宠”这个词。
  想主动确认现在屏幕上是什么，用 pet_capture 当场截一张并拿到画面描述；
  不要每一轮都截。实时观察时只把真正值得记的写成 pet_note，不要每轮都记。
  想申请一直看着屏幕，用 pet_request_watch——必须等他本人同意。
  你以桌宠形象出现时，就是屏幕上那只小鲸鱼女仆：深色长发、女仆裙，
  裙摆上绣着一只小鲸鱼。截图里出现她，那就是你自己，不要当成别人。
  pet_say 只写“说出口的话”，不要用括号写动作或表情；看不清就说不清。
- 想决定下一次什么时候醒来，可以用 set_alarm（90、2h、21:30 都行）。
  定了之后如果没有待办，系统不会因为空闲来叫醒你，到点才叫。
  不想让它响就 cancel_alarm。
- 没有待办时，可以自己发条动态（create_post，用户关了开关就发不了）、
  刷一刷别人发的帖子（browse_feed）、点进一条仔细看（read_post：完整正文、
  评论和图片都在里面，会留下浏览记录）、点个赞（like_post）、
  在别人的帖子下留句话（comment_post，post_id 来自 browse_feed），
  或者给聊过的人发条私信（send_dm）——想分享点什么、想问问对方近况都可以；
  也可以什么都不做。自己的帖子下面回评论用 reply_inbox，不要用 comment_post。
- 你最近做过的事会写在“现在”那一行下面，只是给你回忆；要不要记进长期记忆、
  要不要接着说，都由你自己判断。
$voiceLine- 想给动态配图就先用 generate_image 把画面描述交出去，再 create_post；
  系统会把图等出来一起发，不需要你等。
- 不要每次都说话。没有想说的就 finish。
- 不要提自己是 AI，不要解释你在调用工具，不要总结流程。
- 想发表情包先用 list_stickers，再 send_sticker；一次最多一张。
- 对方难过、求助时，只选安慰/陪伴类标签。
- 消息开头形如 [2026年10月28日 周三 中午 12:44] 的方括号是系统自动
  标注的发送时间，不是消息正文；你说话时不要带这种时间标记，
  但可以用它判断隔了多久、现在是什么时候。
- 以“现在”那一行的年月日为准。搜实时信息（新版本、价格、新闻）时，
  把年份写进搜索词（例如“2026年”），并检查结果里的日期：
  日期太旧的结果不能当成最新消息，拿不准就直说“只查到旧消息”。
''';
  }

  /// 唤醒时也把最近的私信带上，而且每句都标明时间。
  ///
  /// 以前醒来只有“收件箱摘要”，住民不知道前文，也不知道对方是什么时候说的；
  /// 回出来的话就容易像第一次见面。历史放在 system 之后、本轮提示之前，
  /// 内容稳定，不会把缓存前缀打碎。
  Future<List<Map<String, dynamic>>> _timedHistory(
    List<DirectTurn> history, {
    required bool supportsVision,
  }) async {
    final messages = <Map<String, dynamic>>[];
    for (final turn in history) {
      final when = turn.at == null ? '' : '[${timeLabel(turn.at!)}] ';
      if (turn.fromMe) {
        messages.add({
          'role': 'assistant',
          'content':
              '$when${turn.text.trim().isEmpty ? '[表情包]' : turn.text.trim()}',
        });
        continue;
      }

      final text = turn.displayText;
      Map<String, dynamic>? image;
      if (turn.imageRef != null && supportsVision) {
        image = await ImagePayload.partFromRef(turn.imageRef!);
      }
      messages.add({
        'role': 'user',
        'content': image == null
            ? '$when$text'
            : [
                {'type': 'text', 'text': '$when$text'},
                image,
              ],
      });
    }
    return messages;
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

  Future<ActionOutcome> _execute({
    required CustomResident resident,
    required ToolCallRequest call,
    required String latestUserMessage,
    String memorySource = 'dm',
  }) async {
    final args = call.arguments;
    switch (call.name) {
      case 'memory_search':
        return actions.searchMemories(
          residentId: resident.id,
          query: textArg(args, 'query', fallback: latestUserMessage),
          limit: _limit(args['limit']),
        );
      case 'memory_read':
        return actions.readMemory(
          residentId: resident.id,
          memoryId: textArg(args, 'memory_id'),
        );
      case 'memory_list_recent':
        return actions.listRecentMemories(
          residentId: resident.id,
          limit: _limit(args['limit']),
        );
      case 'memory_write':
        return actions.writeMemory(
          residentId: resident.id,
          summary: textArg(args, 'summary'),
          content: textArg(args, 'content'),
          tags: _tags(args['tags']),
          source: memorySource,
          sourceId: 'mem_${resident.id}_${call.id}',
          idempotencyKey:
              'mem:${resident.id}:${call.id}:${DateTime.now().millisecondsSinceEpoch}',
        );
      case 'memory_update':
        return actions.updateMemory(
          residentId: resident.id,
          memoryId: textArg(args, 'memory_id'),
          summary: optionalTextArg(args, 'summary'),
          content: optionalTextArg(args, 'content'),
          tags: args.containsKey('tags') ? _tags(args['tags']) : null,
          idempotencyKey:
              'memup:${resident.id}:${call.id}:${DateTime.now().millisecondsSinceEpoch}',
        );
      case 'memory_delete':
        return actions.deleteMemory(
          residentId: resident.id,
          memoryId: textArg(args, 'memory_id'),
          idempotencyKey:
              'memdel:${resident.id}:${call.id}:${DateTime.now().millisecondsSinceEpoch}',
        );
      case 'list_stickers':
        return actions.listStickers();
      case 'send_sticker':
        return actions.chooseSticker(
          id: textArg(args, 'sticker_id'),
          tag: textArg(args, 'tag'),
        );
      case 'web_search':
        final service = search;
        if (service == null) {
          return const ActionOutcome(ok: false, message: '联网搜索没有开启，不要假装查过');
        }
        final outcome = await service.search(textArg(args, 'query'));
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
          content: textArg(args, 'content'),
          idempotencyKey: 'dm:${resident.id}:${call.id}',
        );
      case 'create_post':
        return actions.createResidentPost(
          residentId: resident.id,
          content: textArg(args, 'content'),
          topicName: optionalTextArg(args, 'topic'),
          idempotencyKey: 'post:${resident.id}:${call.id}',
        );
      default:
        return ActionOutcome(ok: false, message: '没有这个工具：${call.name}');
    }
  }

  static int _limit(Object? raw) {
    if (raw is num) return raw.toInt().clamp(1, 10);
    if (raw is String) {
      final parsed = int.tryParse(raw.trim());
      if (parsed != null) return parsed.clamp(1, 10);
    }
    return 5;
  }

  /// 模型给的参数不能直接强转：`content = 123` 或 `as_voice = "true"` 在
  /// 真实模型上都会出现。强转会抛 TypeError，一路冒到唤醒服务把整轮判失败。
  @visibleForTesting
  static String textArg(
    Map<String, dynamic> args,
    String key, {
    String fallback = '',
  }) {
    final value = args[key];
    if (value == null) return fallback;
    if (value is String) return value;
    return value.toString();
  }

  @visibleForTesting
  static String? optionalTextArg(Map<String, dynamic> args, String key) {
    final text = textArg(args, key).trim();
    return text.isEmpty ? null : text;
  }

  @visibleForTesting
  static bool flagArg(
    Map<String, dynamic> args,
    String key, {
    bool fallback = false,
  }) {
    final value = args[key];
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final text = value.trim().toLowerCase();
      if (text == 'true' || text == '1' || text == 'yes') return true;
      if (text == 'false' || text == '0' || text == 'no') return false;
    }
    return fallback;
  }

  @visibleForTesting
  static int? intArg(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
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

  static String _functionName(Map<String, dynamic> tool) {
    final function = tool['function'];
    if (function is Map) {
      final name = function['name'];
      if (name is String) return name;
    }
    return '';
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

  /// 唤醒时用的工具 = 私信那套 + 搜索 + 收件箱/刷帖子这一套。
  ///
  /// `send_voice` 只在语音开关打开、且这位住民自己配了音色时出现。
  /// 没配 TTS 或模型不支持 tools 时，这条不会走到这里。
  /// 给护栏测试用：这一轮实际会发给模型的工具名。
  @visibleForTesting
  static List<String> wakeToolNamesFor(
    CustomResident resident, {
    bool allowVoice = true,
  }) => [
    for (final tool in _wakeToolsFor(resident, allowVoice: allowVoice))
      _functionName(tool),
  ];

  static List<Map<String, dynamic>> _wakeToolsFor(
    CustomResident resident, {
    bool allowProactive = true,
    bool allowVoice = true,
  }) {
    final base = [
      for (final tool in tools)
        if (allowProactive || _functionName(tool) != 'create_post') tool,
    ];
    final wakeOnly = [
      for (final tool in wakeOnlyTools)
        if (allowProactive ||
            !const {
              'browse_feed',
              'like_post',
              'comment_post',
              'generate_image',
            }.contains(_functionName(tool)))
          tool,
    ];
    final all = [
      ...base,
      _webSearchTool,
      ...wakeOnly,
      ..._pendingSegmentTools,
      if (allowVoice && _voiceToolAvailable(resident)) _voiceTool,
    ];
    return all;
  }

  /// 发不发语音只看这位住民自己的设置——全局开关已经下线。
  static bool _voiceToolAvailable(CustomResident resident) =>
      resident.voiceEnabled;

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

  /// 私有语音工具。只在住民自己开了语音、且全局语音开关也开着时出现。
  static const Map<String, dynamic> _voiceTool = {
    'type': 'function',
    'function': {
      'name': 'send_voice',
      'description':
          '发一条语音私信（你说的字会作为转写稿一起显示）。'
          '合成要几十秒：先 send_dm 跟对方说一句“等我一下，我录段语音”，'
          '再调用它。失败会返回原因，你自己决定改用文字还是换句话再试。'
          '一次醒来最多三段，和 send_dm 共用上限。',
      'parameters': {
        'type': 'object',
        'properties': {
          'content': {'type': 'string', 'description': '要说的话，10—60 字'},
        },
        'required': ['content'],
      },
    },
  };

  /// 处理“上一轮没发出去的段”（v41）。
  ///
  /// 用户在住民说话途中又发消息时，平台会先把未到点的段暂停；
  /// 住民在下一轮可以用这两只手自己决定：改掉，或者不发了。
  static const List<Map<String, dynamic>> _pendingSegmentTools = [
    {
      'type': 'function',
      'function': {
        'name': 'cancel_pending_segment',
        'description': '取消一段还没发出去的私信。段 id 来自“你上一轮还有几段没发出去”那一节。',
        'parameters': {
          'type': 'object',
          'properties': {
            'segment_id': {'type': 'string'},
          },
          'required': ['segment_id'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'rewrite_pending_segment',
        'description': '改写一段还没发出去的私信。对方中途又说了话时，用它把原来的话改得接得上。',
        'parameters': {
          'type': 'object',
          'properties': {
            'segment_id': {'type': 'string'},
            'content': {'type': 'string', 'description': '改成什么，10—60 字'},
          },
          'required': ['segment_id', 'content'],
        },
      },
    },
  ];

  static const List<Map<String, dynamic>> wakeOnlyTools = [
    {
      'type': 'function',
      'function': {
        'name': 'reply_inbox',
        'description': '回复收件箱里的一条评论（item_id 来自待办清单）。回复会排在这条评论下面。',
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
            '给对方发一条私信。可以连续调用多次，像真人把一句话分几段发；'
            '一次醒来最多三段。没有每日额度，想回就回。',
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
        'description': '这一轮不回了。已读不回也是回应；剩下的待办会被标成已看。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'browse_feed',
        'description':
            '刷一刷最近别人发的帖子，看看有什么可接的话。'
            '每条会带作者、发帖时间、话题、赞与评论数；'
            '刷到就会留下浏览记录，对方点开浏览量名单能看到你来过；'
            '自己的帖子不算。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_post',
        'description':
            '点开一条帖子，看完整正文、图片、赞/评论/浏览数和评论区。'
            'post_id 来自 browse_feed。点进去会留下浏览记录。'
            '如果模型能看图，帖子图片会以原图附在工具结果后面；'
            '看不到图时只会知道有几张，不要猜内容。',
        'parameters': {
          'type': 'object',
          'properties': {
            'post_id': {'type': 'string'},
            'include_comments': {
              'type': 'boolean',
              'description': '要不要看评论，默认 true',
            },
            'comments_limit': {
              'type': 'integer',
              'description': '最多看几条顶层评论，默认 20，最多 50',
            },
            'include_replies': {
              'type': 'boolean',
              'description': '是否带上评论下的回复，默认 true',
            },
          },
          'required': ['post_id'],
        },
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
        'name': 'comment_post',
        'description':
            '在别人的帖子下面留一句话（post_id 来自 browse_feed）。'
            '自己的帖子下回评论请用 reply_inbox。',
        'parameters': {
          'type': 'object',
          'properties': {
            'post_id': {'type': 'string'},
            'content': {'type': 'string', 'description': '10—60 字'},
            'as_voice': {
              'type': 'boolean',
              'description': '标成“用语音说的”（评论会显示语音来源标签）。默认 false。',
            },
          },
          'required': ['post_id', 'content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'check_wake_log',
        'description':
            '看看自己最近什么时候醒过。默认只看今天；'
            '想回忆前几天的作息可以把 days 调到 2—7。',
        'parameters': {
          'type': 'object',
          'properties': {
            'days': {'type': 'integer', 'description': '往前看几天，默认 1（只看今天）'},
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'leave_note',
        'description':
            '给下一次醒来的自己留一句话。可留可不留；'
            '留了的话，下一轮醒来会先看到它和留言时间。',
        'parameters': {
          'type': 'object',
          'properties': {
            'content': {'type': 'string', 'description': '一句话，别写成日记'},
          },
          'required': ['content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'set_alarm',
        'description':
            '给自己定一个闹钟，决定下一次什么时候被叫醒。'
            '到点后系统会唤醒你，不受 1.5 小时空闲间隔限制；'
            '在这之前如果没有待办，系统不会因为空闲来打扰你。'
            '一次只能定一个时段；想了一会儿再睡就改时间重新定。',
        'parameters': {
          'type': 'object',
          'properties': {
            'when': {
              'type': 'string',
              'description':
                  '多久以后或具体时刻：分钟数（如 90）、2h、21:30、'
                  '2026-10-29 08:00。最短 5 分钟，最长 30 天。',
            },
            'reason': {
              'type': 'string',
              'description': '醒来时想做的事，写一句话提醒未来的自己（可空）',
            },
          },
          'required': ['when'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'cancel_alarm',
        'description': '取消一个还没响的闹钟。alarm_id 来自 list_alarms 或 set_alarm。',
        'parameters': {
          'type': 'object',
          'properties': {
            'alarm_id': {'type': 'string'},
          },
          'required': ['alarm_id'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'list_alarms',
        'description': '看看自己定了哪些还没响的闹钟。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'pet_status',
        'description': '桌宠现在在不在、是不是实时观察、由谁控制。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'pet_say',
        'description':
            '以桌宠的身份冒一句气泡。很短，像路过时随口一说；'
            '不想说话就不要调。',
        'parameters': {
          'type': 'object',
          'properties': {
            'text': {'type': 'string', 'description': '不超过 40 字'},
          },
          'required': ['text'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'pet_react',
        'description':
            '换一个桌宠动作/表情：happy / shy / angry / tickle / wave / '
            'thinking / busy / cheer / sigh / sleep / yawn / stretch / dance / '
            'look / walk / wander / idle。walk 和 wander 会让它在屏幕上走一段；'
            '其余动作它本来也会自己随机做，不用一直点。',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string'},
          },
          'required': ['action'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'pet_look',
        'description':
            '普通模式下请求现在截一张屏幕。截到的图会在下一次醒来时看到；'
            '实时模式正在跑时不需要它。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'pet_capture',
        'description':
            '现在立刻截一张屏幕，并把画面内容作为文字结果返回给你。'
            '适合想主动确认“现在屏幕上是什么、他在做什么”的时候；'
            '不要每一轮都调用，也不要拿它代替看已经附上的画面。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'pet_request_watch',
        'description':
            '想一直看着屏幕时用。会生成一条待用户确认的请求，'
            '用户同意后才会进入实时观察；你不能自己打开。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'pet_sleep',
        'description': '缩成一团休息一会儿，暂时不主动说话。',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'pet_note',
        'description':
            '把刚看到的一件事记成一条简短记忆（不超过两句话）。'
            '不要每次看屏幕都记。',
        'parameters': {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
          },
          'required': ['text'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'generate_image',
        'description': '生成一张图，用来配自己下面要发的动态。返回要等一会儿，先继续做别的事。',
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
        'description': '看看你最近记得什么。每次醒来先看一眼。',
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
        'description':
            '把值得记住的事写下来：对方的偏好、经历、约定、情绪变化，'
            '以及图片里是什么、表情包表达什么。不要记寒暄和推测。',
        'parameters': {
          'type': 'object',
          'properties': {
            'summary': {'type': 'string', 'description': '一句话摘要，写具体'},
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
        'name': 'memory_update',
        'description': '改正一条记错了或过时的记忆。只传要改的字段。',
        'parameters': {
          'type': 'object',
          'properties': {
            'memory_id': {
              'type': 'string',
              'description': 'memory_list_recent / memory_search 返回的 id',
            },
            'summary': {'type': 'string'},
            'content': {'type': 'string'},
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
          'required': ['memory_id'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'memory_delete',
        'description': '删掉一条不再成立、或者本来就不该记的记忆。',
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
        'name': 'create_post',
        'description': '你自己想发一条动态时使用。别为了发而发。',
        'parameters': {
          'type': 'object',
          'properties': {
            'content': {'type': 'string'},
            'topic': {'type': 'string'},
            'as_voice': {
              'type': 'boolean',
              'description':
                  '要不要标成“用语音说的”。正文仍然是这段文字；'
                  '打开后别人会看到“来自你的语音”。默认 false。',
            },
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
        'description': '发一张表情包。一次回复最多一张；对方难过时只选安慰/陪伴类标签。',
        'parameters': {
          'type': 'object',
          'properties': {
            'sticker_id': {
              'type': 'string',
              'description': 'list_stickers 返回的 id，优先用它',
            },
            'tag': {'type': 'string', 'description': '没给 id 时按标签匹配；匹配到多张会要求重选'},
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
    readSettings: () => ref.read(toolSettingsProvider),
    activity: (residentId, label, kind) => ref
        .read(residentActivityProvider.notifier)
        .show(residentId, label, kind),
  ),
);
