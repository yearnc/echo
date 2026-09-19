import 'dart:math';

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

  /// 评论区：住民说的 + 我自己说的，合成一条时间线。
  ///
  /// 两个来源分表存是有道理的——住民那些要排期、要兑现、切清醒模式时会被取消，
  /// 而"我刚回了句什么"没有这些事。合并放在读取这一层，排序交给数据库。
  Stream<List<PostComment>> watchComments(String postId) {
    return _db
        .customSelect(
          _commentsSql,
          variables: [
            Variable<String>(postId),
            Variable<String>(typeComment),
            Variable<String>(statusDone),
            Variable<String>(postId),
          ],
          readsFrom: {_db.aiInteractions, _db.userComments},
        )
        .watch()
        .map((rows) => rows.map(_toComment).toList(growable: false));
  }

  /// 一条 UNION：上半是兑现了的住民评论，下半是我自己写的，合起来按时间排。
  static const String _commentsSql = '''
SELECT id, post_id, persona_id, content, media_type, voice_path, transcript,
       voice_duration_ms, parent_id, reply_to_name, like_count, at, is_ai
FROM (
  SELECT id, post_id, persona_id, content, media_type, voice_path, transcript,
         voice_duration_ms, parent_id, NULL AS reply_to_name, like_count,
         COALESCE(executed_at, scheduled_at) AS at, is_ai
  FROM ai_interactions
  WHERE post_id = ? AND type = ? AND status = ? AND deleted_at IS NULL
  UNION ALL
  SELECT id, post_id, NULL AS persona_id, content, 'text' AS media_type,
         NULL AS voice_path, NULL AS transcript, NULL AS voice_duration_ms,
         parent_id, reply_to_name, 0 AS like_count,
         created_at AS at, 0 AS is_ai
  FROM user_comments
  WHERE post_id = ? AND deleted_at IS NULL
)
ORDER BY at ASC
''';

  /// 给一条评论点赞 / 取消，返回点完之后的状态。
  ///
  /// 跟帖子的赞分开存：帖子是一条一颗心，评论有很多条。而且这里点的可能是
  /// 住民的评论、也可能是我自己的——两张不同的表，所以赞单独记账。
  Future<bool> toggleCommentLike(String commentId) async {
    final existing =
        await (_db.select(_db.commentLikes)
              ..where((t) => t.commentId.equals(commentId)))
            .getSingleOrNull();

    if (existing != null) {
      await (_db.delete(_db.commentLikes)
            ..where((t) => t.commentId.equals(commentId)))
          .go();
      return false;
    }

    await _db
        .into(_db.commentLikes)
        .insert(
          CommentLikesCompanion.insert(
            commentId: commentId,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    return true;
  }

  /// 我赞过的评论 id。评论列表靠着它点亮心形。
  Stream<Set<String>> watchLikedCommentIds() {
    return _db
        .select(_db.commentLikes)
        .watch()
        .map((rows) => rows.map((row) => row.commentId).toSet());
  }

  /// 我自己发一条评论；[parentId] 非空表示这是在回某一条。
  Future<void> addMyComment({
    required String postId,
    required String content,
    String? parentId,
    String? replyToName,
  }) async {
    await _db
        .into(_db.userComments)
        .insert(
          UserCommentsCompanion.insert(
            id: _newId('uc'),
            postId: postId,
            content: content,
            parentId: Value(parentId),
            replyToName: Value(replyToName),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    await _bumpCommentCount(postId);
  }

  /// 评论数 +1——帖子卡片上那个数字要跟着动。
  Future<void> _bumpCommentCount(String postId) async {
    final query = _db.select(_db.posts)..where((t) => t.id.equals(postId));
    final row = await query.getSingleOrNull();
    if (row == null) return;

    await (_db.update(_db.posts)..where((t) => t.id.equals(postId))).write(
      PostsCompanion(commentCount: Value(row.commentCount + 1)),
    );
  }

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 20)}';

  /// 同 PostRepository：这个后缀必须真的随机，拿时间戳顶上会在同一毫秒里撞。
  static final Random _rand = Random();

  /// 把规划器算出的排期写进队列（发帖时调用）。
  ///
  /// id 由「帖子 + 序号」拼成，所以**同一条帖子只排一次期**——
  /// 排期本来也是发帖那一刻算完就不再追加的。
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
    int? voiceDurationMs,
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
            voiceDurationMs: Value(voiceDurationMs),
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

  /// 还没兑现的评论排期，返回对应的住民 id。
  ///
  /// 模型写评论时需要知道"这是给谁写的"——同一条帖子下几个人的语气完全不同，
  /// 而且写之前得先知道是谁在说。
  Future<List<String>> pendingCommentPersonaIds(String postId) async {
    final query = _db.selectOnly(_db.aiInteractions)
      ..addColumns([_db.aiInteractions.personaId])
      ..where(
        _db.aiInteractions.postId.equals(postId) &
            _db.aiInteractions.type.equals(typeComment) &
            _db.aiInteractions.status.equals('pending'),
      );

    final rows = await query.get();
    return rows
        .map((row) => row.read(_db.aiInteractions.personaId))
        .whereType<String>()
        .toList(growable: false);
  }

  /// 把还没兑现的评论换成模型写的内容，返回改了几条。
  ///
  /// 已经兑现的**不动**：用户可能已经看到了，评论在眼皮底下变一次很怪。
  /// 所以这是"在内容送到之前把它换掉"，不是"编辑评论"。
  Future<int> updatePendingComments(
    String postId,
    Map<String, String> contentByPersona,
  ) async {
    if (contentByPersona.isEmpty) return 0;

    var updated = 0;
    for (final entry in contentByPersona.entries) {
      updated += await (_db.update(_db.aiInteractions)
            ..where(
              (t) =>
                  t.postId.equals(postId) &
                  t.personaId.equals(entry.key) &
                  t.type.equals(typeComment) &
                  t.status.equals('pending'),
            ))
          .write(AiInteractionsCompanion(content: Value(entry.value)));
    }
    return updated;
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

  PostComment _toComment(QueryRow row) {
    return PostComment(
      id: row.read<String>('id'),
      postId: row.read<String>('post_id'),
      personaId: row.readNullable<String>('persona_id'),
      content: row.readNullable<String>('content'),
      mediaType: _parseMedia(row.readNullable<String>('media_type')),
      voiceAsset: row.readNullable<String>('voice_path'),
      transcript: row.readNullable<String>('transcript'),
      voiceDurationMs: row.readNullable<int>('voice_duration_ms'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('at')),
      parentId: row.readNullable<String>('parent_id'),
      replyToName: row.readNullable<String>('reply_to_name'),
      likeCount: row.read<int>('like_count'),
      isAi: row.read<int>('is_ai') != 0,
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

/// 我赞过的评论 id（评论列表靠它点亮心形）。
final likedCommentIdsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(interactionRepositoryProvider).watchLikedCommentIds(),
);
