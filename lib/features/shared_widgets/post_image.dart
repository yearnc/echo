import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 帖子配图。
///
/// 与 [UserAvatar] 同一套引用约定（`asset:` / `file:` / `http`）。
/// 素材还没放进来时渲染一个**有意设计的占位块**（柔和渐变 + 提示文字），
/// 而不是红色报错框——演示彩排时如果图还没到位，画面也不至于难看。
class PostImage extends StatelessWidget {
  const PostImage({super.key, required this.ref, this.height = 220});

  final String ref;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (ref.startsWith('asset:')) {
      return Image.asset(
        ref.substring('asset:'.length),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    if (ref.startsWith('file:')) {
      final file = File(ref.substring('file:'.length));
      if (!file.existsSync()) return _placeholder();
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return Image.network(
        ref,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final fileName = ref.split('/').last;
    return DecoratedBox(
      // 占位底色跟着当前调色板走，日间下不会突然出现一块深色
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [EchoColors.surfaceHigh, EchoColors.overlay],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, color: EchoColors.textFaint, size: 26),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '素材待放入 $fileName',
                textAlign: TextAlign.center,
                style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
