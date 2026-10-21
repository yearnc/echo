import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/sticker_repository.dart';
import '../../domain/models/sticker.dart';

/// 表情包管理页（规划书 §11）。
///
/// v3.2 起没有内置素材：所有表情都由用户从相册导入，并自己打标签。
/// 标签决定 AI 什么时候会用这张图；没标签的会标成“AI 不会用”，
/// 点一下素材就能补。
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
            if (library.stickers.any((item) => item.tags.isEmpty)) ...[
              const SizedBox(height: 12),
              _TagWarning(
                count: library.stickers
                    .where((item) => item.tags.isEmpty)
                    .length,
              ),
            ],
            const SizedBox(height: 18),
            for (final category in library.categories)
              _CategorySection(
                category: category,
                items: library.stickers
                    .where((item) => item.category == category.id)
                    .toList(growable: false),
                onDelete: (item) => _confirmDelete(context, ref, item),
                onEditTags: (item) => _editTags(context, ref, item),
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

    // 标签是 AI 什么时候用这张图的唯一依据；不强制，但要说清楚。
    final tags = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _TagDialog(title: '给这张表情打标签'),
    );
    if (tags == null || !context.mounted) return;

    final id = await ref
        .read(stickerRepositoryProvider)
        .importFromGallery(name: name, tags: tags);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          id == null
              ? '没有选择图片'
              : (tags.isEmpty ? '已导入「$name」，补个标签 AI 才会用它' : '已导入「$name」'),
        ),
      ),
    );
  }

  Future<void> _editTags(
    BuildContext context,
    WidgetRef ref,
    StickerItem item,
  ) async {
    final tags = await showDialog<List<String>>(
      context: context,
      builder: (_) => _TagDialog(
        title: '编辑「${item.name}」的标签',
        initial: item.tags,
      ),
    );
    if (tags == null) return;
    await ref.read(stickerRepositoryProvider).updateTags(item.id, tags);
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
            '素材全部由你自己导入，只保存在这台设备上。\n'
            '导入时记得打标签：AI 靠标签判断什么时候该用它。',
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
    required this.onEditTags,
  });

  final StickerCategory category;
  final List<StickerItem> items;
  final ValueChanged<StickerItem> onDelete;
  final ValueChanged<StickerItem> onEditTags;

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
              onEditTags: items[index].isUser
                  ? () => onEditTags(items[index])
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerTile extends StatelessWidget {
  const _StickerTile({required this.item, this.onDelete, this.onEditTags});

  final StickerItem item;

  /// 只有用户导入的素材可以删；内置的没有删除入口。
  final VoidCallback? onDelete;

  /// 点一下改标签。没标签的表情不显示“AI 可用”。
  final VoidCallback? onEditTags;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onEditTags,
          child: Container(
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
              const SizedBox(height: 2),
              Text(
                item.tags.isEmpty ? 'AI 不会用' : item.tagLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: item.tags.isEmpty
                      ? ClearColors.like.withValues(alpha: 0.8)
                      : ClearColors.accent,
                  fontSize: 9,
                ),
              ),
            ],
          ),
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

class _TagWarning extends StatelessWidget {
  const _TagWarning({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ClearColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ClearColors.divider),
      ),
      child: Text(
        '有 $count 张表情还没标签。没有标签，AI 不知道该在什么时候用它；'
        '点一下素材就能补。',
        style: TextStyle(
          color: ClearColors.textMuted,
          fontSize: 12,
          height: 1.6,
        ),
      ),
    );
  }
}

/// 标签选择：预设 + 自定义。返回 null 表示取消。
class _TagDialog extends StatefulWidget {
  const _TagDialog({required this.title, this.initial = const []});

  final String title;
  final List<String> initial;

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  static const _presets = [
    '开心',
    '无语',
    '吐槽',
    '安慰',
    '点赞',
    '惊讶',
    '生气',
    '撒娇',
    '吃瓜',
    '赞同',
    '鼓励',
    '抱抱',
  ];

  late final Set<String> _selected = {...widget.initial};
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _toggle(String tag) {
    setState(() {
      if (!_selected.remove(tag)) _selected.add(tag);
    });
  }

  void _addCustom() {
    final value = _custom.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _selected.add(value);
      _custom.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ClearColors.surface,
      title: Text(
        widget.title,
        style: TextStyle(color: ClearColors.text, fontSize: 15),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '标签决定 AI 什么时候用它。比如「安慰 / 抱抱」会被用在对方难过时，'
              '「吐槽 / 看戏」不会。',
              style: TextStyle(
                color: ClearColors.textMuted,
                fontSize: 12,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final tag in {..._presets, ..._selected})
                  GestureDetector(
                    onTap: () => _toggle(tag),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _selected.contains(tag)
                            ? ClearColors.accent.withValues(alpha: 0.16)
                            : ClearColors.bg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _selected.contains(tag)
                              ? ClearColors.accent
                              : ClearColors.divider,
                        ),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          color: _selected.contains(tag)
                              ? ClearColors.accent
                              : ClearColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _custom,
                    onSubmitted: (_) => _addCustom(),
                    style: TextStyle(color: ClearColors.text, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '自定义标签',
                      isDense: true,
                      hintStyle: TextStyle(
                        color: ClearColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                TextButton(onPressed: _addCustom, child: const Text('加上')),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: ClearColors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
          child: const Text('保存标签'),
        ),
      ],
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
