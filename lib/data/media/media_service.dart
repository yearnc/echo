import 'dart:io';
import 'dart:typed_data';

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

  /// 现场拍一张。
  ///
  /// 相机把照片先放在系统缓存里；这里只把它**复制进 APP 私有目录**，
  /// 不调用任何“保存到相册”的接口——应用内拍的照片不该出现在系统相册里。
  /// 缓存文件由系统自己回收，不额外处理。
  Future<String?> pickFromCamera() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 2000,
    );
    if (picked == null) return null;
    return _persist(picked);
  }

  Future<String?> _persist(XFile picked) async {
    final mediaDir = await _mediaDir();

    final extension = p.extension(picked.path).isEmpty
        ? '.jpg'
        : p.extension(picked.path).toLowerCase();
    final destination = _newFile(mediaDir, extension);

    await File(picked.path).copy(destination.path);
    return 'file:${destination.path}';
  }

  /// 把一份图片数据直接落盘（住民图文帖用）。
  ///
  /// 模型给的是数据本身，没有"相册里的原文件"可以复制，所以另开这一条。
  /// 落盘位置、命名与用户选的图完全一样——对上层来说都是 `file:` 引用，
  /// 谁也用不着知道那张图是人挑的还是生成的。
  Future<String> saveBytes(Uint8List bytes) async {
    final mediaDir = await _mediaDir();
    final destination = _newFile(mediaDir, extensionOf(bytes));
    await destination.writeAsBytes(bytes);
    return 'file:${destination.path}';
  }

  /// 保存一段参考音频（音色克隆用）。原文件可能是相册/文件管理器给的
  /// 临时缓存，拷进 APP 私有目录才不会过两天就失效。
  Future<String> saveVoiceSample(
    Uint8List bytes, {
    String extension = '.mp3',
  }) async {
    final mediaDir = await _mediaDir();
    final ext = extension.startsWith('.') ? extension : '.$extension';
    final file = File(
      p.join(
        mediaDir.path,
        'voice_sample_${DateTime.now().microsecondsSinceEpoch}$ext',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    return 'file:${file.path}';
  }

  /// 从数据本身认图片格式。
  ///
  /// 文生图服务给的是数据，不说它是什么格式——有的回 png，有的回 jpeg。
  /// 应用里显示图片是照字节解码、不看后缀的，但文件名不该写着一个连自己
  /// 都对不上的扩展名（哪天有人拿出去看，会莫名其妙）。
  static String extensionOf(Uint8List bytes) {
    if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) return '.jpg';
    if (bytes.length > 7 && bytes[0] == 0x89 && bytes[1] == 0x50) {
      return '.png';
    }
    return '.png';
  }

  /// 语音条的落盘位置（B8）。
  ///
  /// 合成引擎要的是一个"写到哪儿"，所以这里给位置而不是收数据。
  /// 目录与图片共用一处：对上层来说两者都只是 `file:` 引用，
  /// 哪天要清理本地素材，扫一个目录就够了。
  Future<File> newVoiceFile({String extension = '.wav'}) async {
    final mediaDir = await _mediaDir();
    final ext = extension.startsWith('.') ? extension : '.$extension';
    return File(
      p.join(mediaDir.path, 'voice_${DateTime.now().microsecondsSinceEpoch}$ext'),
    );
  }

  Future<Directory> _mediaDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, mediaDirName));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  File _newFile(Directory dir, String extension) => File(
    p.join(dir.path, 'img_${DateTime.now().microsecondsSinceEpoch}$extension'),
  );

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
