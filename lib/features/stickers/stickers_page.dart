import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/sticker_repository.dart';
import '../../domain/models/sticker.dart';

/// 头像与表情包管理页（规划书 §11）。
///
/// 内置素材不落库：它们以 `assets/stickers.json` 为准，把图片丢进
/// `assets/stickers/<分类>/` 目录再在 json 里登记一行就能生效。
/// 页面上只做两件事——把现有素材摆出来、把用户自己的图导进来。
///
/// 图片缺失时一律降级成名字文字贴片，所以这个页面在素材还没准备好的阶段
/// 也是可用的（开发期默认就是这一级）。
class StickersPage extends ConsumerWidget {
  const StickersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLibrary = ref.watch(stickerLibraryProvider);

    return Scaffold(
      backgroundColor: ClearColors.bg,
      appBar: AppBar(
        backgroundColor: ClearColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: ClearColors.text),
        title: Text(
          '头像与表情包',
          style: TextStyle(color: ClearColors.text, fontSize: 16),
        ),
      ),
      body: asyncLibrary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            '读取失败：$error',
            style: TextStyle(color: ClearColors.textMuted, fontSize: 12.5),
          ),
        ),
        data: (library) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _ImportCard(onImport: () => _import(context, ref)),
            const SizedBox(height: 18),
            for (final category in library.categories)
              _CategorySection(
                category: category,
                items: library.stickers
                    .where((item) => item.category == category.id)
                    .toList(growable: false),
                onDelete: (item) => _confirmDelete(context, ref, item),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    // 版权确认先于选图：让用户在挑图之前就知道自己在承担什么
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ClearColors.surface,
        title: Text(
          '导入图片',
          style: TextStyle(color: ClearColors.text, fontSize: 15),
        ),
        content: Text(
          '请确认你有权使用这张图片。\n'
          '导入后它只保存在这台设备上，不会上传到任何服务器。',
          style: TextStyle(
            color: ClearColors.textMuted,
            fontSize: 13,
            height: 1.8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: TextStyle(color: ClearColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('继续选图', style: TextStyle(color: ClearColors.accent)),
          ),
        ],
      ),
    );
    if (agreed != true || !context.mounted) return;

    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (name == null || !context.mounted) return;

    final id = await ref
        .read(stickerRepositoryProvider)
        .importFromGallery(name: name);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(id == null ? '没有选择图片' : '已导入「$name」')),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    StickerItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ClearColors.surface,
        title: Text(
          '删除素材',
          style: TextStyle(color: ClearColors.text, fontSize: 15),
        ),
        content: Text(
          '「${item.name}」会被移出素材库，已发出去的帖子不受影响。',
          style: TextStyle(
            color: ClearColors.textMuted,
            fontSize: 13,
            height: 1.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: TextStyle(color: ClearColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('删除', style: TextStyle(color: ClearColors.like)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(stickerRepositoryProvider).deleteUserSticker(item.id);
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ClearColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ClearColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '素材库',
            style: TextStyle(
              color: ClearColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '内置素材由项目提供；你也可以导入自己的图片。\n'
            '同一个位置换一张图，整个 APP 里所有用到它的地方都会跟着换。',
            style: TextStyle(
              color: ClearColors.textMuted,
              fontSize: 12.5,
              height: 1.8,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('导入图片'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ClearColors.accent,
                side: BorderSide(color: ClearColors.divider),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.items,
    required this.onDelete,
  });

  final StickerCategory category;
  final List<StickerItem> items;
  final ValueChanged<StickerItem> onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Text(
              '${category.name}（${items.length}）',
              style: TextStyle(
                color: ClearColors.textFaint,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 92,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.86,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => _StickerTile(
              item: items[index],
              onDelete: items[index].isUser
                  ? () => onDelete(items[index])
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerTile extends StatelessWidget {
  const _StickerTile({required this.item, this.onDelete});

  final StickerItem item;

  /// 只有用户导入的素材可以删；内置的没有删除入口。
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: ClearColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ClearColors.divider),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(child: _preview()),
              const SizedBox(height: 6),
              Text(
                item.fallbackText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ClearColors.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
        if (onDelete != null)
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: ClearColors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: ClearColors.like,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 图片优先、文字兜底。图片文件被删掉时也要能降级，不然整个网格会红一片。
  Widget _preview() {
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
    return image;
  }

  Widget _fallback() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: ClearColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          item.fallbackText,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ClearColors.accent,
            fontSize: 10.5,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ClearColors.surface,
      title: Text(
        '给它起个名字',
        style: TextStyle(color: ClearColors.text, fontSize: 15),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 12,
        style: TextStyle(color: ClearColors.text, fontSize: 14),
        decoration: InputDecoration(
          hintText: '比如：摸鱼猫猫',
          hintStyle: TextStyle(color: ClearColors.textFaint, fontSize: 13),
          counterStyle: TextStyle(color: ClearColors.textFaint, fontSize: 11),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: ClearColors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text('选图', style: TextStyle(color: ClearColors.accent)),
        ),
      ],
    );
  }
}
