import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_texts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/db/app_database.dart';
import '../../data/media/media_service.dart';
import '../../data/repositories/clear_photo_repository.dart';
import '../shared_widgets/image_source_sheet.dart';
import '../shared_widgets/post_image.dart';

/// 真实生活相册（v31）。
///
/// 只收用户主动拍/选的照片，全部落在清醒侧；没有滤镜、没有 AI 生成，
/// 也不进回响信息流。它的存在是为了让“生活里真的发生过什么”
/// 有一个能被看见的地方。
class ClearAlbumPage extends ConsumerWidget {
  const ClearAlbumPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clearPhotosProvider);

    return Scaffold(
      backgroundColor: ClearColors.bg,
      appBar: AppBar(
        backgroundColor: ClearColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: ClearColors.text),
        title: Text(
          '真实生活相册',
          style: TextStyle(color: ClearColors.text, fontSize: 16),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context, ref),
        backgroundColor: ClearColors.primary,
        foregroundColor: Colors.white,
        tooltip: '添加照片',
        child: const Icon(Icons.add_a_photo_outlined),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Text(
            AppTexts.permanentNotice,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ClearColors.textFaint,
              fontSize: 10.5,
            ),
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            '读取失败：$error',
            style: TextStyle(color: ClearColors.textMuted, fontSize: 12.5),
          ),
        ),
        data: (photos) => photos.isEmpty
            ? _Empty(onAdd: () => _add(context, ref))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                children: [
                  Text(
                    '只收你主动选的照片。它们不会进社区，也不会发给模型。',
                    style: TextStyle(
                      color: ClearColors.textFaint,
                      fontSize: 11.5,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.82,
                        ),
                    itemCount: photos.length,
                    itemBuilder: (context, index) => _PhotoTile(
                      photo: photos[index],
                      onTap: () => _open(context, ref, photos[index]),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final path = await pickImageWithSource(context, ref);
    if (path == null || !context.mounted) return;

    final caption = await showDialog<String>(
      context: context,
      builder: (_) => _CaptionDialog(imageRef: path),
    );
    if (caption == null) {
      // 用户取消：刚拷进私有目录的图不该留下。
      await ref.read(mediaServiceProvider).deleteByRef(path);
      return;
    }
    await ref.read(clearPhotoRepositoryProvider).add(
      path: path,
      caption: caption,
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    ClearPhotoRow photo,
  ) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: ClearColors.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: PostImage(ref: photo.path, height: 260),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (photo.caption.isNotEmpty)
                    Text(
                      photo.caption,
                      style: TextStyle(
                        color: ClearColors.text,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    RelativeTime.format(
                      DateTime.fromMillisecondsSinceEpoch(photo.createdAt),
                    ),
                    style: TextStyle(
                      color: ClearColors.textFaint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop('delete'),
                  child: Text(
                    '删除',
                    style: TextStyle(color: ClearColors.like),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (action == 'delete') {
      await ref.read(clearPhotoRepositoryProvider).delete(photo);
    }
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.onTap});

  final ClearPhotoRow photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: ClearColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ClearColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: PostImage(ref: photo.path, borderRadius: 0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(
                photo.caption.isEmpty ? '没有写说明' : photo.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: photo.caption.isEmpty
                      ? ClearColors.textFaint
                      : ClearColors.text,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptionDialog extends StatefulWidget {
  const _CaptionDialog({required this.imageRef});

  final String imageRef;

  @override
  State<_CaptionDialog> createState() => _CaptionDialogState();
}

class _CaptionDialogState extends State<_CaptionDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ClearColors.surface,
      title: Text(
        '记下这一刻',
        style: TextStyle(color: ClearColors.text, fontSize: 15),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PostImage(ref: widget.imageRef, height: 150, borderRadius: 12),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              maxLength: 120,
              style: TextStyle(color: ClearColors.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: '一句话：这是什么时候、在哪儿',
                hintStyle: TextStyle(
                  color: ClearColors.textFaint,
                  fontSize: 13,
                ),
                counterStyle: TextStyle(
                  color: ClearColors.textFaint,
                  fontSize: 10.5,
                ),
              ),
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
          onPressed: () => Navigator.of(context).pop(_text.text.trim()),
          child: const Text('放进相册'),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 30,
              color: ClearColors.textFaint,
            ),
            const SizedBox(height: 12),
            Text(
              '相册还是空的。\n拍一张今天看到的东西，附上一句话。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ClearColors.textMuted,
                fontSize: 13,
                height: 1.8,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('添加照片'),
            ),
          ],
        ),
      ),
    );
  }
}
