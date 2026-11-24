import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/pet_settings_repository.dart';
import '../../data/repositories/private_message_repository.dart';
import '../../domain/models/custom_resident.dart';
import '../../domain/models/private_message.dart';
import '../../domain/models/sticker.dart';
import '../../domain/services/model_gateway.dart';
import '../../domain/services/photo_describer.dart';
import '../../domain/services/resident_activity_controller.dart';
import '../../domain/services/resident_sleep_service.dart';
import '../../domain/services/resident_timeline.dart';
import '../../domain/services/resident_wake_service.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';
import '../shared_widgets/app_toast.dart';
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
  /// 一次读三十条；往上翻到底再添三十条，不一次读全量。
  static const int _threadPageSize = 30;

  final TextEditingController _input = TextEditingController();
  int _threadLimit = _threadPageSize;
  bool _sending = false;

  /// 上一次读到的消息。往上翻、limit 变大时先继续铺旧列表，
  /// 不让整页闪一下加载圈、顺手把滚动位置弄丢。
  List<PrivateMessage>? _cachedMessages;

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
      ref
          .read(privateMessageRepositoryProvider)
          .markThreadRead(widget.personaId),
    );
  }

  /// 用户翻到最早一条时再往前取三十条。
  void _loadOlder() {
    setState(() => _threadLimit += _threadPageSize);
  }

  /// 我发一句。
  ///
  /// 发完顺手让私信服务排一条回应——**不 await**：排期是他那边的事，
  /// 跟“这句话已经发出去了”没关系，更不该让你等它。
  Future<void> _send({
    String? text,
    StickerItem? sticker,
    String? imageRef,
    String? voiceRef,
    String? transcript,
    int? voiceDurationMs,
  }) async {
    if (_sending) return;
    final content =
        sticker?.path ?? imageRef ?? voiceRef ?? (text ?? '').trim();
    if (content.isEmpty) return;
    final mediaType = sticker != null
        ? 'sticker'
        : (imageRef != null ? 'image' : (voiceRef != null ? 'voice' : 'text'));
    final caption = sticker != null
        ? '表情包「${sticker.name}」'
              '${sticker.tags.isEmpty ? '' : '（标签：${sticker.tags.join('、')}）'}'
        : (voiceRef != null
              ? '语音 ${((voiceDurationMs ?? 0) / 1000).round()} 秒'
              : '');

    final draft = _input.text;
    setState(() => _sending = true);
    // 先把输入框清掉：消息落库还要等一次数据库往返，手指按下去就该有反馈，
    // 不该卡在原地看着自己刚打的字。写入失败再把草稿还回去。
    _input.clear();
    try {
      final messageId = await ref
          .read(privateMessageRepositoryProvider)
          .send(
            personaId: widget.personaId,
            content: content,
            mediaType: mediaType,
            caption: caption,
            voicePath: voiceRef ?? '',
            transcript: transcript ?? '',
          );

      // 叫醒住民是后台的事：记互动、暂停待发段、补图片描述、发起唤醒
      // 都在 [\_enrichAndWake] 里，不挡“这句话已经发出去了”。
      unawaited(
        _enrichAndWake(
          messageId: messageId,
          content: content,
          mediaType: mediaType,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      if (text != null) _input.text = draft;
      showAppToast(context, '没发出去：$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 消息落库之后的后台收尾：记互动、暂停待发段、补图片描述、叫醒住民。
  ///
  /// 这一轮可能比页面活得久（用户发完就退出）。开头一次性把要用的服务
  /// 取出来，之后不再碰 `ref`，否则卸载后读取会抛错。
  Future<void> _enrichAndWake({
    required String messageId,
    required String content,
    required String mediaType,
  }) async {
    final sleepService = ref.read(residentSleepServiceProvider);
    final messages = ref.read(privateMessageRepositoryProvider);
    final residents = ref.read(customResidentRepositoryProvider);
    final gateway = ref.read(modelGatewayProvider);
    final describer = ref.read(photoDescriberProvider);
    final wakeService = ref.read(residentWakeServiceProvider);

    // 住民被删掉了：不叫醒，也不记这次互动。
    final resident = await residents.findById(widget.personaId);
    if (resident == null) return;

    // 先记互动：如果 TA 正在睡，这一步会当场结束睡眠，并拿到“睡了多久”。
    final sleepNotice = await sleepService.prepareInteraction(widget.personaId);

    // v41：我在他还没说完的时候又插了一句——把上一轮还没到点的段先暂停，
    // 下一轮唤醒会把原话交给他，让他自己决定照发、改写还是算了。
    // 必须在叫醒之前完成，否则他醒来还可能看到旧段。
    await messages.pausePendingSegments(widget.personaId);

    // 消息先出现；图片描述补齐之后再把住民叫醒。
    // 这样模型无论是看图还是读描述，都知道“他发来的到底是什么”。
    if (mediaType == 'image') {
      await _describeImage(
        messageId: messageId,
        imageRef: content,
        resident: resident,
        gateway: gateway,
        messages: messages,
        describer: describer,
      );
    }

    // 他这一轮可能回私信，也可能去帖子下面接话——那是他自己的选择。
    await wakeService.wake(
      widget.personaId,
      trigger: WakeTrigger.userAction,
      sleepNotice: sleepNotice,
    );
  }

  /// 一次发多张图（v50）。
  ///
  /// 每张落成一条 image 私信，像微信一样并排出现；描述全部补齐后
  /// 只叫醒住民一次，免得连发三张就把他叫醒三回。
  Future<void> _sendImages(List<String> imageRefs) async {
    if (_sending || imageRefs.isEmpty) return;
    final messages = ref.read(privateMessageRepositoryProvider);
    setState(() => _sending = true);
    try {
      final sent = <String, String>{};
      for (final imageRef in imageRefs) {
        final id = await messages.send(
          personaId: widget.personaId,
          content: imageRef,
          mediaType: 'image',
        );
        sent[id] = imageRef;
      }
      // 图片先铺出来；描述、暂停旧段和叫醒都放到后台。
      unawaited(_wakeAfterImages(sent));
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '没发出去：$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _wakeAfterImages(Map<String, String> sent) async {
    final sleepService = ref.read(residentSleepServiceProvider);
    final messages = ref.read(privateMessageRepositoryProvider);
    final residents = ref.read(customResidentRepositoryProvider);
    final gateway = ref.read(modelGatewayProvider);
    final describer = ref.read(photoDescriberProvider);
    final wakeService = ref.read(residentWakeServiceProvider);

    final resident = await residents.findById(widget.personaId);
    if (resident == null) return;

    final sleepNotice = await sleepService.prepareInteraction(widget.personaId);
    await messages.pausePendingSegments(widget.personaId);
    for (final entry in sent.entries) {
      await _describeImage(
        messageId: entry.key,
        imageRef: entry.value,
        resident: resident,
        gateway: gateway,
        messages: messages,
        describer: describer,
      );
    }
    await wakeService.wake(
      widget.personaId,
      trigger: WakeTrigger.userAction,
      sleepNotice: sleepNotice,
    );
  }

  /// 文字模型看不懂图时，先把画面描述补进 caption。
  Future<void> _describeImage({
    required String messageId,
    required String imageRef,
    required CustomResident resident,
    required ModelGateway gateway,
    required PrivateMessageRepository messages,
    required PhotoDescriber describer,
  }) async {
    try {
      final config =
          await gateway.configFor(configId: resident.modelConfigId) ??
          await gateway.activeConfig();
      if (config == null || !config.supportsVision) {
        final description = await describer.describe(imageRef);
        if (description.isNotEmpty) {
          await messages.attachCaption(messageId, description);
        }
      }
    } catch (error) {
      // 描述只是兜底：它失败不能让“叫醒住民”也被跳过。
      debugPrint('[图片] 描述兜底没走成：$error');
    }
  }

  /// 通话入口：TA 正控制桌宠时不允许打给他。
  ///
  /// 这是单向的；反过来“通话中桌宠推迟接管”在 PetObserveService 里。
  Future<void> _openCall({required bool video}) async {
    try {
      final repo = ref.read(petSettingsRepositoryProvider);
      final settings = await repo.load();
      if (settings.enabled) {
        final controller = await repo.controllerAt(
          DateTime.now(),
          fallbackResidentId: settings.defaultResidentId,
        );
        if (controller == widget.personaId) {
          if (!mounted) return;
          showAppToast(context, 'TA 正在当桌宠，结束桌宠后再通话');
          return;
        }
      }
    } catch (error) {
      debugPrint('[通话] 控制者检查没成：$error');
    }
    // 打电话也是“直接找 TA”：睡着的住民会在这里被叫醒。
    final sleepNotice = await ref
        .read(residentSleepServiceProvider)
        .prepareInteraction(widget.personaId);
    if (sleepNotice != null) {
      unawaited(
        ref
            .read(residentWakeServiceProvider)
            .wake(
              widget.personaId,
              trigger: WakeTrigger.userAction,
              sleepNotice: sleepNotice,
            ),
      );
    }
    if (!mounted) return;
    context.push(RoutePaths.call(widget.personaId, video: video));
  }

  @override
  Widget build(BuildContext context) {
    // 行为判断用“还在社区里的”；显示名字/头像用“含已删除的”——
    // 删掉的住民仍然是一段历史，不该在会话里变成“社区住民”。
    final resident = ref.watch(customResidentByIdProvider(widget.personaId));
    final storedResident = ref.watch(
      customResidentAnyByIdProvider(widget.personaId),
    );
    final thread = ref.watch(
      privateThreadProvider((
        personaId: widget.personaId,
        limit: _threadLimit,
      )),
    );
    final activity = ref.watch(residentActivityProvider)[widget.personaId];
    final live = activity != null && !activity.isStale ? activity : null;
    // 唤醒结束、但分段的私信还没发完：这几秒显示「正在打字」。
    final typing =
        ref.watch(privateTypingProvider(widget.personaId)).value ?? false;
    final name = storedResident?.name ?? '已离开的住民';
    final avatarRef = storedResident?.avatarAsset;
    // 没有人能接话了：固定住民已删除。保留历史，但不能再发。
    final canSend = resident != null;
    final departed = resident == null;
    final status = departed
        ? '已离开社区'
        : (live?.label ?? (typing ? '正在打字…' : ''));
    final statusActive = live != null || typing;

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
                  // 没有状态时不占这一行：以前那句「固定住民」是写死的标签，
                  // 现在只在 TA 真的在想/在打字/已经离开时才出现。
                  if (status.isNotEmpty)
                    Text(
                      status,
                      style: TextStyle(
                        color: statusActive
                            ? EchoColors.primary
                            : EchoColors.textFaint,
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
                loading: () {
                  final cached = _cachedMessages;
                  if (cached == null) {
                    return Center(
                      child: CircularProgressIndicator(color: EchoColors.primary),
                    );
                  }
                  return _MessageList(
                    messages: cached,
                    name: name,
                    avatarRef: avatarRef,
                    residentId: widget.personaId,
                  );
                },
                error: (error, _) => Center(
                  child: Text(
                    '读不到会话：$error',
                    style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
                  ),
                ),
                data: (list) {
                  _cachedMessages = list;
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
                          residentId: widget.personaId,
                          onLoadOlder: list.length >= _threadLimit
                              ? _loadOlder
                              : null,
                        );
                },
              ),
            ),
            if (canSend) ...[
              ChatComposer(
                controller: _input,
                sending: _sending,
                onSend: _send,
                onSendImages: _sendImages,
                onVoiceCall: () => _openCall(video: false),
                onVideoCall: () => _openCall(video: true),
              ),
            ] else
              const _DepartedNotice(),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends ConsumerWidget {
  const _MessageList({
    required this.messages,
    required this.name,
    required this.avatarRef,
    required this.residentId,
    this.onLoadOlder,
  });

  final List<PrivateMessage> messages;
  final String residentId;
  final String name;
  final String? avatarRef;

  /// 滚到最早一条时为 null：已经到底，没有更早的消息了。
  final VoidCallback? onLoadOlder;

  /// 长按删除单条。聊天记录和上下文时间线一起删——
  /// 只删界面的话，住民下次醒来还会记得这句话。
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PrivateMessage message,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: EchoColors.surface,
        title: const Text('删除这条消息？'),
        content: Text('删掉后聊天记录里不会再显示，$name 也不会再记得这句话。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('删除', style: TextStyle(color: EchoColors.like)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(privateMessageRepositoryProvider).deleteMessage(message.id);
    await ref.read(residentTimelineProvider).deleteDmEvent(message.id);
    // 删掉的话不能还留在常驻窗口里。
    ref.read(residentWakeServiceProvider).invalidateWindow(residentId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          onLongPress: () => _delete(context, ref, message),
        ),
      );
      previousSender = sender;
    }

    return NotificationListener<ScrollNotification>(
      // 列表是 reverse 的：maxScrollExtent 那头就是最早的一条。
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (onLoadOlder != null &&
            metrics.maxScrollExtent > 0 &&
            metrics.pixels >= metrics.maxScrollExtent - 240) {
          onLoadOlder!();
        }
        return false;
      },
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        itemCount: rows.length,
        itemBuilder: (context, index) => rows[rows.length - 1 - index],
      ),
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
          Icon(Icons.lock_outline, size: 15, color: EchoColors.textFaint),
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
