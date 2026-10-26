import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/resident_inbox.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 固定住民的收件箱。
///
/// 三种来源合成一份待办：别人在我帖子下的评论、别人回我的评论、私信。
/// 每次唤醒先 `sync` 再 `pending`，模型处理完由唤醒服务标 `handled`。
class ResidentInboxRepository {
  const ResidentInboxRepository(this._db);

  final AppDatabase _db;

  static const String kindCommentOnPost = 'comment_on_post';
  static const String kindReplyToComment = 'reply_to_comment';
  static const String kindDm = 'dm';

  /// 只看最近两周的动静。再往前的评论早就聊完了，第一次打开 APP
  /// 不该把半年前的评论全塞进收件箱。
  static int get _recentCutoffMs => DateTime.now()
      .subtract(const Duration(days: 14))
      .millisecondsSinceEpoch;

  /// 按现有数据补齐待办。用确定 id，重复调用不会写出第二条。
  Future<int> sync(String residentId) async {
    final rows = <ResidentInboxItemsCompanion>[];

    // 1. 我发的帖子下面，用户的新评论（顶层的）。
    final onPost = await _db.customSelect(
      '''
SELECT uc.id, uc.post_id, uc.content, uc.caption, uc.created_at
FROM user_comments uc
JOIN posts p ON p.id = uc.post_id
WHERE p.author_resident_id = ? AND p.deleted_at IS NULL
  AND uc.deleted_at IS NULL AND uc.parent_id IS NULL
  AND uc.created_at > ?
  AND NOT EXISTS (
    SELECT 1 FROM ai_interactions r
    WHERE r.post_id = uc.post_id AND r.parent_id = uc.id
      AND r.status = 'done' AND r.deleted_at IS NULL
  )
''',
      variables: [
        Variable<String>(residentId),
        Variable<int>(_recentCutoffMs),
      ],
      readsFrom: {_db.userComments, _db.posts, _db.aiInteractions},
    ).get();
    for (final row in onPost) {
      rows.add(
        _item(
          residentId: residentId,
          kind: kindCommentOnPost,
          refId: row.read<String>('id'),
          postId: row.read<String>('post_id'),
          summary: _summary(
            row.readNullable<String>('content'),
            row.readNullable<String>('caption'),
          ),
          at: row.read<int>('created_at'),
        ),
      );
    }

    // 2. 我的评论收到的用户回复：user_comments.parent_id 指向
    //    ai_interactions，而那条 AI 评论的 persona 属于这个住民。
    final replies = await _db.customSelect(
      '''
SELECT uc.id, uc.post_id, uc.content, uc.caption, uc.created_at
FROM user_comments uc
JOIN ai_interactions ai ON ai.id = uc.parent_id
JOIN post_voices pv ON pv.id = ai.persona_id
WHERE pv.resident_id = ? AND uc.deleted_at IS NULL
  AND ai.deleted_at IS NULL AND ai.status = 'done'
  AND uc.created_at > ?
  AND NOT EXISTS (
    SELECT 1 FROM ai_interactions r
    WHERE r.post_id = uc.post_id AND r.parent_id = uc.id
      AND r.status = 'done' AND r.deleted_at IS NULL
  )
''',
      variables: [
        Variable<String>(residentId),
        Variable<int>(_recentCutoffMs),
      ],
      readsFrom: {
        _db.userComments,
        _db.aiInteractions,
        _db.postVoices,
      },
    ).get();
    for (final row in replies) {
      rows.add(
        _item(
          residentId: residentId,
          kind: kindReplyToComment,
          refId: row.read<String>('id'),
          postId: row.read<String>('post_id'),
          summary: _summary(
            row.readNullable<String>('content'),
            row.readNullable<String>('caption'),
          ),
          at: row.read<int>('created_at'),
        ),
      );
    }

    // 3. 私信：用户说的话，如果住民还没接，就是待办。
    //
    // direction 的口径：out = 我（用户）发出去的，in = 住民发来的。
    // 之前这里写反了，导致“用户发消息”永远进不了收件箱。
    //
    // 两个细节：
    // - **只把已经到点的“in”当成已回复**。住民的回话是排到几秒之后的，
    //   如果拿它当“已经回复了”，用户在等待窗口里再补一句就永远等不到回应。
    // - 一次取最近几条（最多 6 条），用户连发两三句时模型能看到完整意思，
    //   而不是只看到最后半句。
    final now = DateTime.now().millisecondsSinceEpoch;
    final dmRows = await _db.customSelect(
      '''
SELECT pm.id, pm.content, pm.media_type, pm.caption, pm.created_at
FROM private_messages pm
WHERE pm.persona_id = ? AND pm.direction = 'out' AND pm.deleted_at IS NULL
  AND pm.created_at > COALESCE((
    SELECT MAX(reply.created_at) FROM private_messages reply
    WHERE reply.persona_id = pm.persona_id AND reply.direction = 'in'
      AND reply.deleted_at IS NULL AND reply.created_at <= ?
  ), 0)
ORDER BY pm.created_at DESC
LIMIT 6
''',
      variables: [
        Variable<String>(residentId),
        Variable<int>(now),
      ],
      readsFrom: {_db.privateMessages},
    ).get();
    for (final dm in dmRows.toList().reversed) {
      final media = dm.readNullable<String>('media_type') ?? 'text';
      final caption = dm.readNullable<String>('caption') ?? '';
      final label = media == 'sticker' ? '表情包' : '图片';
      rows.add(
        _item(
          residentId: residentId,
          kind: kindDm,
          refId: dm.read<String>('id'),
          summary: media == 'text'
              ? (dm.readNullable<String>('content') ?? '')
              : (caption.isEmpty
                    ? '[发来一张$label]'
                    : '[发来一张$label：$caption]'),
          at: dm.read<int>('created_at'),
        ),
      );
    }

    if (rows.isEmpty) return 0;
    await _db.batch(
      (batch) => batch.insertAll(
        _db.residentInboxItems,
        rows,
        mode: InsertMode.insertOrIgnore,
      ),
    );
    return rows.length;
  }

