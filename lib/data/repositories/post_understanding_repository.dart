import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/post_understanding.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 帖子解析结果的读写。
class PostUnderstandingRepository {
  const PostUnderstandingRepository(this._db);

  final AppDatabase _db;

  Future<PostUnderstanding?> find(String postId) async {
    final row = await (_db.select(
      _db.postUnderstandings,
    )..where((t) => t.postId.equals(postId))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Future<void> upsert(PostUnderstanding understanding) async {
    await _db
        .into(_db.postUnderstandings)
        .insertOnConflictUpdate(
          PostUnderstandingsCompanion.insert(
            postId: understanding.postId,
            tone: Value(understanding.tone),
            domain: Value(understanding.domain),
            entities: Value(jsonEncode(understanding.entities)),
            point: Value(understanding.point),
            imageSummary: Value(understanding.imageSummary),
            jokeMechanism: Value(understanding.jokeMechanism),
            emotion: Value(understanding.emotion),
            insiderAngle: Value(understanding.insiderAngle),
            angles: Value(jsonEncode(understanding.angles)),
            needsWeb: Value(understanding.needsWeb),
            confidence: Value(understanding.confidence),
            model: Value(understanding.model),
            updatedAt: understanding.updatedAt.millisecondsSinceEpoch,
          ),
        );
  }

  /// 帖子被编辑/删除时置空，下一次发帖重新算。
  Future<int> deleteByPost(String postId) {
    return (_db.delete(
      _db.postUnderstandings,
    )..where((t) => t.postId.equals(postId))).go();
  }

  PostUnderstanding _toDomain(PostUnderstandingRow row) {
    final decoded = _entities(row.entities);
    return PostUnderstanding(
      angles: _entities(row.angles),
      postId: row.postId,
      tone: row.tone,
      domain: row.domain,
      entities: decoded,
      point: row.point,
      imageSummary: row.imageSummary,
      jokeMechanism: row.jokeMechanism,
      emotion: row.emotion,
      insiderAngle: row.insiderAngle,
      needsWeb: row.needsWeb,
      confidence: row.confidence,
      model: row.model,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
    );
  }

  static List<String> _entities(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
    } catch (_) {
      return const [];
    }
  }
}

final postUnderstandingRepositoryProvider =
    Provider<PostUnderstandingRepository>(
      (ref) => PostUnderstandingRepository(ref.watch(databaseProvider)),
    );
