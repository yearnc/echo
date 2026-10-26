import 'dart:async';
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
    return _dueStream(
      load: () async {
        final rows = await _db
            .customSelect(
              _conversationsSql,
              readsFrom: {_db.privateMessages},
            )
            .get();
        return rows.map(_toConversation).toList(growable: false);
      },
      nextDueMs: () => _nextFutureAt(),
    );
  }

  /// 和某个人的全部往来（按时间正序，够聊天页从上往下铺）。
  ///
  /// **不在 SQL 里绑一个"建查询那一刻"的 now**：那样你刚发出去的消息
  /// 时间戳一定比它大，会被过滤掉，界面上就像"点了发送没反应"。
  /// 过滤放在每次读取时，还没到点的排期消息不会提前出现。
  ///
  /// 更关键的是 [nextDueMs]：下一条排期消息到点时，这个流会自己重新
  /// 发射一次。以前只靠数据库变更触发，排期消息躺在库里但还没到点，
  /// 就要等页面轮询或退出重进才会一次蹦出来。
  Stream<List<PrivateMessage>> watchThread(String personaId) {
    return _dueStream(
      load: () async {
        final rows =
            await (_db.select(_db.privateMessages)..where(
                  (t) => t.personaId.equals(personaId) & t.deletedAt.isNull(),
                )
                ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
                .get();
        final now = DateTime.now().millisecondsSinceEpoch;
        return [
          for (final row in rows)
            if (row.createdAt <= now) _toMessage(row),
        ];
      },
      nextDueMs: () => _nextFutureAt(personaId: personaId),
    );
  }

  /// 还没读的私信有几条（底部导航上那个红点用它）。
  Stream<int> watchUnreadCount() {
    return _dueStream(
      load: () async {
        final count = _db.privateMessages.id.count();
        final query = _db.selectOnly(_db.privateMessages)
          ..addColumns([count])
          ..where(
            _db.privateMessages.direction.equals('in') &
                _db.privateMessages.readAt.isNull() &
                _db.privateMessages.deletedAt.isNull() &
                _db.privateMessages.createdAt.isSmallerOrEqualValue(_now),
          );
        final row = await query.getSingle();
        return row.read(count) ?? 0;
      },
      nextDueMs: () => _nextFutureAt(incomingOnly: true),
    );
  }

  /// 排期消息到点就重新发一次；平时只听数据库变更。
  ///
  /// 这是私信“像微信一样自己冒出来”的关键：排期消息写进库时
  /// `created_at` 在未来，数据库不会因为它“到点”而变更，
  /// 所以必须按最近的未来时刻自己设一个定时器。
  Stream<T> _dueStream<T>({
    required Future<T> Function() load,
    required Future<int?> Function() nextDueMs,
  }) {
    late StreamController<T> controller;
    StreamSubscription<void>? changes;
    Timer? timer;
    var closed = false;
    var emitting = false;
    var pendingEmit = false;

    late Future<void> Function() emit;

    Future<void> scheduleNext() async {
      timer?.cancel();
      if (closed) return;
      final next = await nextDueMs();
      if (next == null || closed) return;
      final delay = next - DateTime.now().millisecondsSinceEpoch;
      timer = Timer(
        Duration(milliseconds: delay < 20 ? 20 : delay),
        () => unawaited(emit()),
      );
    }

    emit = () async {
      if (closed) return;
      if (emitting) {
        // 正读着库时又来了新消息：这一轮结束后再补一次，
        // 不能把“刚刚插进来的那条”漏掉。
        pendingEmit = true;
        return;
      }
      emitting = true;
      try {
        final value = await load();
        if (!closed) controller.add(value);
      } catch (error, stack) {
        if (!closed) controller.addError(error, stack);
      } finally {
        emitting = false;
        if (pendingEmit && !closed) {
          pendingEmit = false;
          unawaited(emit());
        } else {
          await scheduleNext();
        }
      }
    };

    controller = StreamController<T>(
      onListen: () {
        changes = _db
            .tableUpdates(TableUpdateQuery.onTable(_db.privateMessages))
            .listen((_) {
          unawaited(emit());
        });
        unawaited(emit());
      },
      onCancel: () async {
        closed = true;
        timer?.cancel();
        await changes?.cancel();
        changes = null;
      },
    );
    return controller.stream;
  }

  /// 最近一条还在“未来”的消息时刻。没有就返回 null。
  Future<int?> _nextFutureAt({
    String? personaId,
    bool incomingOnly = false,
  }) async {
    final soonest = _db.privateMessages.createdAt.min();
    final query = _db.selectOnly(_db.privateMessages)
      ..addColumns([soonest])
      ..where(
        _db.privateMessages.deletedAt.isNull() &
            _db.privateMessages.createdAt.isBiggerThanValue(_now),
      );
    if (personaId != null) {
      query.where(_db.privateMessages.personaId.equals(personaId));
    }
    if (incomingOnly) {
      query.where(_db.privateMessages.direction.equals('in'));
    }
    final row = await query.getSingle();
    return row.read(soonest);
  }

  /// 我发出去一句。立刻就在表里（时间戳就是现在）。
  /// 返回消息 id：图片描述 / 表情包语义要稍后补到同一条上。
  Future<String> send({
    required String personaId,
    required String content,
    String mediaType = 'text',
    String caption = '',
  }) async {
    final id = _newId();
    await _db
        .into(_db.privateMessages)
        .insert(
          PrivateMessagesCompanion.insert(
            id: id,
            personaId: personaId,
            direction: 'out',
            content: Value(content),
            mediaType: Value(mediaType),
            caption: Value(caption),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    return id;
  }

  /// 排一条他发来的话。[at] 可以是将来的时刻——那时它才会出现在会话里。
  Future<String> scheduleIncoming({
    required String personaId,
    required String content,
    required DateTime at,
    String mediaType = 'text',
    String caption = '',
    String voicePath = '',
    String transcript = '',
  }) async {
    final id = _newId();
    await _db
        .into(_db.privateMessages)
        .insert(
          PrivateMessagesCompanion.insert(
            id: id,
            personaId: personaId,
            direction: 'in',
            content: Value(content),
            mediaType: Value(mediaType),
            caption: Value(caption),
            voicePath: Value(voicePath.isEmpty ? null : voicePath),
            transcript: Value(transcript.isEmpty ? null : transcript),
            createdAt: at.millisecondsSinceEpoch,
          ),
        );
    return id;
  }

  /// 图/表情包发出去之后补一句“它是什么”。失败不影响消息本身。
  Future<void> attachCaption(String messageId, String caption) async {
    await (_db.update(
      _db.privateMessages,
    )..where((t) => t.id.equals(messageId))).write(
      PrivateMessagesCompanion(caption: Value(caption.trim())),
    );
  }

  /// 把一句已经发出去的话升级成语音条。
  ///
  /// 和评论一样：文字先落库（用户先看到），合成好了再补音频。
  Future<void> attachVoice({
    required String messageId,
    required String voicePath,
    required String transcript,
  }) async {
    await (_db.update(
      _db.privateMessages,
    )..where((t) => t.id.equals(messageId))).write(
      PrivateMessagesCompanion(
        mediaType: const Value('voice'),
        voicePath: Value(voicePath),
        transcript: Value(transcript),
      ),
    );
  }

  /// 删掉一段会话：只软删消息，不碰住民、记忆或帖子。
  ///
  /// 已经离开的住民不会再有新消息，所以这段历史可以彻底从消息页消失；
  /// 想再聊也没有入口了。
  Future<void> deleteThread(String personaId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.privateMessages)..where(
          (t) => t.personaId.equals(personaId) & t.deletedAt.isNull(),
        ))
        .write(PrivateMessagesCompanion(deletedAt: Value(now)));
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
    caption: row.caption,
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
final privateThreadProvider = StreamProvider.autoDispose
    .family<List<PrivateMessage>, String>(
      (ref, personaId) =>
          ref.watch(privateMessageRepositoryProvider).watchThread(personaId),
    );

/// 未读私信条数（底部导航的红点）。
final privateUnreadCountProvider = StreamProvider<int>(
  (ref) => ref.watch(privateMessageRepositoryProvider).watchUnreadCount(),
);
