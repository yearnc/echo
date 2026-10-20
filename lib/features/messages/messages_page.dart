import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/private_message_repository.dart';
import '../../domain/models/custom_resident.dart';
import '../../domain/models/private_message.dart';
import '../shared_widgets/user_avatar.dart';

/// 消息页（B5）：你和住民一对一聊过的那几个人。
///
/// 列表上只有**聊过的人**，不是全部住民——私信是一段已经发生的关系，
/// 不是一份通讯录。想开一段新的，去他的主页点「发消息」。
class MessagesPage extends ConsumerWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final residents = ref.watch(customResidentsProvider).value ?? const [];

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        title: Text(
          '消息',
          style: TextStyle(
            color: EchoColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // 关注与粉丝（B5）：它和私信是一类东西——都是"你和某个人的一对一"
          IconButton(
            onPressed: () => context.push(RoutePaths.follows),
            tooltip: '关注与粉丝',
            icon: Icon(
              Icons.people_alt_outlined,
              color: EchoColors.textMuted,
              size: 20,
            ),
          ),
        ],
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
          // 还没聊过的固定住民单独列在下面：设置完就能直接开聊，
          // 不用等关系升温，也不用等他先来敲门。
          final started = {for (final item in list) item.personaId};
          final fresh = residents
              .where((resident) => !started.contains(resident.id))
              .toList(growable: false);

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              if (list.isEmpty)
                const SizedBox(height: 260, child: _Empty()),
              for (final conversation in list) ...[
                _ConversationTile(conversation: conversation),
                Divider(
                  height: 1,
                  color: EchoColors.divider,
                  indent: 74,
                ),
              ],
              if (fresh.isNotEmpty) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 6),
                  child: Text(
                    '固定住民',
                    style: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                for (final resident in fresh)
                  _ResidentEntry(resident: resident),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 还没开过口的固定住民：点一下就能开始一段私信。
class _ResidentEntry extends StatelessWidget {
  const _ResidentEntry({required this.resident});

  final CustomResident resident;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(RoutePaths.chat(resident.id)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
        child: Row(
          children: [
            UserAvatar(
              name: resident.name,
              avatarRef: resident.avatarAsset,
              size: 46,
              showRing: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    resident.name,
                    style: TextStyle(
                      color: EchoColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    resident.bio.trim().isEmpty
                        ? '点开说第一句话'
                        : resident.bio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: EchoColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resident = ref.watch(customResidentByIdProvider(conversation.personaId));
    final persona = ref.watch(personaByIdProvider(conversation.personaId));
    final name = resident?.name ?? persona?.name ?? '社区住民';
    final unread = conversation.unreadCount > 0;

    return InkWell(
      onTap: () => context.push(RoutePaths.chat(conversation.personaId)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            UserAvatar(
              name: name,
              avatarRef: resident?.avatarAsset ?? persona?.avatar,
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
                      const SizedBox(width: 8),
                      Text(
                        RelativeTime.format(conversation.lastAt),
                        style: TextStyle(
                          color: EchoColors.textFaint,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
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
