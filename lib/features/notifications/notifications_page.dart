import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_texts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/persona_repository.dart';
import '../shared_widgets/user_avatar.dart';

/// 通知页（规划书 §3.7）。
///
/// 文案刻意**不带 AI 前缀**——"温柔学姐 评论了你的帖子"，
/// 沉浸感就是靠这些细节堆出来的。合规交给页面底部那行小字。
/// 锁屏通知默认隐藏具体内容，所以列表里的正文也只给一句模糊描述。
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  /// 预置通知（阶段 B 由调度器写入 notification_logs）。
  static const List<_NotifyItem> _items = [
    _NotifyItem('persona_001', '评论了你的帖子', '看到这条的时候刚好在图书馆靠窗的位置…', 12),
    _NotifyItem('persona_006', '评论了你的帖子', '认真看了很久，想说这张照片比它看起来的要重得多…', 26),
    _NotifyItem.group('5 位社区住民', '互动了你的帖子', '你有一条社区互动通知', 41),
    _NotifyItem('persona_004', '赞了你的帖子', '', 58),
    _NotifyItem('persona_009', '关注了你', '', 96),
    _NotifyItem.group('23 位社区住民', '赞了你的帖子', '你有一条社区互动通知', 132),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: EchoColors.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Row(
            children: [
              Text('通知',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: EchoColors.text,
                        fontSize: 24,
                      )),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: EchoColors.like,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Text('6',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              Text('全部已读',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: EchoColors.primary)),
            ],
          ),
          const SizedBox(height: 14),
          for (final item in _items) _NotifyTile(item: item),
          const SizedBox(height: 8),
          Center(
            child: Text(
              AppTexts.aiDisclaimer,
              style: const TextStyle(color: EchoColors.textFaint, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifyItem {
  const _NotifyItem(this.personaId, this.action, this.preview, this.minutesAgo)
      : name = '',
        isGroup = false;

  const _NotifyItem.group(this.name, this.action, this.preview, this.minutesAgo)
      : personaId = '',
        isGroup = true;

  final String personaId;
  final String name;
  final String action;
  final String preview;
  final int minutesAgo;
  final bool isGroup;
}

class _NotifyTile extends ConsumerWidget {
  const _NotifyTile({required this.item});

  final _NotifyItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persona = item.personaId.isEmpty
        ? null
        : ref.watch(personaByIdProvider(item.personaId));
    final name = item.isGroup ? item.name : (persona?.name ?? '社区住民');
    final createdAt = DateTime.now().subtract(Duration(minutes: item.minutesAgo));

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: EchoColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EchoColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.isGroup)
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: EchoColors.primary.withValues(alpha: 0.16),
                ),
                child: const Icon(Icons.groups_outlined,
                    size: 19, color: EchoColors.primary),
              )
            else
              UserAvatar(name: name, avatarRef: persona?.avatar, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: name,
                          style: const TextStyle(
                            color: EchoColors.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                        TextSpan(
                          text: ' ${item.action}',
                          style: const TextStyle(
                            color: EchoColors.textMuted,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.preview.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: EchoColors.textFaint, fontSize: 12, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(RelativeTime.short(createdAt),
                style: const TextStyle(color: EchoColors.textFaint, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
