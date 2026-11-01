import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media/image_payload.dart';
import '../../data/repositories/custom_resident_repository.dart';
import 'action_registry.dart';
import 'model_gateway.dart';
import 'photo_describer.dart';
import 'resident_context_service.dart';
import 'resident_timeline.dart';
import 'tool_call_text.dart';

/// 通话里的一句话（只活在这通电话里，不落私信）。
class CallTurn {
  const CallTurn({
    required this.fromMe,
    required this.text,
    required this.at,
  });

  final bool fromMe;
  final String text;
  final DateTime at;
}

/// 摄像头在两句话之间采到的一帧。
class CallFrame {
  const CallFrame({required this.ref, required this.at});

  final String ref;
  final DateTime at;
}

/// 通话的模型通道（v4.0 P4 重做）。
///
/// 和私信唤醒分开：这里没有收件箱、没有工具，也不往 `private_messages`
/// 写任何正文。每轮只把“最近几秒的帧 + 用户这句话 + 之前聊过的几句”
/// 交给模型，让它像打电话一样回一句。
class CallService {
  CallService({
    required this.gateway,
    required this.residents,
    required this.actions,
    required this.photos,
    required this.context,
    required this.timeline,
  });

  final ModelGateway gateway;
  final CustomResidentRepository residents;
  final ActionRegistry actions;
  final PhotoDescriber photos;
  final ResidentContextService context;
  final ResidentTimeline timeline;

  /// 通话里带多少轮旧文本。再多就变成聊天记录了，不是电话。
  static const int maxHistoryTurns = 10;

  /// 一次最多附几张画面。
  static const int maxFrames = 4;

  Future<String> reply({
    required String residentId,
    required String userText,
    required List<CallTurn> history,
    required List<CallFrame> frames,
    required bool video,
    required bool interrupted,
    bool proactive = false,
  }) async {
    final resident = await residents.findById(residentId);
    if (resident == null) throw StateError('这个人已经不在社区里了');
    final config =
        await gateway.configFor(configId: resident.modelConfigId) ??
        await gateway.activeConfig();
    if (config == null) throw StateError('还没有配置对话模型');

    // 通话不是另一套会话：人设、记忆、最近私信都来自同一个常驻窗口。
    // 通话里的句子只作为本轮载荷，不往私信写正文，也不改窗口前缀。
    final window = await context.open(
      resident,
      allowVoice: true,
      allowImages: config.supportsVision,
    );

    final recent = history.length > maxHistoryTurns
        ? history.sublist(history.length - maxHistoryTurns)
        : history;
    final spoken = StringBuffer();
    for (final turn in recent) {
      spoken.writeln('${turn.fromMe ? '对方' : '你'}：${turn.text}');
    }

    final pictureLines = <String>[];
    final imageParts = <Map<String, dynamic>>[];
    if (video && frames.isNotEmpty) {
      final picked = frames.length > maxFrames
          ? frames.sublist(frames.length - maxFrames)
          : frames;
      if (config.supportsVision) {
        imageParts.addAll(
          await ImagePayload.partsFromRefs(
            [for (final frame in picked) frame.ref],
            limit: maxFrames,
          ),
        );
        for (final frame in picked) {
          pictureLines.add('- ${_clock(frame.at)}');
        }
      } else {
        // 模型看不了图：至少让它知道最后一帧里是什么。
        final description = await photos.describe(picked.last.ref);
        if (description.isNotEmpty) {
          pictureLines.add('- ${_clock(picked.last.at)} 画面：$description');
        }
      }
    }

    final userBlock = [
      '现在：${_clock(DateTime.now())}',
      if (spoken.isNotEmpty) '你们刚在通话里说过：\n${spoken.toString().trim()}',
      if (pictureLines.isNotEmpty)
        '${video ? '摄像头' : '屏幕'}在这几秒里看到的（按时间顺序，附图与之一一对应）：\n${pictureLines.join('\n')}',
      if (interrupted) '（上一句你还没说完，对方就开口打断了你。）',
      if (proactive)
        '对方已经十几秒没说话了。看一眼摄像头里的画面，'
            '若确实有想说的、或注意到什么值得提一句的，就主动开口；'
            '没什么可说的就只回复 [沉默]，不要为了说话而找话。'
      else
        '对方刚说：「${userText.trim()}」',
      _callRules(video),
    ].join('\n\n');

    // 共享窗口里的 system + 记忆 + 最近私信原样留着，通话只往后追加。
    final messages = <Map<String, dynamic>>[
      ...window.messages,
      {
        'role': 'user',
        'content': imageParts.isEmpty
            ? userBlock
            : [
                {'type': 'text', 'text': userBlock},
                ...imageParts,
              ],
      },
    ];

    final text = await gateway.completeRich(
      config: config,
      messages: messages,
      temperature: 0.9,
      maxTokens: 220,
      timeout: const Duration(seconds: 25),
    );
    final clean = sanitizeModelText(text);
    if (clean.isEmpty) throw StateError('这次没接上话');
    return clean;
  }

