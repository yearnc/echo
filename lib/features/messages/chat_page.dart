import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/message_time.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/media/media_service.dart';
import '../../data/repositories/private_message_repository.dart';
import '../../domain/models/private_message.dart';
import '../../domain/models/sticker.dart';
import '../../domain/services/direct_message_service.dart';
import '../../domain/services/model_gateway.dart';
import '../../domain/services/resident_memory_service.dart';
import '../../domain/services/resident_wake_service.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';
import '../shared_widgets/post_image.dart';
import '../shared_widgets/sticker_picker_sheet.dart';
import '../shared_widgets/user_avatar.dart';

/// 和某一位住民的会话（B5）。
///
/// 这里的节奏是**故意的**：你发一句，他过几分钟才回。真人不会秒回，
/// 而这个 APP 本来就在做一件事——让人不那么在意"回应要立刻有"。
/// 所以没有"对方正在输入…"（规划书 §3.5 明确删掉了它）。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.personaId});

  final String personaId;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final TextEditingController _input = TextEditingController();
  Timer? _refresh;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markRead();
      // 不再播手写的“开场白”：住民醒来后自己开口。
      // 新建住民时编辑页已经叫醒过他，这里不重复叫。
    });
    // 他不会秒回：回应排在几分钟之后，页面得自己隔一会儿重问一次，
    // 不然那句话要等你退出去再进来才看得见。
    _refresh = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      _markRead();
      ref.invalidate(privateThreadProvider(widget.personaId));
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
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
  /// 跟"这句话已经发出去了"没关系，更不该让你等它。
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

    setState(() => _sending = true);
    try {
      _input.clear();
      await ref
          .read(privateMessageRepositoryProvider)
          .send(
            personaId: widget.personaId,
            content: content,
            mediaType: mediaType,
          );

      // 固定住民记得住你说过的话，也记得你发过图——
      // 以前只写文字，翻记忆时会以为你们从没发过图片。
      final resident = ref.read(customResidentByIdProvider(widget.personaId));
      if (resident != null) {
        final memory = ref.read(residentMemoryServiceProvider);
        final sourceId = 'dm_${widget.personaId}_'
            '${DateTime.now().microsecondsSinceEpoch}';
        if (mediaType == 'text') {
          unawaited(
            memory.rememberUserReply(
              residentId: resident.id,
              reply: content,
              source: 'dm',
              sourceId: sourceId,
            ),
          );
        } else if (mediaType == 'image') {
          unawaited(
            memory.rememberUserReply(
              residentId: resident.id,
              reply: '[发来一张图片]',
              imageSummary: '对方发来一张图片',
              source: 'dm',
              sourceId: sourceId,
            ),
          );
        } else if (mediaType == 'sticker') {
          unawaited(
            memory.rememberUserReply(
              residentId: resident.id,
              reply: '[发来一个表情包]',
              source: 'dm',
              sourceId: sourceId,
            ),
          );
        }
      }

      // 固定住民要马上醒过来看这条消息：他这一轮可能回私信，
      // 也可能去帖子下面接话——那是他自己的选择，不该由发送方决定。
      if (resident != null) {
        unawaited(
          ref
              .read(residentWakeServiceProvider)
              .wake(widget.personaId, trigger: WakeTrigger.userAction),
        );
      } else {
        unawaited(ref.read(directMessageServiceProvider).tick());
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('没发出去：$error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickSticker() async {
    final picked = await showStickerPicker(context, ref);
    if (picked != null) await _send(sticker: picked);
  }

  Future<void> _pickImage() async {
    final imageRef = await ref.read(mediaServiceProvider).pickFromGallery();
    if (imageRef == null || !mounted) return;
    await _send(imageRef: imageRef);

    // 当前对话模型不支持看图时，至少别让用户以为对方真看见了。
    final config = await ref.read(modelGatewayProvider).activeConfig();
    if (!mounted) return;
    if (config != null && !config.supportsVision) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前对话模型看不了图，TA 只会知道“对方发来一张图片”'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final resident = ref.watch(customResidentByIdProvider(widget.personaId));
    final persona = ref.watch(personaByIdProvider(widget.personaId));
    final thread = ref.watch(privateThreadProvider(widget.personaId));
    final name = resident?.name ?? persona?.name ?? '社区住民';
    final avatarRef = resident?.avatarAsset ?? persona?.avatar;

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          name,
          style: TextStyle(
            color: EchoColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      bottomNavigationBar: const SafeArea(child: AiDisclaimerBar()),
      body: Column(
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
              data: (list) => list.isEmpty
                  ? _Opening(name: name)
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final message = list[list.length - 1 - index];
                        return _Bubble(
                          message: message,
                          name: name,
                          avatarRef: avatarRef,
                        );
                      },
                    ),
            ),
          ),
          _Composer(
            controller: _input,
            sending: _sending,
            onSend: _send,
            onSticker: _pickSticker,
            onImage: _pickImage,
          ),
        ],
      ),
    );
  }
}

