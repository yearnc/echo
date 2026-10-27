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

  /// 正在生效的记忆（记忆页用）。按更新时间倒序，最近说过的在最上面。
  Stream<List<ResidentMemory>> watchActive(String residentId) {
    final query = _db.select(_db.residentMemories)
      ..where(
        (t) =>
            t.residentId.equals(residentId) &
            t.archivedAt.isNull() &
            t.deletedAt.isNull(),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  /// 已归档的记忆：还留着，只是不再注入提示词。
  Stream<List<ResidentMemory>> watchArchived(String residentId) {
    final query = _db.select(_db.residentMemories)
      ..where(
        (t) =>
            t.residentId.equals(residentId) &
            t.archivedAt.isNotNull() &
            t.deletedAt.isNull(),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.archivedAt)]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  /// 用户手动改一条记忆。只改摘要、正文和标签——
  /// 来源与时间属于"这件事什么时候发生的"，不该被编辑。
  Future<int> updateText({
    required String id,
    required String summary,
    required String content,
    required List<String> tags,
  }) {
    return (_db.update(
      _db.residentMemories,
    )..where((t) => t.id.equals(id))).write(
      ResidentMemoriesCompanion(
        summary: Value(summary),
        content: Value(content),
        tags: Value(tags.join(',')),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 把归档的放回生效列表。
  Future<int> restore(String id) {
    return (_db.update(_db.residentMemories)..where((t) => t.id.equals(id)))
        .write(ResidentMemoriesCompanion(archivedAt: const Value<int?>(null)));
  }

  Future<List<ResidentMemory>> recent(
    String residentId, {
    int limit = 5,
  }) async {
    final rows =
        await (_db.select(_db.residentMemories)
              ..where(
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
  ///
  /// 中文没有空格：直接把“上次考试的事”当整串去 contains 是查不到的。
  /// 这里把每个空格/标点隔开的片段拆成 2—3 字滑窗，**片段之间仍是“都要命中”，
  /// 片段内部只要任意一个滑窗命中就算**——中文长句能查，多个关键词也仍然能
  /// 同时约束（“天空 晚霞”两个都要在）。
  Future<List<ResidentMemory>> search(
    String residentId,
    String query, {
    int limit = 5,
  }) async {
    final groups = termGroups(query);
    if (groups.isEmpty) return recent(residentId, limit: limit);

    final rows =
        await (_db.select(_db.residentMemories)
              ..where(
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
        if (_matches(row, groups)) _toDomain(row),
    ].take(limit).toList(growable: false);
  }

  /// 把查询拆成“关键词组”：组间 AND，组内 OR。
  static List<List<String>> termGroups(String query) {
    final groups = <List<String>>[];
    for (final part in query.toLowerCase().split(
      RegExp(r'[\s，。！？、；：,.!?;:（）()\[\]【】「」]+'),
    )) {
      final text = part.trim();
      if (text.isEmpty) continue;

      final terms = <String>{};
      if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) {
        final chars = text.runes.map(String.fromCharCode).toList();
        for (final size in const [2, 3]) {
          if (chars.length < size) continue;
          for (var i = 0; i + size <= chars.length; i++) {
            final term = chars.sublist(i, i + size).join();
            if (_stopWords.contains(term)) continue;
            terms.add(term);
            if (terms.length >= 60) break;
          }
          if (terms.length >= 60) break;
        }
        // “猫”“晚霞”这种一两个字的查询：滑窗生成不出来，原样用。
        if (terms.isEmpty && !_stopWords.contains(text)) terms.add(text);
      } else if (text.length >= 2 && !_stopWords.contains(text)) {
        terms.add(text);
      }

      if (terms.isNotEmpty) {
        groups.add(terms.toList(growable: false));
      }
    }
    return groups;
  }

  bool _matches(ResidentMemoryRow row, List<List<String>> groups) {
    final haystack = '${row.summary}\n${row.content}\n${row.tags}'
        .toLowerCase();
    for (final group in groups) {
      if (!group.any(haystack.contains)) return false;
    }
    return true;
  }

  /// “的/了/我的/什么”这类词拆出来只会匹配到所有记忆，直接丢掉。
  static const Set<String> _stopWords = {
    '的',
    '了',
    '是',
    '吗',
    '呢',
    '啊',
    '呀',
    '吧',
    '我',
    '你',
    '他',
    '她',
    '它',
    '们',
    '这',
    '那',
    '和',
    '与',
    '在',
    '有',
    '个',
    '一',
    '不',
    '就',
    '都',
    '也',
    '还',
    '很',
    '要',
    '把',
    '被',
    '给',
    '对',
    '从',
    '到',
    '我的',
    '你的',
    '他的',
    '她的',
    '这个',
    '那个',
    '一下',
    '什么',
    '怎么',
    '可以',
    '没有',
    '我们',
    '你们',
    '他们',
    '她们',
  };

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

  /// 按 id 找一条还在生效的记忆。
  Future<ResidentMemory?> findActive(String id) async {
    final row =
        await (_db.select(_db.residentMemories)..where(
              (t) =>
                  t.id.equals(id) &
                  t.archivedAt.isNull() &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
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
        await (_db.select(_db.residentMemories)
              ..where(
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

/// 某个固定住民正在生效的记忆。
final activeMemoriesProvider = StreamProvider.autoDispose
    .family<List<ResidentMemory>, String>(
      (ref, residentId) =>
          ref.watch(residentMemoryRepositoryProvider).watchActive(residentId),
    );

/// 某个固定住民已归档的记忆。
final archivedMemoriesProvider = StreamProvider.autoDispose
    .family<List<ResidentMemory>, String>(
      (ref, residentId) =>
          ref.watch(residentMemoryRepositoryProvider).watchArchived(residentId),
    );
