import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 用户导入的一张“网友头像”。
class CustomAvatar {
  const CustomAvatar({
    required this.id,
    required this.path,
    required this.createdAt,
  });

  final String id;

  /// `file:` 引用，与头像组件、表情包共用同一套写法。
  final String path;
  final DateTime createdAt;
}

/// 网友头像池。
///
/// 临时网民的头像以前只能从内置 32 张里挑；用户传了图之后优先用这些，
/// 池子空了再回落到内置素材。删除是软删除，正在使用的旧帖子不受影响。
class CustomAvatarRepository {
  const CustomAvatarRepository(this._db);

  final AppDatabase _db;

  Stream<List<CustomAvatar>> watchAll() {
    final query = _db.select(_db.customAvatars)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  Future<List<CustomAvatar>> all() async {
    final query = _db.select(_db.customAvatars)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    final rows = await query.get();
    return rows.map(_toDomain).toList(growable: false);
  }

  Future<CustomAvatar> add(String path) async {
    final now = DateTime.now();
    final id = 'avatar_${now.microsecondsSinceEpoch}';
    await _db
        .into(_db.customAvatars)
        .insert(
          CustomAvatarsCompanion.insert(
            id: id,
            path: path,
            createdAt: now.millisecondsSinceEpoch,
          ),
        );
    return CustomAvatar(id: id, path: path, createdAt: now);
  }

  Future<void> remove(String id) async {
    await (_db.update(_db.customAvatars)..where((t) => t.id.equals(id))).write(
      CustomAvatarsCompanion(
        deletedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  CustomAvatar _toDomain(CustomAvatarRow row) => CustomAvatar(
    id: row.id,
    path: row.path,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
  );
}

final customAvatarRepositoryProvider = Provider<CustomAvatarRepository>(
  (ref) => CustomAvatarRepository(ref.watch(databaseProvider)),
);

final customAvatarsProvider = StreamProvider<List<CustomAvatar>>(
  (ref) => ref.watch(customAvatarRepositoryProvider).watchAll(),
);