  /// 还没处理的待办，按时间从早到晚——真人也是先翻旧的。
  Future<List<ResidentInboxItem>> pending(String residentId) async {
    final query = _db.select(_db.residentInboxItems)
      ..where((t) => t.residentId.equals(residentId) & t.handledAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    final rows = await query.get();
    return rows.map(_toDomain).toList(growable: false);
  }

  Future<void> markHandled(
    Iterable<String> ids, {
    required String decision,
    String? wakeId,
  }) async {
    final list = ids.toList(growable: false);
    if (list.isEmpty) return;
    await (_db.update(_db.residentInboxItems)
          ..where((t) => t.id.isIn(list)))
        .write(
          ResidentInboxItemsCompanion(
            handledAt: Value(DateTime.now().millisecondsSinceEpoch),
            decision: Value(decision),
            wakeId: Value(wakeId),
          ),
        );
  }

  Future<void> markAllHandled(
    String residentId, {
    required String decision,
    String? wakeId,
  }) async {
    await (_db.update(_db.residentInboxItems)
          ..where(
            (t) => t.residentId.equals(residentId) & t.handledAt.isNull(),
          ))
        .write(
          ResidentInboxItemsCompanion(
            handledAt: Value(DateTime.now().millisecondsSinceEpoch),
            decision: Value(decision),
            wakeId: Value(wakeId),
          ),
        );
  }

  ResidentInboxItemsCompanion _item({
    required String residentId,
    required String kind,
    required String refId,
    required String summary,
    required int at,
    String? postId,
  }) {
    return ResidentInboxItemsCompanion.insert(
      id: 'ib_${kind}_$refId',
      residentId: residentId,
      kind: kind,
      refId: refId,
      postId: Value(postId),
      summary: Value(summary),
      createdAt: at,
    );
  }

  static String _summary(String? content, String? caption) {
    final text = [caption ?? '', content ?? '']
        .where((part) => part.trim().isNotEmpty)
        .join('｜');
    if (text.length <= 200) return text;
    return text.substring(0, 200);
  }

  ResidentInboxItem _toDomain(ResidentInboxRow row) => ResidentInboxItem(
    id: row.id,
    residentId: row.residentId,
    kind: row.kind,
    refId: row.refId,
    postId: row.postId,
    summary: row.summary,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
  );
}

final residentInboxRepositoryProvider = Provider<ResidentInboxRepository>(
  (ref) => ResidentInboxRepository(ref.watch(databaseProvider)),
);
