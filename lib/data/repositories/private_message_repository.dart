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

  /// 分段投递的四种状态（v41）。
  ///
  /// - `pending`：写好、还没到点；
  /// - `paused`：你中途又说话了，先停下，等下一轮由住民决定怎么处理；
  /// - `sent`：已经出现 / 历史消息；
  /// - `cancelled`：不要了，永远不出现。
  static const String pendingState = 'pending';
  static const String pausedState = 'paused';
  static const String sentState = 'sent';
  static const String cancelledState = 'cancelled';

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

  /// 这位住民现在是不是还有话没发完（聊天页的「正在打字…」用它）。
  ///
  /// 唤醒结束时会清掉「正在思考」；但分好的段按 3/9/15 秒的节奏一条条出现，
  /// 中间那几秒没有状态，用户会以为对方说完了。这个流只在**未来还有待发段**
  /// 时为 true，到点自动变回 false——不是假打字动画。
  Stream<bool> watchTyping(String personaId) {
    return _dueStream(
      load: () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        final count = _db.privateMessages.id.count();
        final query = _db.selectOnly(_db.privateMessages)
          ..addColumns([count])
          ..where(
            _db.privateMessages.personaId.equals(personaId) &
                _db.privateMessages.direction.equals('in') &
                _db.privateMessages.deletedAt.isNull() &
                _db.privateMessages.deliveryState.equals(pendingState) &
                _db.privateMessages.createdAt.isBiggerThanValue(now),
          );
        final row = await query.getSingle();
        return (row.read(count) ?? 0) > 0;
      },
      nextDueMs: () => _nextFutureAt(personaId: personaId, incomingOnly: true),
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
                  (t) =>
                      t.personaId.equals(personaId) &
                      t.deletedAt.isNull() &
                      // 被用户打断（paused）或取消（cancelled）的段不出现。
                      t.deliveryState.isIn([
                        pendingState,
                        sentState,
                      ]),
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
                _db.privateMessages.deliveryState.isIn([
                  pendingState,
                  sentState,
                ]) &
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
            _db.privateMessages.deliveryState.isIn([pendingState, sentState]) &
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
            direction: 'out',
            content: Value(content),
            mediaType: Value(mediaType),
            caption: Value(caption),
            voicePath: Value(voicePath.isEmpty ? null : voicePath),
            transcript: Value(transcript.isEmpty ? null : transcript),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    return id;
  }

  /// 排一条他发来的话。[at] 可以是将来的时刻——那时它才会出现在会话里。
  ///
  /// [deliveryGroup] 是同一次唤醒的标识，[deliveryIndex] 是第几段。
  /// 还没到点的段状态是 `pending`，可以被用户的新消息打断后取消或改写。
  Future<String> scheduleIncoming({
    required String personaId,
    required String content,
    required DateTime at,
    String mediaType = 'text',
    String caption = '',
    String voicePath = '',
    String transcript = '',
    String deliveryGroup = '',
    int deliveryIndex = 0,
  }) async {
    final id = _newId();
    final pending = deliveryGroup.isNotEmpty && at.isAfter(DateTime.now());
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
            deliveryGroup: Value(deliveryGroup),
            deliveryIndex: Value(deliveryIndex),
            deliveryState: Value(pending ? pendingState : sentState),
          ),
        );
    return id;
  }

  /// 还没到点、也还没被取消的段（按第几段排序）。
  ///
  /// 只读：下一轮唤醒时把“你有几段没发出去、原话是什么”交给住民，
  /// 让它自己决定照发、改写还是算了。
  Future<List<PendingSegment>> pendingSegments(String personaId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows =
        await (_db.select(_db.privateMessages)..where(
              (t) =>
                  t.personaId.equals(personaId) &
                  t.direction.equals('in') &
                  t.deletedAt.isNull() &
                  t.deliveryState.isIn([pendingState, pausedState]),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return [
      for (final row in rows)
        // 暂停的段不管原定时间过没过，都要交给下一轮；
        // 正常待发的段只交还没到点的（过了点的已经在会话里）。
        if (row.deliveryState == pausedState || row.createdAt > now)
          PendingSegment(
          id: row.id,
          groupId: row.deliveryGroup,
          index: row.deliveryIndex,
          content: row.content,
          at: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
          mediaType: row.mediaType,
        ),
    ];
  }

  /// 用户又发了一句：把这一轮还没发出去的段全部暂停。
  ///
  /// 返回被暂停的段，交给下一次唤醒。“已经发出去的”不动——
  /// 只有 `created_at` 还在未来的段才谈得上暂停。
  Future<List<PendingSegment>> pausePendingSegments(String personaId) async {
    final paused = await pendingSegments(personaId);
    if (paused.isEmpty) return const [];
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.privateMessages)..where(
          (t) =>
              t.personaId.equals(personaId) &
              t.deliveryState.equals(pendingState) &
              t.createdAt.isBiggerThanValue(now),
        ))
        .write(
          const PrivateMessagesCompanion(
            deliveryState: Value(pausedState),
          ),
        );
    return paused;
  }

  /// 取消单独一段（模型自己决定某段不发了）。暂停中的段也能取消。
  Future<bool> cancelPendingSegment(String segmentId) async {
    return _markRemoved(segmentId, cancelledState);
  }

  /// 这一轮已经给模型看过、但它没有处理（没改也没取消）的暂停段：
  /// 不能一直挂在待发队列里反复出现，收尾时统一取消。
  Future<int> expirePausedSegments(Iterable<String> ids) async {
    if (ids.isEmpty) return 0;
    return (_db.update(_db.privateMessages)..where(
          (t) =>
              t.id.isIn(ids) & t.deliveryState.equals(pausedState),
        ))
        .write(
          const PrivateMessagesCompanion(
            deliveryState: Value(cancelledState),
          ),
        );
  }

  Future<bool> _markRemoved(String segmentId, String state) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final affected =
        await (_db.update(_db.privateMessages)..where(
              (t) =>
                  t.id.equals(segmentId) &
                  (t.deliveryState.equals(pausedState) |
                      (t.deliveryState.equals(pendingState) &
                          t.createdAt.isBiggerThanValue(now))),
            ))
            .write(PrivateMessagesCompanion(deliveryState: Value(state)));
    return affected > 0;
  }

  /// 改写一段还没发出去的话（时间也可以顺延）。
  Future<bool> rewritePendingSegment({
    required String segmentId,
    required String content,
    DateTime? at,
  }) async {
    final text = content.trim();
    if (text.isEmpty) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final affected =
        await (_db.update(_db.privateMessages)..where(
              (t) =>
                  t.id.equals(segmentId) &
                  (t.deliveryState.equals(pausedState) |
                      (t.deliveryState.equals(pendingState) &
                          t.createdAt.isBiggerThanValue(now))),
            ))
            .write(
              PrivateMessagesCompanion(
                content: Value(text),
                caption: const Value(''),
                mediaType: const Value('text'),
                transcript: const Value(null),
                // 改写过的段重新进入待发；时间不变的话它仍按原计划出现。
                deliveryState: const Value(pendingState),
              ),
            );
    if (affected > 0 && at != null) {
      // createdAt 在更新语句里不是可空字段，单独写一次。
      await (_db.update(_db.privateMessages)..where(
            (t) => t.id.equals(segmentId),
          ))
          .write(
            PrivateMessagesCompanion(
              createdAt: Value(at.millisecondsSinceEpoch),
            ),
          );
    }
    return affected > 0;
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
                    t.deliveryState.isIn([pendingState, sentState]) &
                    t.createdAt.isSmallerOrEqualValue(_now),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(limit))
            .get();
    return rows.reversed.map(_toMessage).toList(growable: false);
  }

  /// 从某个时刻起已经出现的全部私信，按时间正序。
  ///
  /// 上下文时间线同步用：**不设条数上限**，缺的补进来，已有的靠事件 id
  /// 幂等忽略。只取 pending/sent 且已经到点的，未来排期下一轮再补。
  Future<List<PrivateMessage>> turnsSince(
    String personaId, {
    required int afterMs,
  }) async {
    final rows =
        await (_db.select(_db.privateMessages)
              ..where(
                (t) =>
                    t.personaId.equals(personaId) &
                    t.deletedAt.isNull() &
                    t.deliveryState.isIn([pendingState, sentState]) &
                    t.createdAt.isBiggerOrEqualValue(afterMs) &
                    t.createdAt.isSmallerOrEqualValue(_now),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return rows.map(_toMessage).toList(growable: false);
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
      AND u.delivery_state IN ('pending', 'sent')
      AND u.created_at <= $_conversationsNow
  ) AS unread
FROM private_messages m
WHERE m.deleted_at IS NULL
  AND m.delivery_state IN ('pending', 'sent')
  AND m.created_at <= $_conversationsNow
  AND m.id = (
    SELECT l.id FROM private_messages l
    WHERE l.persona_id = m.persona_id
      AND l.deleted_at IS NULL
      AND l.delivery_state IN ('pending', 'sent')
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

/// 这位住民还有没有话没发完（「正在打字…」）。
final privateTypingProvider = StreamProvider.autoDispose.family<bool, String>(
  (ref, personaId) =>
      ref.watch(privateMessageRepositoryProvider).watchTyping(personaId),
);

/// 未读私信条数（底部导航的红点）。
final privateUnreadCountProvider = StreamProvider<int>(
  (ref) => ref.watch(privateMessageRepositoryProvider).watchUnreadCount(),
);
