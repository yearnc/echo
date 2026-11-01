import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/game.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 小游戏的持久层：邀请、对局、落子。
///
/// 状态机放在这里，UI 和模型工具只调用语义方法，不直接拼 SQL。
class GameRepository {
  GameRepository(this._db);

  final AppDatabase _db;
  static final Random _rand = Random();

  /// 邀请 24 小时没回应就过期，卡片上显示“未回应”。
  static const Duration inviteTtl = Duration(hours: 24);

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 20)}';

  // ---------------------------------------------------------------------------
  // 邀请
  // ---------------------------------------------------------------------------

  Future<GameInvite> createInvite({
    required String residentId,
    required String gameId,
    required String initiator,
    String note = '',
    String? messageId,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final id = _newId('invite');
    await _db.into(_db.gameInvites).insert(
      GameInvitesCompanion.insert(
        id: id,
        residentId: residentId,
        gameId: gameId,
        initiator: initiator,
        note: Value(note.trim()),
        messageId: Value(messageId),
        createdAt: at.millisecondsSinceEpoch,
        expiresAt: at.add(inviteTtl).millisecondsSinceEpoch,
      ),
    );
    return (await findInvite(id))!;
  }

  Future<GameInvite?> findInvite(String id) async {
    final row = await (_db.select(_db.gameInvites)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toInvite(row);
  }

  Future<List<GameInvite>> pendingInvites(
    String residentId, {
    DateTime? now,
  }) async {
    await expireStale(now: now);
    final at = now ?? DateTime.now();
    final rows =
        await (_db.select(_db.gameInvites)
              ..where(
                (t) =>
                    t.residentId.equals(residentId) &
                    t.status.equals('pending') &
                    t.expiresAt.isBiggerThanValue(at.millisecondsSinceEpoch),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return rows.map(_toInvite).toList(growable: false);
  }

  Future<List<GameInvite>> invitesFor(String residentId) async {
    await expireStale();
    final rows =
        await (_db.select(_db.gameInvites)
              ..where((t) => t.residentId.equals(residentId))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
    return rows.map(_toInvite).toList(growable: false);
  }

  Stream<List<GameInvite>> watchInvitesFor(String residentId) {
    final query = _db.select(_db.gameInvites)
      ..where((t) => t.residentId.equals(residentId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_toInvite).toList(growable: false),
    );
  }

  Stream<List<GameInvite>> watchAllInvites({int limit = 40}) {
    final query = _db.select(_db.gameInvites)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);
    return query.watch().map(
      (rows) => rows.map(_toInvite).toList(growable: false),
    );
  }

  /// 只允许从 pending 迁移，重复点接受不会开出两局。
  Future<bool> resolveInvite(
    String id,
    GameInviteStatus status, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final affected =
        await (_db.update(_db.gameInvites)..where(
              (t) => t.id.equals(id) & t.status.equals('pending'),
            ))
            .write(
              GameInvitesCompanion(
                status: Value(status.name),
                resolvedAt: Value(at.millisecondsSinceEpoch),
              ),
            );
    return affected > 0;
  }

  Future<int> expireStale({DateTime? now}) async {
    final at = now ?? DateTime.now();
    return (_db.update(_db.gameInvites)..where(
          (t) =>
              t.status.equals('pending') &
              t.expiresAt.isSmallerOrEqualValue(
                at.millisecondsSinceEpoch,
              ),
        ))
        .write(
          GameInvitesCompanion(
            status: const Value('expired'),
            resolvedAt: Value(at.millisecondsSinceEpoch),
          ),
        );
  }

  Future<void> attachMessage(String inviteId, String messageId) async {
    await (_db.update(_db.gameInvites)..where(
          (t) => t.id.equals(inviteId),
        ))
        .write(GameInvitesCompanion(messageId: Value(messageId)));
  }

  Future<void> attachMatch(String inviteId, String matchId) async {
    await (_db.update(_db.gameInvites)..where(
          (t) => t.id.equals(inviteId),
        ))
        .write(GameInvitesCompanion(matchId: Value(matchId)));
  }

  // ---------------------------------------------------------------------------
  // 对局
  // ---------------------------------------------------------------------------

  Future<GameMatch> createMatch({
    required String residentId,
    required String gameId,
    required String board,
    required GameSide turn,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final id = _newId('match');
    await _db.into(_db.gameMatches).insert(
      GameMatchesCompanion.insert(
        id: id,
        residentId: residentId,
        gameId: gameId,
        board: board,
        turn: Value(turn.name),
        createdAt: at.millisecondsSinceEpoch,
        updatedAt: at.millisecondsSinceEpoch,
      ),
    );
    return (await findMatch(id))!;
  }

  Future<GameMatch?> findMatch(String id) async {
    final row = await (_db.select(_db.gameMatches)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toMatch(row);
  }

  Stream<GameMatch?> watchMatch(String id) {
    final query = _db.select(_db.gameMatches)
      ..where((t) => t.id.equals(id));
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : _toMatch(row),
    );
  }

  Future<List<GameMatch>> activeMatches(String residentId) async {
    final rows =
        await (_db.select(_db.gameMatches)
              ..where(
                (t) =>
                    t.residentId.equals(residentId) &
                    t.status.equals('active'),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
            .get();
    return rows.map(_toMatch).toList(growable: false);
  }

  Future<List<GameMatch>> recentMatches({
    String? residentId,
    int limit = 30,
  }) async {
    final query = _db.select(_db.gameMatches)
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(limit);
    if (residentId != null) {
      query.where((t) => t.residentId.equals(residentId));
    }
    final rows = await query.get();
    return rows.map(_toMatch).toList(growable: false);
  }

  Stream<List<GameMatch>> watchActiveMatches() {
    final query = _db.select(_db.gameMatches)
      ..where((t) => t.status.equals('active'))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.watch().map(
      (rows) => rows.map(_toMatch).toList(growable: false),
    );
  }

  Stream<GameInvite?> watchInvite(String id) {
    final query = _db.select(_db.gameInvites)
      ..where((t) => t.id.equals(id));
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : _toInvite(row),
    );
  }

  Stream<List<GameMatch>> watchRecentMatches({int limit = 30}) {
    final query = _db.select(_db.gameMatches)
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(limit);
    return query.watch().map(
      (rows) => rows.map(_toMatch).toList(growable: false),
    );
  }

  Stream<List<GameMatch>> watchMatchesFor(String residentId) {
    final query = _db.select(_db.gameMatches)
      ..where((t) => t.residentId.equals(residentId))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.watch().map(
      (rows) => rows.map(_toMatch).toList(growable: false),
    );
  }

  /// 更新对局。带期望条件时只有状态仍匹配才写入，返回是否真的写到了。
  ///
  /// 模型走棋和用户认输可能同时到达；没有这层比较，后写的一方会把
  /// 另一方刚落的子/刚结束的状态覆盖掉。
  Future<bool> updateMatch({
    required String id,
    required String board,
    required GameSide turn,
    required int moveCount,
    GameMatchStatus status = GameMatchStatus.active,
    String result = '',
    DateTime? now,
    bool expectActive = false,
    GameSide? expectedTurn,
    int? expectedMoveCount,
  }) async {
    final at = now ?? DateTime.now();
    final affected =
        await (_db.update(_db.gameMatches)..where((t) {
              var condition = t.id.equals(id);
              if (expectActive) condition = condition & t.status.equals('active');
              if (expectedTurn != null) {
                condition = condition & t.turn.equals(expectedTurn.name);
              }
              if (expectedMoveCount != null) {
                condition = condition & t.moveCount.equals(expectedMoveCount);
              }
              return condition;
            }))
            .write(
              GameMatchesCompanion(
                board: Value(board),
                turn: Value(turn.name),
                moveCount: Value(moveCount),
                status: Value(status.name),
                result: Value(result),
                updatedAt: Value(at.millisecondsSinceEpoch),
              ),
            );
    return affected > 0;
  }

  Future<void> abandonMatch(String id, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    await (_db.update(_db.gameMatches)..where(
          (t) => t.id.equals(id) & t.status.equals('active'),
        ))
        .write(
          GameMatchesCompanion(
            status: const Value('abandoned'),
            updatedAt: Value(at.millisecondsSinceEpoch),
          ),
        );
  }

  Future<GameMove> appendMove({
    required String matchId,
    required int seq,
    required GameSide by,
    required String move,
    required String board,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final id = _newId('move');
    await _db.into(_db.gameMoves).insert(
      GameMovesCompanion.insert(
        id: id,
        matchId: matchId,
        seq: seq,
        by: by.name,
        move: move,
        board: Value(board),
        createdAt: at.millisecondsSinceEpoch,
      ),
    );
    return GameMove(
      id: id,
      matchId: matchId,
      seq: seq,
      by: by,
      move: move,
      board: board,
      createdAt: at,
    );
  }

  Future<List<GameMove>> movesFor(String matchId) async {
    final rows =
        await (_db.select(_db.gameMoves)
              ..where((t) => t.matchId.equals(matchId))
              ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
            .get();
    return [
      for (final row in rows)
        GameMove(
          id: row.id,
          matchId: row.matchId,
          seq: row.seq,
          by: gameSideByName(row.by) ?? GameSide.user,
          move: row.move,
          board: row.board,
          createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
        ),
    ];
  }

  Future<GameMessage> addMessage({
    required String matchId,
    required String residentId,
    required GameSide by,
    required String content,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final id = _newId('gmsg');
    await _db.into(_db.gameMessages).insert(
      GameMessagesCompanion.insert(
        id: id,
        matchId: matchId,
        residentId: residentId,
        by: by.name,
        content: content.trim(),
        createdAt: at.millisecondsSinceEpoch,
      ),
    );
    return GameMessage(
      id: id,
      matchId: matchId,
      residentId: residentId,
      by: by,
      content: content.trim(),
      createdAt: at,
    );
  }

  Future<List<GameMessage>> messagesFor(String matchId) async {
    final rows =
        await (_db.select(_db.gameMessages)
              ..where((t) => t.matchId.equals(matchId))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return rows.map(_toGameMessage).toList(growable: false);
  }

  Stream<List<GameMessage>> watchMessagesFor(String matchId) {
    final query = _db.select(_db.gameMessages)
      ..where((t) => t.matchId.equals(matchId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_toGameMessage).toList(growable: false),
    );
  }

  GameMessage _toGameMessage(GameMessageRow row) => GameMessage(
    id: row.id,
    matchId: row.matchId,
    residentId: row.residentId,
    by: gameSideByName(row.by) ?? GameSide.user,
    content: row.content,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
  );

  GameInvite _toInvite(GameInviteRow row) => GameInvite(
    id: row.id,
    residentId: row.residentId,
    gameId: row.gameId,
    initiator: row.initiator,
    status: gameInviteStatusByName(row.status),
    note: row.note,
    messageId: row.messageId,
    matchId: row.matchId,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    expiresAt: DateTime.fromMillisecondsSinceEpoch(row.expiresAt),
    resolvedAt: row.resolvedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.resolvedAt!),
  );

  GameMatch _toMatch(GameMatchRow row) => GameMatch(
    id: row.id,
    residentId: row.residentId,
    gameId: row.gameId,
    status: gameMatchStatusByName(row.status),
    board: row.board,
    turn: gameSideByName(row.turn) ?? GameSide.user,
    result: row.result,
    moveCount: row.moveCount,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
  );
}

final gameRepositoryProvider = Provider<GameRepository>(
  (ref) => GameRepository(ref.watch(databaseProvider)),
);
