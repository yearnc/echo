import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/private_message_repository.dart';
import '../../domain/models/private_message.dart';
import '../../domain/models/sticker.dart';
import '../../domain/services/photo_describer.dart';
import '../../domain/services/resident_wake_service.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';
import '../shared_widgets/chat_bubble.dart';
import '../shared_widgets/chat_composer.dart';
import '../shared_widgets/user_avatar.dart';

/// 和某一位住民的会话（B5）。
///
/// 节奏是故意的：你发一句，他过几分钟才回。真人不会秒回，
/// 而这个 APP 本来就在做一件事——让人不那么在意“回应要立刻有”。
/// 所以没有“对方正在输入…”（规划书 §3.5 明确删掉了它）。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.personaId});

  final String personaId;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final TextEditingController _input = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markRead();
      // 不再播手写的“开场白”：住民醒来后自己开口。
      // 新建住民时编辑页已经叫醒过他，这里不重复叫。
    });
    // 不用轮询：私信仓储会按“下一条排期消息到点”的时间自己重新发射，
    // 到点的那一条会像微信一样直接出现。
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _markRead() {
    unawaited(
      ref.read(privateMessageRepositoryProvider).markThreadRead(widget.personaId),
    );
  }

  /// 我发一句。
  ///
  /// 发完顺手让私信服务排一条回应——**不 await**：排期是他那边的事，
  /// 跟“这句话已经发出去了”没关系，更不该让你等它。
  Future<void> _send({
    String? text,
    StickerItem? sticker,
    String? imageRef,
  }) async {
    if (_sending) return;
    final content = sticker?.path ?? imageRef ?? (text ?? '').trim();
    if (content.isEmpty) return;
    final mediaType = sticker != null
        ? 'sticker'
        : (imageRef != null ? 'image' : 'text');
    final caption = sticker == null
        ? ''
        : '表情包「${sticker.name}」'
              '${sticker.tags.isEmpty ? '' : '（标签：${sticker.tags.join('、')}）'}';

    setState(() => _sending = true);
    try {
      _input.clear();
      final messageId = await ref
          .read(privateMessageRepositoryProvider)
          .send(
            personaId: widget.personaId,
            content: content,
            mediaType: mediaType,
            caption: caption,
          );

      // 消息先出现；图片描述补齐之后再把住民叫醒。
      // 这样模型无论是看图还是读描述，都知道“他发来的到底是什么”。
      unawaited(
        _enrichAndWake(
          messageId: messageId,
          content: content,
          mediaType: mediaType,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('没发出去：$error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 把图片/表情包的语义补进这条消息，再叫醒固定住民。
  ///
  /// 记忆不再由页面写死：住民醒来后自己决定记什么。页面只负责把
  /// “图里是什么”送到它面前。
  Future<void> _enrichAndWake({
    required String messageId,
    required String content,
    required String mediaType,
  }) async {
    if (mediaType == 'image') {
      final description = await ref
          .read(photoDescriberProvider)
          .describe(content);
      if (description.isNotEmpty) {
        await ref
            .read(privateMessageRepositoryProvider)
            .attachCaption(messageId, description);
      }
    }
    if (!mounted) return;

    final resident = ref.read(customResidentByIdProvider(widget.personaId));
    if (resident != null) {
      // 他这一轮可能回私信，也可能去帖子下面接话——那是他自己的选择。
      await ref
          .read(residentWakeServiceProvider)
          .wake(widget.personaId, trigger: WakeTrigger.userAction);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 行为判断用“还在社区里的”；显示名字/头像用“含已删除的”——
    // 删掉的住民仍然是一段历史，不该在会话里变成“社区住民”。
    final resident = ref.watch(customResidentByIdProvider(widget.personaId));
    final storedResident = ref.watch(
      customResidentAnyByIdProvider(widget.personaId),
    );
    final thread = ref.watch(privateThreadProvider(widget.personaId));
    final name = storedResident?.name ?? '已离开的住民';
    final avatarRef = storedResident?.avatarAsset;
    // 没有人能接话了：固定住民已删除。保留历史，但不能再发。
    final canSend = resident != null;
    final departed = resident == null;

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(name: name, avatarRef: avatarRef, size: 32),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: EchoColors.text,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    departed ? '已离开社区' : '固定住民',
                    style: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SafeArea(child: AiDisclaimerBar()),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              EchoColors.bg,
              Color.lerp(EchoColors.bg, EchoColors.primary, 0.035) ??
                  EchoColors.bg,
            ],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: thread.when(
                loading: () => Center(
                  child: CircularProgressIndicator(color: EchoColors.primary),
                ),
                error: (error, _) => Center(
                  child: Text(
                    '读不到会话：$error',
                    style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
                  ),
                ),
                data: (list) {
                  // 刚到点的那条消息出现时顺手标已读；不用等页面轮询。
                  if (list.any((message) => !message.fromMe && !message.read)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _markRead();
                    });
                  }
                  return list.isEmpty
                      ? _Opening(name: name, avatarRef: avatarRef)
                      : _MessageList(
                          messages: list,
                          name: name,
                          avatarRef: avatarRef,
                        );
                },
              ),
            ),
            if (canSend)
              ChatComposer(
                controller: _input,
                sending: _sending,
                onSend: _send,
              )
            else
              const _DepartedNotice(),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.name,
    required this.avatarRef,
  });

  final List<PrivateMessage> messages;
  final String name;
  final String? avatarRef;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    DateTime? day;
    String? previousSender;

    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      final sender = message.fromMe ? 'me' : 'them';

      if (day == null || !ChatDayDivider.sameDay(day, message.createdAt)) {
        rows.add(ChatDayDivider(day: message.createdAt));
        day = message.createdAt;
        previousSender = null;
      }

      final next = index + 1 < messages.length ? messages[index + 1] : null;
      final sameAsNext =
          next != null &&
          (next.fromMe ? 'me' : 'them') == sender &&
          ChatDayDivider.sameDay(next.createdAt, message.createdAt) &&
          next.createdAt.difference(message.createdAt).inMinutes < 5;

      rows.add(
        ChatBubble(
          content: message.content,
          mediaType: message.mediaType,
          caption: message.caption,
          voicePath: message.voicePath,
          transcript: message.transcript,
          fromMe: message.fromMe,
          senderName: name,
          avatarRef: avatarRef,
          createdAt: message.createdAt,
          showAvatar: previousSender != sender,
          showTime: !sameAsNext,
        ),
      );
      previousSender = sender;
    }

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[rows.length - 1 - index],
    );
  }
}

/// 对方已经不在社区里：这段对话变成只读，历史还在。
class _DepartedNotice extends StatelessWidget {
  const _DepartedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        border: Border(top: BorderSide(color: EchoColors.divider, width: 0.8)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline,
            size: 15,
            color: EchoColors.textFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'TA 已经离开社区，这段对话只能回看。',
              style: TextStyle(color: EchoColors.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// 会话还是空的——他还没开口，而你已经在门口了。
class _Opening extends StatelessWidget {
  const _Opening({required this.name, this.avatarRef});

  final String name;
  final String? avatarRef;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            UserAvatar(
              name: name,
              avatarRef: avatarRef,
              size: 64,
              showRing: true,
            ),
            const SizedBox(height: 14),
            Text(
              '你们还没聊过。',
              style: TextStyle(color: EchoColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 5),
            Text(
              '说句话试试？',
              style: TextStyle(color: EchoColors.textFaint, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
