import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/sticker_repository.dart';
import '../../domain/models/sticker.dart';

/// 表情包选择：私信和评论区共用同一份实现。
Future<StickerItem?> showStickerPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final library = await ref.read(stickerLibraryProvider.future);
  if (!context.mounted) return null;

  return showModalBottomSheet<StickerItem>(
    context: context,
    backgroundColor: EchoColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
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
            if (library.stickers.isEmpty)
              _EmptySheet(onImport: () {
                Navigator.of(sheetContext).pop();
                context.push(RoutePaths.stickers);
              })
            else
              SizedBox(
                height: 240,
                child: GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    for (final sticker in library.stickers)
                      InkWell(
                        onTap: () => Navigator.of(sheetContext).pop(sticker),
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
              ),
          ],
        ),
      ),
    ),
  );
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
