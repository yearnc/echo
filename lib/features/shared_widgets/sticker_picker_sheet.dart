import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/sticker_repository.dart';
import '../../domain/models/sticker.dart';

/// 表情包选择：私信和评论区共用同一份实现。
///
/// 弹层**立刻出现**，库在弹层里异步加载：以前先 await 库再弹，
/// 首次打开或读取失败时按钮看起来像“点了没反应”。
Future<StickerItem?> showStickerPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  // 键盘还开着会把 240 高的网格顶出屏幕，先收键盘再弹。
  FocusScope.of(context).unfocus();

  return showModalBottomSheet<StickerItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: EchoColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: SafeArea(
        child: _StickerSheet(
          onImport: () {
            Navigator.of(sheetContext).pop();
            context.push(RoutePaths.stickers);
          },
        ),
      ),
    ),
  );
}

class _StickerSheet extends ConsumerWidget {
  const _StickerSheet({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
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
          // 必须 watch：provider 是 autoDispose，用 ref.read(future) 之后
          // 没有监听者，provider 会立刻销毁，Future 永远等不到结果——
          // 表现出来就是“点开表情包一直转圈”。
          Builder(
            builder: (context) {
              final async = ref.watch(stickerLibraryProvider);
              if (async.isLoading) {
                return const SizedBox(
                  height: 120,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              if (async.hasError) {
                return SizedBox(
                  height: 120,
                  child: Center(
                    child: Text(
                      '表情包没读出来，退出后再试一次。',
                      style: TextStyle(
                        color: EchoColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                );
              }
              final stickers = async.value?.stickers ?? const [];
              if (stickers.isEmpty) {
                return _EmptySheet(onImport: onImport);
              }
              return SizedBox(
                height: 240,
                child: GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    for (final sticker in stickers)
                      InkWell(
                        onTap: () => Navigator.of(context).pop(sticker),
                        borderRadius: BorderRadius.circular(10),
                        child: Column(
                          children: [
                            Expanded(child: _Thumb(item: sticker)),
                            const SizedBox(height: 3),
                            Text(
                              sticker.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: EchoColors.textFaint,
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmptySheet extends StatelessWidget {
  const _EmptySheet({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Text(
            '还没有表情包。',
            style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            '导入时记得打标签，AI 才知道什么时候用它。',
            style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 17),
            label: const Text('去导入'),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item});

  final StickerItem item;

  @override
  Widget build(BuildContext context) {
    if (!item.hasImage) return _fallback();
    final image = item.isAsset
        ? Image.asset(
            item.rawPath,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _fallback(),
          )
        : Image.file(
            File(item.rawPath),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _fallback(),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.expand(child: image),
    );
  }

  Widget _fallback() {
    return Center(
      child: Text(
        item.fallbackText,
        textAlign: TextAlign.center,
        style: TextStyle(color: EchoColors.textMuted, fontSize: 11),
      ),
    );
  }
}
