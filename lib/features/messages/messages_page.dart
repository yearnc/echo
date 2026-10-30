import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/private_message_repository.dart';
import '../../domain/models/private_message.dart';
import '../../domain/services/resident_activity_controller.dart';
import '../../domain/services/resident_timeline.dart';
import '../shared_widgets/user_avatar.dart';

/// 消息页（B5）：你和住民一对一聊过的那几个人。
///
/// 列表上只有**聊过的人**，不是全部住民——私信是一段已经发生的关系，
/// 不是一份通讯录。想开一段新的，去他的主页点「发消息」。
///
/// 固定住民被删掉之后，对话仍然留在这里（只能回看），名字和头像照旧。
class MessagesPage extends ConsumerWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          '消息',
          style: TextStyle(
            color: EchoColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: conversations.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: EchoColors.primary)),
        error: (error, _) => Center(
          child: Text(
            '读不到消息：$error',
            style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
          ),
        ),
        data: (list) {
          // 不再单列“还没聊过的固定住民”：新建完就直接进他的私信页，
          // 他醒来后会自己发出第一条消息，会话自然出现在这个列表里。
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              if (list.isEmpty)
                const SizedBox(height: 260, child: _Empty()),
              for (final conversation in list) ...[
                _ConversationTile(conversation: conversation),
                Divider(height: 1, color: EchoColors.divider, indent: 74),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 已删除的固定住民也要显示原来的名字和头像：这段会话是历史，
    // 不能因为“人走了”就变成没有面孔的“社区住民”。
    final resident = ref.watch(customResidentByIdProvider(conversation.personaId));
    final storedResident = ref.watch(
      customResidentAnyByIdProvider(conversation.personaId),
    );
    final name = storedResident?.name ?? '已离开的住民';
    final avatarRef = storedResident?.avatarAsset;
    final departed = resident == null;
    final unread = conversation.unreadCount > 0;
    final activity =
        ref.watch(residentActivityProvider)[conversation.personaId];
    final live = activity != null && !activity.isStale ? activity : null;

    final tile = InkWell(
      onTap: () => context.push(RoutePaths.chat(conversation.personaId)),
      onLongPress: departed ? () => _deleteNow(context, ref) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            UserAvatar(
              name: name,
              avatarRef: avatarRef,
              size: 46,
              showRing: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: EchoColors.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (departed) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: EchoColors.surfaceHigh,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '已离开',
                                  style: TextStyle(
                                    color: EchoColors.textFaint,
                                    fontSize: 9.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        RelativeTime.format(conversation.lastAt),
                        style: TextStyle(
                          color: EchoColors.textFaint,
                          fontSize: 11.5,
                        ),
                      ),
                      if (departed) ...[
                        const SizedBox(width: 2),
                        IconButton(
                          onPressed: () => _deleteNow(context, ref),
                          tooltip: '删除这段对话',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          icon: Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: EchoColors.textFaint,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (live != null)
                        Expanded(
                          child: Text(
                            live.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: EchoColors.primary,
                              fontSize: 13,
                            ),
                          ),
                        )
                      else ...[
                        if (conversation.lastFromMe)
                          Text(
                            '我：',
                            style: TextStyle(
                              color: EchoColors.textFaint,
                              fontSize: 13,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            conversation.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: unread
                                  ? EchoColors.text
                                  : EchoColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      if (unread) ...[
                        const SizedBox(width: 8),
                        _UnreadBadge(count: conversation.unreadCount),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return tile;
  }

  Future<void> _deleteNow(BuildContext context, WidgetRef ref) async {
    if (!await _confirmDelete(context)) return;
    await ref
        .read(privateMessageRepositoryProvider)
        .deleteThread(conversation.personaId);
    await ref
        .read(residentTimelineProvider)
        .deleteDmEvents(conversation.personaId);
  }

  /// 已离开的住民不会再有新消息，这段历史可以整段删掉。
  Future<bool> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: EchoColors.surface,
        title: const Text('删除这段对话？'),
        content: const Text('TA 已经离开社区，删除后这段对话不会再出现在消息列表里。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              '删除',
              style: TextStyle(color: EchoColors.like),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: EchoColors.like,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 34,
              color: EchoColors.textFaint,
            ),
            const SizedBox(height: 14),
            Text(
              '还没有人跟你单独说过话。',
              style: TextStyle(color: EchoColors.textMuted, fontSize: 13.5),
            ),
            const SizedBox(height: 6),
            Text(
              '聊得多了，会有人来找你的。',
              style: TextStyle(color: EchoColors.textFaint, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
