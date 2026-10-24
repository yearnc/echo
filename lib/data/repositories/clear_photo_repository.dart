import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media/media_service.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 真实生活相册（v31）。
///
/// 照片只存在 `scope=clear` 的相册表里；回响侧任何查询都不碰这张表。
/// 删除是**硬删除 + 删磁盘**：用户说“删掉这张照片”就是不要它了，
/// 留一份在私有目录里反而违背承诺。
class ClearPhotoRepository {
  const ClearPhotoRepository(this._db, this._media);

  final AppDatabase _db;
  final MediaService _media;

  static final Random _rand = Random();

  Stream<List<ClearPhotoRow>> watchAll() {
    final query = _db.select(_db.clearPhotos)
      ..where((t) => t.deletedAt.isNull() & t.scope.equals('clear'))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  Future<List<ClearPhotoRow>> all() async {
    final query = _db.select(_db.clearPhotos)
      ..where((t) => t.deletedAt.isNull() & t.scope.equals('clear'))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.get();
  }

  /// 选一张照片入库。用户取消选图时返回 null。
  Future<ClearPhotoRow?> addFromGallery({String caption = ''}) async {
    final path = await _media.pickFromGallery();
    if (path == null) return null;
    return add(path: path, caption: caption);
  }

  Future<ClearPhotoRow> add({required String path, String caption = ''}) async {
    final row = ClearPhotoRow(
      id: 'photo_${DateTime.now().microsecondsSinceEpoch}_'
          '${_rand.nextInt(1 << 20)}',
      path: path,
      caption: caption.trim(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      scope: 'clear',
    );
    await _db
        .into(_db.clearPhotos)
        .insert(
          ClearPhotosCompanion.insert(
            id: row.id,
            path: row.path,
            caption: Value(row.caption),
            createdAt: row.createdAt,
          ),
        );
    return row;
  }

  Future<void> updateCaption(String id, String caption) async {
    await (_db.update(_db.clearPhotos)..where((t) => t.id.equals(id))).write(
      ClearPhotosCompanion(caption: Value(caption.trim())),
    );
  }

  Future<void> delete(ClearPhotoRow row) async {
    await (_db.delete(_db.clearPhotos)..where((t) => t.id.equals(row.id)))
        .go();
    await _media.deleteByRef(row.path);
  }

  /// 清空相册（数据导出/删除用）：连同磁盘文件一起删。
  Future<int> deleteAll() async {
    final rows = await all();
    for (final row in rows) {
      await _media.deleteByRef(row.path);
    }
    return _db.delete(_db.clearPhotos).go();
  }
}

final clearPhotoRepositoryProvider = Provider<ClearPhotoRepository>(
  (ref) => ClearPhotoRepository(
    ref.watch(databaseProvider),
    ref.watch(mediaServiceProvider),
  ),
);

final clearPhotosProvider = StreamProvider<List<ClearPhotoRow>>(
  (ref) => ref.watch(clearPhotoRepositoryProvider).watchAll(),
);
