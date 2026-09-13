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
      ..where(
        (t) =>
            t.postId.equals(postId) &
            t.type.equals(typeComment) &
            t.status.equals(statusDone) &
            t.deletedAt.isNull(),
      )
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

  /// 策划事件兑现的评论：它在脚本时间轴上是"已经发生"的，
  /// 所以直接以 done 状态落库，评论区立刻就能读到。
  Future<void> insertExecutedComment({
    required String id,
    required String postId,
    required String personaId,
    String? mediaType,
    String? content,
    String? voicePath,
    String? transcript,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.aiInteractions)
        .insert(
          AiInteractionsCompanion.insert(
            id: id,
            postId: postId,
            personaId: personaId,
            type: typeComment,
            mediaType: Value(mediaType ?? 'text'),
            content: Value(content),
            voicePath: Value(voicePath),
            transcript: Value(transcript),
            scheduledAt: now,
            executedAt: Value(now),
            status: const Value(statusDone),
          ),
        );
  }

  /// 到点该兑现的排期（冷启动 / 回前台时扫一次）。
  Future<List<PendingInteraction>> duePending(DateTime now) async {
    final query = _db.select(_db.aiInteractions)
      ..where(
        (t) =>
            t.status.equals('pending') &
            t.scheduledAt.isSmallerOrEqualValue(now.millisecondsSinceEpoch),
      )
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

  /// 取消所有还没兑现的排期。
  ///
  /// 切到清醒模式时调用：用户已经说了不要虚拟反馈，队列里那些"将来会来的
  /// 点赞和评论"就必须停下来——这是"停止所有待发 AI 互动队列"的字面意思。
  Future<int> cancelAllPending() async {
    return (_db.update(_db.aiInteractions)
          ..where((t) => t.status.equals('pending')))
        .write(const AiInteractionsCompanion(status: Value('cancelled')));
  }

  /// 把已经兑现的 AI 互动归档（默认不参与清醒模式的统计）。
  Future<int> archiveExecuted() async {
    return (_db.update(_db.aiInteractions)
          ..where((t) => t.status.equals(statusDone) & t.scope.equals('echo')))
        .write(const AiInteractionsCompanion(scope: Value('archived')));
  }

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

final commentsProvider = StreamProvider.autoDispose
    .family<List<PostComment>, String>(
      (ref, postId) =>
          ref.watch(interactionRepositoryProvider).watchComments(postId),
    );
