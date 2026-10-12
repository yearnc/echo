import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/private_message_repository.dart';
import '../../data/repositories/sticker_repository.dart';
import '../../domain/models/private_message.dart';
import '../../domain/models/sticker.dart';
import '../../domain/services/direct_message_service.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';
import '../shared_widgets/post_image.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
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
  Future<void> _send({String? text, StickerItem? sticker}) async {
    final content = sticker?.path ?? (text ?? '').trim();
    if (content.isEmpty) return;

    _input.clear();
    await ref
        .read(privateMessageRepositoryProvider)
        .send(
          personaId: widget.personaId,
          content: content,
          mediaType: sticker == null ? 'text' : 'sticker',
        );
    unawaited(ref.read(directMessageServiceProvider).tick());
  }

  Future<void> _pickSticker() async {
    final library = await ref.read(stickerLibraryProvider.future);
    if (!mounted) return;

    final picked = await showModalBottomSheet<StickerItem>(
      context: context,
      backgroundColor: EchoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => _StickerSheet(library: library),
    );

    if (picked != null) await _send(sticker: picked);
  }

  @override
  Widget build(BuildContext context) {
    final persona = ref.watch(personaByIdProvider(widget.personaId));
    final thread = ref.watch(privateThreadProvider(widget.personaId));
    final name = persona?.name ?? '社区住民';

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
                          avatarRef: persona?.avatar,
                        );
                      },
                    ),
            ),
          ),
          _Composer(
            controller: _input,
            onSend: _send,
            onSticker: _pickSticker,
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
      child: Row(
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
    );
  }

  Widget _content(bool fromMe) {
    // 表情包就是一张图，不套气泡——套上就像给图加了个相框
    if (message.mediaType == 'sticker') {
      return SizedBox(
        width: 118,
        height: 118,
        child: PostImage(ref: message.content, height: 118),
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
    required this.onSend,
    required this.onSticker,
  });

  final TextEditingController controller;
  final Future<void> Function({String? text, StickerItem? sticker}) onSend;
  final VoidCallback onSticker;

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
            onPressed: onSticker,
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
              onSubmitted: (_) => onSend(),
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
            onPressed: () => onSend(),
            tooltip: '发送',
            icon: Icon(Icons.send_rounded, color: EchoColors.primary, size: 22),
          ),
        ],
      ),
    );
  }
}

/// 表情包选择：内置素材 + 自己存的那几张。
class _StickerSheet extends StatelessWidget {
  const _StickerSheet({required this.library});

  final StickerLibrary library;

  @override
  Widget build(BuildContext context) {
    final stickers = library.stickers;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '表情包',
              style: TextStyle(
                color: EchoColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (stickers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '还没有表情包素材。',
                  style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
                ),
              )
            else
              SizedBox(
                height: 220,
                child: GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    for (final sticker in stickers)
                      InkWell(
                        onTap: () => Navigator.of(context).pop(sticker),
                        child: _StickerThumb(item: sticker),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StickerThumb extends StatelessWidget {
  const _StickerThumb({required this.item});

  final StickerItem item;

  @override
  Widget build(BuildContext context) {
    if (!item.hasImage) {
      return Center(
        child: Text(
          item.fallbackText,
          textAlign: TextAlign.center,
          style: TextStyle(color: EchoColors.textMuted, fontSize: 12),
        ),
      );
    }

    return item.isAsset
        ? Image.asset(item.rawPath, fit: BoxFit.contain)
        : Image.file(File(item.rawPath), fit: BoxFit.contain);
  }
}
