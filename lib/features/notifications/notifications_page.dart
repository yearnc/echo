import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/notification_repository.dart';
import '../../domain/models/app_notification.dart';

/// 通知页（规划书 §3.7）。
///
/// 文案刻意**不带 AI 前缀**——"温柔学姐 评论了你的帖子"，
/// 沉浸感就是靠这些细节堆出来的。合规交给页面底部那行小字。
/// 通知由调度器在兑现互动时写入，所以这里的每一条背后都真的发生过一次互动。
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    // 打开通知页 = 看过了，红点该灭——这是用户对通知的常识预期。
    // 放在首帧之后，避免在 build 期间写库触发重建。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(notificationRepositoryProvider).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);

    return Container(
      color: EchoColors.bg,
      child: notifications.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: EchoColors.primary)),
        error: (error, _) => Center(
          child: Text(
            '通知加载失败：$error',
            style: TextStyle(color: EchoColors.like, fontSize: 12),
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            Row(
              children: [
                Text(
                  '通知',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(color: EchoColors.text, fontSize: 24),
                ),
                if (list.any((item) => !item.isRead)) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: EchoColors.like,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    // 显示的是**未读数**：看过的通知不该继续占着这个数字
                    child: Text(
                      '${list.where((item) => !item.isRead).length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (list.any((item) => !item.isRead))
                  GestureDetector(
                    onTap: () =>
                        ref.read(notificationRepositoryProvider).markAllRead(),
                    child: Text(
                      '全部已读',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: EchoColors.primary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (list.isEmpty)
              const _EmptyNotifications()
            else
              for (final item in list)
                _NotifyTile(
                  item: item,
                  // 点了就去看那条帖子——通知本来就是关于它的
                  onTap: item.postId == null
                      ? null
                      : () => context.push(RoutePaths.post(item.postId!)),
                ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                AppTexts.aiDisclaimer,
                style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 70),
      child: Column(
        children: [
          Icon(Icons.notifications_none, size: 30, color: EchoColors.textFaint),
          const SizedBox(height: 14),
          Text(
            AppTexts.emptyNotifications,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: EchoColors.textMuted,
              fontSize: 13,
              height: 1.8,
            ),
          ),
          const SizedBox(height: 6),
          // 只说这一页是干什么的，不说互动什么时候来——
          // "0—48 小时"是调度机制，不该出现在用户眼前（同帖子详情空评论区）
          Text(
            '有人回应你的时候，这里会有提示',
            style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _NotifyTile extends StatelessWidget {
  const _NotifyTile({required this.item, this.onTap});

  final AppNotification item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isLike = item.type == 'like';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: EchoColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: item.isRead
                  ? EchoColors.divider
                  : EchoColors.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isLike ? EchoColors.like : EchoColors.primary)
                      .withValues(alpha: 0.16),
                ),
                child: Icon(
                  isLike ? Icons.favorite : Icons.mode_comment_outlined,
                  size: 18,
                  color: isLike ? EchoColors.like : EchoColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        color: EchoColors.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                    if (item.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: EchoColors.textFaint,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                RelativeTime.short(item.createdAt),
                style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 15,
                  color: EchoColors.textFaint,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
