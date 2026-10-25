import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../data/media/media_service.dart';

/// 选图的唯一入口：拍一张，还是从相册挑。
///
/// 所有需要图片的地方都走这里，免得每个页面各写一份“拍照 / 相册”的弹层。
/// 返回值是 `file:` 引用；用户取消时返回 null。
Future<String?> pickImageWithSource(
  BuildContext context,
  WidgetRef ref,
) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: EchoColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 34,
            height: 4,
            decoration: BoxDecoration(
              color: EchoColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          _SourceTile(
            icon: Icons.photo_camera_outlined,
            label: '拍一张',
            hint: '只存进 APP，不进系统相册',
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
          _SourceTile(
            icon: Icons.photo_library_outlined,
            label: '从相册选择',
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
  if (source == null) return null;

  final media = ref.read(mediaServiceProvider);
  return source == ImageSource.camera
      ? media.pickFromCamera()
      : media.pickFromGallery();
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: EchoColors.primary, size: 22),
      title: Text(
        label,
        style: TextStyle(color: EchoColors.text, fontSize: 15),
      ),
      subtitle: hint == null
          ? null
          : Text(
              hint!,
              style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
            ),
      onTap: onTap,
    );
  }
}