  /// 挂断后：把这段通话总结成一条记忆，然后删掉临时画面。
  ///
  /// 总结失败也照样删：通话内容不是聊天记录，没有理由长期留在磁盘上。
  Future<void> finishAndRemember({
    required String residentId,
    required List<CallTurn> turns,
    required List<CallFrame> frames,
    required Duration duration,
    required bool video,
  }) async {
    try {
      if (turns.isNotEmpty) {
        final summary = await _summarize(
          residentId: residentId,
          turns: turns,
          duration: duration,
          video: video,
        );
        if (summary.isNotEmpty) {
          await actions.writeMemory(
            residentId: residentId,
            summary: summary,
            content: summary,
            source: 'call',
            idempotencyKey:
                'call:$residentId:${DateTime.now().microsecondsSinceEpoch}',
          );
        }
        // 挂断后让同一个窗口知道“刚才通过话”，下一次私信/桌宠才接得上。
        // 只留一段摘要，不把整段通话正文塞进私信或长期时间线。
        final line = summary.isEmpty
            ? '你和对方通了一次${video ? '视频' : '语音'}电话，'
                  '时长约 ${duration.inMinutes} 分钟。'
            : '你和对方通了一次${video ? '视频' : '语音'}电话，'
                  '时长约 ${duration.inMinutes} 分钟；聊到：$summary';
        context.appendMessage(residentId, {
          'role': 'user',
          'content': '<system-reminder>[通话记录] $line</system-reminder>',
        });
        await timeline.appendAction(
          residentId,
          content: '和对方通了一次${video ? '视频' : '语音'}电话'
              '（${duration.inMinutes} 分钟）',
          at: DateTime.now(),
          meta: 'call',
        );
      }
    } catch (error) {
      debugPrint('[通话] 这段没记成：$error');
    } finally {
      for (final frame in frames) {
        _delete(frame.ref);
      }
    }
  }

  Future<String> _summarize({
    required String residentId,
    required List<CallTurn> turns,
    required Duration duration,
    required bool video,
  }) async {
    final resident = await residents.findById(residentId);
    if (resident == null || !resident.memoryEnabled) return '';
    final config =
        await gateway.configFor(configId: resident.modelConfigId) ??
        await gateway.activeConfig();
    if (config == null) return '';

    final text = turns
        .map((turn) => '${turn.fromMe ? '对方' : '你'}：${turn.text}')
        .join('\n');
    final result = await gateway.completeRich(
      config: config,
      messages: [
        {
          'role': 'system',
          'content':
              '你刚和对方通了一次${video ? '视频' : '语音'}电话，'
              '时长约 ${duration.inMinutes} 分钟。'
              '把这次通话里值得记住的事写成一条简短记忆：对方说了什么、'
              '在做什么、有没有约定。两句话以内，不要写成日记，'
              '不要提“语音”“视频”“通话记录”这些词。',
        },
        {'role': 'user', 'content': text},
      ],
      temperature: 0.4,
      maxTokens: 160,
      timeout: const Duration(seconds: 20),
    );
    return sanitizeModelText(result).trim();
  }

  /// 通话场景只加在**本轮用户消息**里，不另写 system、不动共享前缀。
  static String _callRules(bool video) => '''
你们现在正在${video ? '视频' : '语音'}通话。
- 像真的在打电话：一次 1—3 句，每句短，不要小作文，不要客套结尾。
- 直接说出口，不要调用 send_dm / send_voice，也不要提“消息”“私信”。
- ${video ? '你看得到对方这几秒的画面，可以顺着画面里的东西接话，但别像看图说话一样逐条描述。' : '这是语音通话，没有画面，只凭声音和上下文接话。'}
- 对方可能中途打断你：被打断就别接着刚才那句往下念，先听他说。''';

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}';

  static void _delete(String ref) {
    try {
      final path = ref.startsWith('file:') ? ref.substring(5) : ref;
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // cache 目录由系统兜底。
    }
  }
}

final callServiceProvider = Provider<CallService>(
  (ref) => CallService(
    gateway: ref.watch(modelGatewayProvider),
    residents: ref.watch(customResidentRepositoryProvider),
    actions: ref.watch(actionRegistryProvider),
    photos: ref.watch(photoDescriberProvider),
    context: ref.watch(residentContextServiceProvider),
    timeline: ref.watch(residentTimelineProvider),
  ),
);
