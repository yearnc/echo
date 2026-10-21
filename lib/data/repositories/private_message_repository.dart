import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/private_message.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 私信（B5）。
///
/// **"还没到点"的消息也在表里**：住民回你那句话先写好、时间戳落在几分钟之后，
/// 读的时候按 `created_at <= 现在` 过滤，于是你会觉得"他过一会儿才回"。
/// 这比另开一张待发队列省事，也顺带解决了补发——进程被杀掉，那条消息照样
/// 躺在库里，下次打开就到了。
class PrivateMessageRepository {
  const PrivateMessageRepository(this._db);

  final AppDatabase _db;

  /// 会话列表：一个人一行，带最后一句和未读数。
  ///
  /// 一行一个子查询是有点重，但会话数量是"你聊过的人"，不是"消息数"，
  /// 几十行顶天了。
  Stream<List<Conversation>> watchConversations() {
    return _db
        .customSelect(
          _conversationsSql,
          readsFrom: {_db.privateMessages},
        )
        .watch()
        .map((rows) => rows.map(_toConversation).toList(growable: false));
  }

  /// 和某个人的全部往来（按时间正序，够聊天页从上往下铺）。
  ///
  /// **不在 SQL 里绑一个"建查询那一刻"的 now**：那样你刚发出去的消息
  /// 时间戳一定比它大，会被过滤掉，界面上就像"点了发送没反应"。
  /// 这里把过滤放到每次查询结果上，时间取的是**读出来的那一刻**；
  /// 还没到点的排期消息仍然不会提前出现。
  Stream<List<PrivateMessage>> watchThread(String personaId) {
    return (_db.select(_db.privateMessages)
          ..where(
            (t) => t.personaId.equals(personaId) & t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch()
        .map((rows) {
          final now = DateTime.now().millisecondsSinceEpoch;
          return [
            for (final row in rows)
              if (row.createdAt <= now) _toMessage(row),
          ];
        });
  }

  /// 还没读的私信有几条（底部导航上那个红点用它）。
  Stream<int> watchUnreadCount() {
    final count = _db.privateMessages.id.count();
    final query = _db.selectOnly(_db.privateMessages)
      ..addColumns([count])
      ..where(
        _db.privateMessages.direction.equals('in') &
            _db.privateMessages.readAt.isNull() &
            _db.privateMessages.deletedAt.isNull() &
            // 用 SQL 里的 now，而不是建查询时绑定的值：否则刚收到的那条
            // 永远落在“未来”，红点要等页面重建才出现。
            _db.privateMessages.createdAt.isSmallerOrEqual(
              CustomExpression<int>(
                "(CAST(strftime('%s', 'now') AS INTEGER) * 1000 + 999)",
              ),
            ),
      );

    return query.watchSingle().map((row) => row.read(count) ?? 0);
  }

  /// 我发出去一句。立刻就在表里（时间戳就是现在）。
  Future<void> send({
    required String personaId,
    required String content,
    String mediaType = 'text',
  }) async {
    await _db
        .into(_db.privateMessages)
        .insert(
          PrivateMessagesCompanion.insert(
            id: _newId(),
            personaId: personaId,
            direction: 'out',
            content: Value(content),
            mediaType: Value(mediaType),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  /// 排一条他发来的话。[at] 可以是将来的时刻——那时它才会出现在会话里。
  Future<void> scheduleIncoming({
    required String personaId,
    required String content,
    required DateTime at,
    String mediaType = 'text',
    String voicePath = '',
  }) async {
    await _db
        .into(_db.privateMessages)
        .insert(
          PrivateMessagesCompanion.insert(
            id: _newId(),
            personaId: personaId,
            direction: 'in',
            content: Value(content),
            mediaType: Value(mediaType),
            voicePath: Value(voicePath.isEmpty ? null : voicePath),
            createdAt: at.millisecondsSinceEpoch,
          ),
        );
  }

  /// 和某个人的最近几句，按时间正序（拼私信提示词用）。
  Future<List<PrivateMessage>> recentTurns(
    String personaId, {
    int limit = 6,
  }) async {
    final rows =
        await (_db.select(_db.privateMessages)
              ..where(
                (t) =>
                    t.personaId.equals(personaId) &
                    t.deletedAt.isNull() &
                    t.createdAt.isSmallerOrEqualValue(_now),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(limit))
            .get();
    return rows.reversed.map(_toMessage).toList(growable: false);
  }

  /// 把和某个人的会话标成已读（进聊天页时调）。
  Future<void> markThreadRead(String personaId) async {
    await (_db.update(_db.privateMessages)..where(
          (t) =>
              t.personaId.equals(personaId) &
              t.direction.equals('in') &
              t.readAt.isNull() &
              t.createdAt.isSmallerOrEqualValue(_now),
        ))
        .write(PrivateMessagesCompanion(readAt: Value(_now)));
  }

  /// 你和他之间最后一条消息的时刻（含还没到点的）。
  ///
  /// 调度要用它来判断"上一句还是我写的吗""他是不是刚说过话"——
  /// 这些判断必须看得见未来的那条，否则同一轮 tick 会给他排第二句。
  Future<DateTime?> lastAt(String personaId) async {
    final row =
        await (_db.select(_db.privateMessages)
              ..where(
                (t) => t.personaId.equals(personaId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.createdAt);
  }

  /// 你最后一句话之后，他还没有回过（调度用它决定"要不要接一句"）。
  ///
  /// 这里**故意不过滤时间**：已经排上、但还没到点的那条回应也算数——
  /// 否则每轮 tick 都会以为"他还没回"，一路给他排下去。
  Future<bool> hasUnansweredFromMe(String personaId) async {
    final rows =
        await (_db.select(_db.privateMessages)
              ..where(
                (t) => t.personaId.equals(personaId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(1))
            .get();
    if (rows.isEmpty) return false;
    return rows.first.direction == 'out';
  }

  /// 你说了话、他还欠着一句的人（B5 的调度用它决定该让谁回）。
  ///
  /// 同样**看得见未来的那条**：已经排上回应的人不该被排第二次。
  Future<List<String>> personaIdsAwaitingReply() async {
    final rows = await _db
        .customSelect(
          _awaitingSql,
          readsFrom: {_db.privateMessages},
        )
        .get();
    return rows.map((row) => row.read<String>('persona_id')).toList();
  }

  /// 会话里有没有过他发来的、你还没读的话。
  Future<bool> hasUnreadIncoming(String personaId) async {
    final count = _db.privateMessages.id.count();
    final query = _db.selectOnly(_db.privateMessages)
      ..addColumns([count])
      ..where(
        _db.privateMessages.personaId.equals(personaId) &
            _db.privateMessages.direction.equals('in') &
            _db.privateMessages.readAt.isNull() &
            _db.privateMessages.createdAt.isSmallerOrEqualValue(_now),
      );
    final row = await query.getSingle();
    return (row.read(count) ?? 0) > 0;
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;


  Conversation _toConversation(QueryRow row) => Conversation(
    personaId: row.read<String>('persona_id'),
    lastMessage: previewOf(
      row.read<String>('content'),
      row.read<String>('media_type'),
    ),
    lastAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('created_at')),
    unreadCount: row.read<int>('unread'),
    lastFromMe: row.read<String>('direction') == 'out',
  );

  PrivateMessage _toMessage(PrivateMessageRow row) => PrivateMessage(
    id: row.id,
    personaId: row.personaId,
    fromMe: row.direction == 'out',
    content: row.content,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    mediaType: row.mediaType,
    voicePath: row.voicePath ?? '',
    transcript: row.transcript ?? '',
    read: row.readAt != null,
  );

  /// 列表上那一行的预览文字：表情包和语音不能把路径铺出来。
  static String previewOf(String content, String mediaType) {
    return switch (mediaType) {
      'sticker' => '[表情包]',
      'voice' => '[语音]',
      'image' => '[图片]',
      _ => content,
    };
  }

  static final Random _rand = Random();

  /// 后缀必须真的随机：拿时间戳顶上会在同一毫秒里撞（PostRepository 踩过）。
  String _newId() =>
      'pm_${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 20)}';

  /// 最后一句是我说的那些人。
  static const String _awaitingSql = '''
SELECT DISTINCT m.persona_id AS persona_id
FROM private_messages m
WHERE m.deleted_at IS NULL
  AND m.direction = 'out'
  AND m.id = (
    SELECT l.id FROM private_messages l
    WHERE l.persona_id = m.persona_id
      AND l.deleted_at IS NULL
    ORDER BY l.created_at DESC
    LIMIT 1
  )
''';

  /// 会话列表：每个聊过的人取最后一条，顺带数一数没读的。
  ///
  /// 时间用 SQL 里的 `now` 而不是绑定参数：会话列表会一直挂着监听，
  /// 绑定一次 now 的话，之后新发的消息永远落在"未来"。
  /// 当前时间的毫秒值。`strftime('%s')` 只到秒，同一秒里刚发的消息会被
  /// 判成“未来”而消失；用 julian day 换成毫秒。
  static const String _conversationsNow =
      'CAST((julianday(\'now\') - 2440587.5) * 86400000 AS INTEGER)';

  static const String _conversationsSql = '''
SELECT
  m.persona_id AS persona_id,
  m.content AS content,
  m.media_type AS media_type,
  m.direction AS direction,
  m.created_at AS created_at,
  (
    SELECT COUNT(*) FROM private_messages u
    WHERE u.persona_id = m.persona_id
      AND u.direction = 'in'
      AND u.read_at IS NULL
      AND u.deleted_at IS NULL
      AND u.created_at <= $_conversationsNow
  ) AS unread
FROM private_messages m
WHERE m.deleted_at IS NULL
  AND m.created_at <= $_conversationsNow
  AND m.id = (
    SELECT l.id FROM private_messages l
    WHERE l.persona_id = m.persona_id
      AND l.deleted_at IS NULL
      AND l.created_at <= $_conversationsNow
    ORDER BY l.created_at DESC
    LIMIT 1
  )
ORDER BY m.created_at DESC
''';
}

final privateMessageRepositoryProvider = Provider<PrivateMessageRepository>(
  (ref) => PrivateMessageRepository(ref.watch(databaseProvider)),
);

/// 会话列表。
final conversationsProvider = StreamProvider<List<Conversation>>(
  (ref) => ref.watch(privateMessageRepositoryProvider).watchConversations(),
);

/// 和某一个人的往来。
final privateThreadProvider =
    StreamProvider.family<List<PrivateMessage>, String>(
      (ref, personaId) =>
          ref.watch(privateMessageRepositoryProvider).watchThread(personaId),
    );

/// 未读私信条数（底部导航的红点）。
final privateUnreadCountProvider = StreamProvider<int>(
  (ref) => ref.watch(privateMessageRepositoryProvider).watchUnreadCount(),
);
