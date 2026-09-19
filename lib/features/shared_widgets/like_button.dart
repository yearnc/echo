import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/post_repository.dart';
import '../../domain/models/post.dart';

/// 给帖子点赞的那颗心。信息流卡片和帖子详情共用这一个。
///
/// 写第二遍是个很容易犯的错误——两处的图标、颜色、计数、点击行为完全一样，
/// 分开写只会带来"改了一处忘了一处"。而且同一个动作在两个地方长得不一样，
/// 用户会以为是两件事。
class LikeButton extends ConsumerWidget {
  const LikeButton({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = post.likedByMe;

    return GestureDetector(
      onTap: () => ref.read(postRepositoryProvider).toggleLike(post.id),
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            liked ? Icons.favorite : Icons.favorite_border,
            size: 16,
            color: EchoColors.like,
          ),
          const SizedBox(width: 4),
          Text(
            '${post.likeCount}',
            style: TextStyle(color: EchoColors.like, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
