import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/sticker.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';
import '../media/media_service.dart';
import '../seed/builtin_stickers.dart';

/// 素材（头像 / 表情包）的读写（规划书 §11）。
///
/// 内置素材始终以 `assets/stickers.json` 为准、不落库；只有用户导入的才写表。
/// 这样"删掉内置素材"这件事从根上不存在——不需要为它维护软删除状态。
class StickerRepository {
  const StickerRepository(this._db, this._media);

  final AppDatabase _db;
  final MediaService _media;

  static final Random _rand = Random();

  /// 用户导入的素材，新的在前。
  Stream<List<StickerItem>> watchUserStickers() {
    final query = _db.select(_db.stickers)
      ..where((t) => t.deletedAt.isNull() & t.isUser.equals(true))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query
        .watch()
        .map((rows) => rows.map(_toItem).toList(growable: false));
  }

  /// 从相册导一张。用户取消时返回 null。
  ///
  /// 图片先落进 APP 私有目录再入库（`MediaService` 负责）——
  /// 相册里的原图被删掉后，素材不该跟着消失。
  Future<String?> importFromGallery({
    required String name,
    String category = StickerCategory.customId,
  }) async {
    final ref = await _media.pickFromGallery();
    if (ref == null) return null;

    final id = 'sticker_${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 20)}';
    await _db
        .into(_db.stickers)
        .insert(
          StickersCompanion.insert(
            id: id,
            name: name.trim().isEmpty ? '我导入的' : name.trim(),
            category: category,
            source: const Value('file'),
            path: ref,
            isUser: const Value(true),
            createdAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
    return id;
  }

  Future<int> countUserStickers() async {
    final count = _db.stickers.id.count();
    final query = _db.selectOnly(_db.stickers)
      ..addColumns([count])
      ..where(_db.stickers.deletedAt.isNull() & _db.stickers.isUser.equals(true));
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// 软删除 + 清磁盘。内置素材不走这里（它们根本不在表里）。
  Future<void> deleteUserSticker(String id) async {
    final query = _db.select(_db.stickers)..where((t) => t.id.equals(id));
    final row = await query.getSingleOrNull();
    if (row == null) return;

    await (_db.update(_db.stickers)..where((t) => t.id.equals(id))).write(
      StickersCompanion(
        deletedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    await _media.deleteByRef(row.path);
  }

  StickerItem _toItem(StickerRow row) => StickerItem(
    id: row.id,
    name: row.name,
    category: row.category,
    path: row.path,
    isUser: row.isUser,
    isBuiltin: row.isBuiltin,
  );
}

final stickerRepositoryProvider = Provider<StickerRepository>(
  (ref) => StickerRepository(
    ref.watch(databaseProvider),
    ref.watch(mediaServiceProvider),
  ),
);

/// 用户导入的素材（管理页与头像选择共用）。
final userStickersProvider = StreamProvider<List<StickerItem>>(
  (ref) => ref.watch(stickerRepositoryProvider).watchUserStickers(),
);

/// 整套素材：内置（assets）+ 用户导入（数据库）。
final stickerLibraryProvider = FutureProvider.autoDispose<StickerLibrary>((
  ref,
) async {
  final builtin = await BuiltinStickers.load();
  final user = await ref.watch(userStickersProvider.future);

  return StickerLibrary(
    categories: builtin.categories,
    stickers: [...builtin.stickers, ...user],
  );
});
