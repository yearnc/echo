import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/post_repository.dart';
import '../../domain/models/post.dart';

/// 删除自己的帖子：确认 + 软删除。信息流和详情页共用这一份。
///
/// 返回 true 表示真的删了（详情页据此退回上一页）。
Future<bool> confirmDeletePost(
  BuildContext context,
  WidgetRef ref,
  Post post,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: EchoColors.surface,
      title: Text(
        '删除这条帖子？',
        style: TextStyle(color: EchoColors.text, fontSize: 15),
      ),
      content: Text(
        '评论、还没发生的互动和通知会一起收走。删除后不会出现在信息流和你的主页。',
        style: TextStyle(color: EchoColors.textMuted, fontSize: 13, height: 1.7),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('再想想'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('删除', style: TextStyle(color: EchoColors.like)),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  await ref.read(postRepositoryProvider).softDelete(post.id);
  if (!context.mounted) return true;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('帖子已删除')));
  return true;
}
