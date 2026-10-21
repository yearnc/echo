import 'package:flutter/material.dart';

import 'post_image.dart';

/// 一条帖子的配图：一张大图，多张宫格。
///
/// 以前信息流和详情页都只画 `images.first`，传两张只看得见一张。
/// 这里按张数排版：2 张两列、4 张 2×2、其余 3 列。
class PostImageGrid extends StatelessWidget {
  const PostImageGrid({
    super.key,
    required this.images,
    this.singleHeight = 220,
    this.spacing = 6,
  });

  final List<String> images;
  final double singleHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    if (images.length == 1) {
      return PostImage(ref: images.first, height: singleHeight);
    }

    final columns = switch (images.length) {
      2 => 2,
      4 => 2,
      _ => 3,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final tile =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final ref in images)
              SizedBox(
                width: tile,
                height: tile,
                child: PostImage(
                  ref: ref,
                  height: tile,
                  borderRadius: 10,
                ),
              ),
          ],
        );
      },
    );
  }
}