/// 会话还是空的——他还没开口，而你已经在门口了。
class _Opening extends StatelessWidget {
  const _Opening({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        child: Text(
          '你们还没聊过。说句话试试？',
          textAlign: TextAlign.center,
          style: TextStyle(color: EchoColors.textFaint, fontSize: 13),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.name, this.avatarRef});

  final PrivateMessage message;
  final String name;
  final String? avatarRef;

  @override
  Widget build(BuildContext context) {
    final fromMe = message.fromMe;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 5, 14, 5),
      child: Column(
        crossAxisAlignment: fromMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: fromMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!fromMe) ...[
                UserAvatar(name: name, avatarRef: avatarRef, size: 34),
                const SizedBox(width: 8),
              ],
              Flexible(child: _content(fromMe)),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(
              top: 3,
              left: fromMe ? 0 : 42,
              right: fromMe ? 4 : 0,
            ),
            child: Text(
              formatMessageTime(message.createdAt),
              style: TextStyle(color: EchoColors.textFaint, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(bool fromMe) {
    // 表情包和图片就是一张图，不套气泡——套上就像给图加了个相框
    if (message.mediaType == 'sticker' || message.mediaType == 'image') {
      final isImage = message.mediaType == 'image';
      final side = isImage ? 190.0 : 118.0;
      return SizedBox(
        width: side,
        height: isImage ? 170 : side,
        child: PostImage(
          ref: message.content,
          height: isImage ? 170 : side,
          borderRadius: 12,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: fromMe ? EchoColors.primary : EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: fromMe ? null : Border.all(color: EchoColors.divider),
      ),
      child: Text(
        message.content,
        style: TextStyle(
          color: fromMe ? Colors.white : EchoColors.text,
          fontSize: 14,
          height: 1.55,
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onSticker,
    required this.onImage,
  });

  final TextEditingController controller;
  final bool sending;
  final Future<void> Function({
    String? text,
    StickerItem? sticker,
    String? imageRef,
  }) onSend;
  final VoidCallback onSticker;
  final VoidCallback onImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EchoColors.surface,
        border: Border(top: BorderSide(color: EchoColors.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: sending ? null : onImage,
            tooltip: '图片',
            icon: Icon(
              Icons.image_outlined,
              color: EchoColors.textMuted,
              size: 22,
            ),
          ),
          IconButton(
            onPressed: sending ? null : onSticker,
            tooltip: '表情包',
            icon: Icon(
              Icons.emoji_emotions_outlined,
              color: EchoColors.textMuted,
              size: 22,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (!sending) onSend(text: controller.text);
              },
              style: TextStyle(color: EchoColors.text, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: '说点什么…',
                hintStyle: TextStyle(color: EchoColors.textFaint, fontSize: 14),
                filled: true,
                fillColor: EchoColors.bg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            onPressed: sending ? null : () => onSend(text: controller.text),
            tooltip: '发送',
            icon: sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.send_rounded,
                    color: EchoColors.primary,
                    size: 22,
                  ),
          ),
        ],
      ),
    );
  }
}
