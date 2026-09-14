import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/sticker.dart';

/// 内置素材清单（`assets/stickers.json`）。
///
/// 清单放在 assets 而不是数据库里，是为了让"丢一张图进目录"就能生效：
/// 把图片按分类放好、在 json 里登记一行即可，业务代码不用动。
/// 图片缺失也不会崩——UI 会降级成名字文字贴片。
class BuiltinStickers {
  const BuiltinStickers._();

  static const String assetPath = 'assets/stickers.json';

  static Future<StickerLibrary> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final categories = (json['categories'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => StickerCategory(
            id: item['id'] as String? ?? '',
            name: item['name'] as String? ?? '',
          ),
        )
        .where((category) => category.id.isNotEmpty)
        .toList(growable: false);

    final stickers = (json['stickers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => StickerItem(
            id: item['id'] as String? ?? '',
            name: item['name'] as String? ?? '未命名',
            category: item['category'] as String? ?? StickerCategory.customId,
            path: item['path'] as String? ?? '',
            isBuiltin: true,
          ),
        )
        .where((sticker) => sticker.id.isNotEmpty)
        .toList(growable: false);

    return StickerLibrary(categories: categories, stickers: stickers);
  }
}
