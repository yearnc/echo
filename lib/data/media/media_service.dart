import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 图片素材的本地化。
///
/// 用户选的图会被**复制进 APP 私有目录**，而不是只存一个外部路径——
/// 相册里的原图被删掉或被系统清理后，帖子里的图不该跟着消失。
/// 返回的是 `file:` 引用，与头像、表情包共用同一套约定。
class MediaService {
  const MediaService();

  static const String mediaDirName = 'media';

  /// 从相册选一张图并落盘。用户取消时返回 null。
  Future<String?> pickFromGallery() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 2000,
    );
    if (picked == null) return null;
    return _persist(picked);
  }

  Future<String?> _persist(XFile picked) async {
    final docs = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(docs.path, mediaDirName));
    if (!mediaDir.existsSync()) {
      await mediaDir.create(recursive: true);
    }

    final extension = p.extension(picked.path).isEmpty
        ? '.jpg'
        : p.extension(picked.path).toLowerCase();
    final fileName = 'img_${DateTime.now().microsecondsSinceEpoch}$extension';
    final destination = File(p.join(mediaDir.path, fileName));

    await File(picked.path).copy(destination.path);
    return 'file:${destination.path}';
  }

  /// 撤销一次附图（用户删掉刚选的图时清理磁盘）。
  Future<void> deleteByRef(String ref) async {
    if (!ref.startsWith('file:')) return;
    final file = File(ref.substring('file:'.length));
    if (file.existsSync()) {
      await file.delete();
    }
  }
}

final mediaServiceProvider = Provider<MediaService>(
  (ref) => const MediaService(),
);
