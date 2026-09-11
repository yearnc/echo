import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/pending_interaction.dart';
import '../../domain/models/post.dart';
import '../../domain/services/interaction_planner.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// AI 互动的读取。
///
/// 这里是「队列」与「展示」的分界：
/// - `status = pending` 的记录是还没到点的排期（M3 的调度器负责推进）
/// - `status = done` 的才进评论区
/// 所以页面永远只读 done，不会提前剧透。
class InteractionRepository {
  const InteractionRepository(this._db);

  final AppDatabase _db;

  static const String typeComment = 'comment';
  static const String typeLike = 'like';
  static const String statusDone = 'done';

  Stream<List<PostComment>> watchComments(String postId) {
    final query = _db.select(_db.aiInteractions)
      ..where((t) =>
          t.postId.equals(postId) &
          t.type.equals(typeComment) &
          t.status.equals(statusDone) &
          t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.executedAt)]);

    return query.watch().map(
          (rows) => rows.map(_toComment).toList(growable: false),
        );
  }

  /// 把规划器算出的排期写进队列（发帖时调用）。
  Future<void> insertPlanned(
    String postId,
    List<PlannedInteraction> planned,
  ) async {
    if (planned.isEmpty) return;

    final rows = <AiInteractionsCompanion>[];
    for (var i = 0; i < planned.length; i++) {
      final item = planned[i];
      rows.add(
        AiInteractionsCompanion(
          id: Value('sched_${postId}_$i'),
          postId: Value(postId),
          personaId: Value(item.personaId),
          type: Value(item.type),
          mediaType: Value(item.mediaType),
          content: Value(item.content),
          scheduledAt: Value(item.scheduledAt.millisecondsSinceEpoch),
          status: const Value('pending'),
          likeCount: Value(item.likeBatch),
        ),
      );
    }

    await _db.batch((batch) => batch.insertAll(_db.aiInteractions, rows));
  }

  /// 到点该兑现的排期（冷启动 / 回前台时扫一次）。
  Future<List<PendingInteraction>> duePending(DateTime now) async {
    final query = _db.select(_db.aiInteractions)
      ..where((t) =>
          t.status.equals('pending') &
          t.scheduledAt.isSmallerOrEqualValue(now.millisecondsSinceEpoch))
      ..orderBy([(t) => OrderingTerm.asc(t.scheduledAt)]);

    final rows = await query.get();
    return rows.map(_toPending).toList(growable: false);
  }

  /// 最近已经兑现的互动（信息流补发后给 UI 用）。
  Future<int> countPending() async {
    final count = _db.aiInteractions.id.count();
    final query = _db.selectOnly(_db.aiInteractions)
      ..addColumns([count])
      ..where(_db.aiInteractions.status.equals('pending'));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  PendingInteraction _toPending(AiInteractionRow row) => PendingInteraction(
        id: row.id,
        postId: row.postId,
        personaId: row.personaId,
        type: row.type,
        content: row.content,
        mediaType: row.mediaType,
        voiceDurationMs: row.voiceDurationMs,
        likeBatch: row.likeCount,
      );

  Future<void> markExecuted(String id, {int? likeCount}) async {
    await (_db.update(_db.aiInteractions)..where((t) => t.id.equals(id))).write(
      AiInteractionsCompanion(
        status: const Value(statusDone),
        executedAt: Value(DateTime.now().millisecondsSinceEpoch),
        likeCount: likeCount == null ? const Value.absent() : Value(likeCount),
      ),
    );
  }

  PostComment _toComment(AiInteractionRow row) {
    return PostComment(
      id: row.id,
      postId: row.postId,
      personaId: row.personaId,
      content: row.content,
      mediaType: _parseMedia(row.mediaType),
      voiceAsset: row.voicePath,
      transcript: row.transcript,
      voiceDurationMs: row.voiceDurationMs,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.executedAt ?? row.scheduledAt,
      ),
      parentId: row.parentId,
      likeCount: row.likeCount,
      isAi: row.isAi,
    );
  }

  CommentMedia _parseMedia(String? raw) => switch (raw) {
        'voice' => CommentMedia.voice,
        'image' => CommentMedia.image,
        'emoji' => CommentMedia.emoji,
        _ => CommentMedia.text,
      };
}

final interactionRepositoryProvider = Provider<InteractionRepository>(
  (ref) => InteractionRepository(ref.watch(databaseProvider)),
);

final commentsProvider =
    StreamProvider.autoDispose.family<List<PostComment>, String>(
  (ref, postId) => ref.watch(interactionRepositoryProvider).watchComments(postId),
);
