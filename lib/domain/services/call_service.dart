import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media/image_payload.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../domain/models/custom_resident.dart';
import 'action_registry.dart';
import 'model_gateway.dart';
import 'photo_describer.dart';
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
  });

  final ModelGateway gateway;
  final CustomResidentRepository residents;
  final ActionRegistry actions;
  final PhotoDescriber photos;

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
  }) async {
    final resident = await residents.findById(residentId);
    if (resident == null) throw StateError('这个人已经不在社区里了');
    final config =
        await gateway.configFor(configId: resident.modelConfigId) ??
        await gateway.activeConfig();
    if (config == null) throw StateError('还没有配置对话模型');

    final recent = history.length > maxHistoryTurns
        ? history.sublist(history.length - maxHistoryTurns)
        : history;
    final timeline = StringBuffer();
    for (final turn in recent) {
      timeline.writeln('${turn.fromMe ? '对方' : '你'}：${turn.text}');
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
      if (timeline.isNotEmpty) '你们刚在通话里说过：\n${timeline.toString().trim()}',
      if (pictureLines.isNotEmpty)
        '${video ? '摄像头' : '屏幕'}在这几秒里看到的（按时间顺序，附图与之一一对应）：\n${pictureLines.join('\n')}',
      if (interrupted) '（上一句你还没说完，对方就开口打断了你。）',
      '对方刚说：「${userText.trim()}」',
      '直接回他一句，像打电话一样。',
    ].join('\n\n');

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt(resident, video: video)},
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

  String _systemPrompt(CustomResident resident, {required bool video}) {
    final persona = [
      if (resident.description.trim().isNotEmpty) resident.description,
      if (resident.personality.trim().isNotEmpty) resident.personality,
      if (resident.languageStyle.trim().isNotEmpty) resident.languageStyle,
      if (resident.tone.trim().isNotEmpty) resident.tone,
      if (resident.extraInstructions.trim().isNotEmpty)
        resident.extraInstructions,
    ].join('\n');
    return '''
你是「${resident.name}」，正在和对方${video ? '视频' : '语音'}通话。
$persona

规则：
- 像真的在打电话：一次 1—3 句，每句短，不要小作文，不要客套结尾。
- 你听到的是对方说的话；不要提“消息”“私信”“聊天记录”。
- ${video ? '你看得到对方这几秒的画面，可以顺着画面里的东西接话，但别像看图说话一样逐条描述。' : '这是语音通话，没有画面，只凭声音和上下文接话。'}
- 不要提自己是 AI，不要解释规则。
- 对方可能中途打断你：被打断就别接着刚才那句往下念，先听他说。
''';
  }

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
  ),
);
