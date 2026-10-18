import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/resident_memory.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 固定住民的长期记忆。
class ResidentMemoryRepository {
  const ResidentMemoryRepository(this._db);

  final AppDatabase _db;

  /// 写一条记忆；[limit] 非空时顺手把最旧的归档出去。
  Future<void> add(ResidentMemory memory, {int? limit}) async {
    await _db
        .into(_db.residentMemories)
        .insert(
          ResidentMemoriesCompanion.insert(
            id: memory.id,
            residentId: memory.residentId,
            source: Value(memory.source),
            sourceId: Value(memory.sourceId),
            summary: Value(memory.summary),
            content: Value(memory.content),
            tags: Value(memory.tags.join(',')),
            createdAt: memory.createdAt.millisecondsSinceEpoch,
            updatedAt: memory.updatedAt.millisecondsSinceEpoch,
          ),
        );
    if (limit != null) await archiveOverflow(memory.residentId, limit);
  }

  Future<List<ResidentMemory>> recent(
    String residentId, {
    int limit = 5,
  }) async {
    final rows =
        await (_db.select(_db.residentMemories)..where(
              (t) =>
                  t.residentId.equals(residentId) &
                  t.archivedAt.isNull() &
                  t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
            ..limit(limit))
            .get();
    return rows.map(_toDomain).toList(growable: false);
  }

  /// 关键词检索：在最近 300 条里做包含匹配。
  ///
  /// 记忆量本来就有上限（默认 400），先拉出来在 Dart 里过滤，
  /// 比在 SQL 里拼一串 LIKE 更好读，也不会把用户输入当 SQL 用。
  Future<List<ResidentMemory>> search(
    String residentId,
    String query, {
    int limit = 5,
  }) async {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.trim().isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) return recent(residentId, limit: limit);

    final rows =
        await (_db.select(_db.residentMemories)..where(
              (t) =>
                  t.residentId.equals(residentId) &
                  t.archivedAt.isNull() &
                  t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
            ..limit(300))
            .get();

    return [
      for (final row in rows)
        if (_matches(row, terms)) _toDomain(row),
    ].take(limit).toList(growable: false);
  }

  bool _matches(ResidentMemoryRow row, List<String> terms) {
    final haystack =
        '${row.summary}\n${row.content}\n${row.tags}'.toLowerCase();
    return terms.every(haystack.contains);
  }

  /// 同一个来源（帖子/评论/私信）是否已经记过，避免重复写。
  Future<bool> hasSource({
    required String residentId,
    required String sourceId,
  }) async {
    final row =
        await (_db.select(_db.residentMemories)..where(
              (t) =>
                  t.residentId.equals(residentId) &
                  t.sourceId.equals(sourceId) &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    return row != null;
  }

  Future<int> count(String residentId) async {
    final count = _db.residentMemories.id.count();
    final query = _db.selectOnly(_db.residentMemories)
      ..addColumns([count])
      ..where(
        _db.residentMemories.residentId.equals(residentId) &
            _db.residentMemories.archivedAt.isNull() &
            _db.residentMemories.deletedAt.isNull(),
      );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// 超过上限时把最旧的归档，不删除原文。
  Future<int> archiveOverflow(String residentId, int limit) async {
    final active = await count(residentId);
    final overflow = active - limit;
    if (overflow <= 0) return 0;

    final rows =
        await (_db.select(_db.residentMemories)..where(
              (t) =>
                  t.residentId.equals(residentId) &
                  t.archivedAt.isNull() &
                  t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)])
            ..limit(overflow))
            .get();

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final row in rows) {
      await (_db.update(_db.residentMemories)
            ..where((t) => t.id.equals(row.id)))
          .write(ResidentMemoriesCompanion(archivedAt: Value(now)));
    }
    return rows.length;
  }

  Future<int> archive(String id) {
    return (_db.update(
      _db.residentMemories,
    )..where((t) => t.id.equals(id))).write(
      ResidentMemoriesCompanion(
        archivedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 删除一条记忆：只停止注入，不删除私信/评论原文。
  Future<int> softDelete(String id) {
    return (_db.update(
      _db.residentMemories,
    )..where((t) => t.id.equals(id))).write(
      ResidentMemoriesCompanion(
        deletedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  static String newId() => 'mem_${DateTime.now().microsecondsSinceEpoch}';

  ResidentMemory _toDomain(ResidentMemoryRow row) => ResidentMemory(
    id: row.id,
    residentId: row.residentId,
    source: row.source,
    sourceId: row.sourceId,
    summary: row.summary,
    content: row.content,
    tags: row.tags.isEmpty
        ? const []
        : row.tags.split(',').where((tag) => tag.isNotEmpty).toList(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
    archivedAt: row.archivedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.archivedAt!),
  );
}

final residentMemoryRepositoryProvider = Provider<ResidentMemoryRepository>(
  (ref) => ResidentMemoryRepository(ref.watch(databaseProvider)),
);
