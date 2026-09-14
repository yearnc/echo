/// 素材（头像 / 表情包）的领域模型（规划书 §11）。
library;

/// 素材分类（开心 / 安慰 / 吐槽 / 震惊 / 点赞 / 无语 / 鼓励 / 自定义）。
class StickerCategory {
  const StickerCategory({required this.id, required this.name});

  final String id;
  final String name;

  /// 用户导入的素材默认落在这里。
  static const String customId = 'custom';

  static const StickerCategory custom = StickerCategory(
    id: customId,
    name: '自定义',
  );
}

/// 一条素材。
///
/// [path] 的两种形态（`asset:` 内置 / `file:` 用户上传）对 UI 是同一件事：
/// 页面只负责"显示这张图，缺了就显示名字"——内置图被换成自己的图时，
/// 不该出现两套行为。
class StickerItem {
  const StickerItem({
    required this.id,
    required this.name,
    required this.category,
    required this.path,
    this.isUser = false,
    this.isBuiltin = false,
  });

  final String id;
  final String name;
  final String category;
  final String path;
  final bool isUser;
  final bool isBuiltin;

  /// 图片缺失时显示的文字。
  ///
  /// 名字形如「安慰·摸摸头」，兜底只取破折号后面那截——
  /// 摆在网格里时，「摸摸头」比「安慰·摸摸头」更好认。
  String get fallbackText {
    final index = name.indexOf('·');
    if (index < 0 || index == name.length - 1) return name;
    return name.substring(index + 1);
  }

  /// 去掉协议前缀、可以直接交给 `AssetImage` / `FileImage` 的路径。
  String get rawPath {
    if (path.startsWith('asset:')) return path.substring('asset:'.length);
    if (path.startsWith('file:')) return path.substring('file:'.length);
    return path;
  }

  bool get isAsset => path.startsWith('asset:');

  bool get hasImage => path.isNotEmpty;
}

/// 一次加载拿到的整套素材。
class StickerLibrary {
  const StickerLibrary({required this.categories, required this.stickers});

  final List<StickerCategory> categories;
  final List<StickerItem> stickers;

  static const StickerLibrary empty = StickerLibrary(
    categories: [],
    stickers: [],
  );
}
