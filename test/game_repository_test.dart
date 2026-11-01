import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/game_repository.dart';
import 'package:echo/domain/models/game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late GameRepository games;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    games = GameRepository(db);
  });

  tearDown(() async => db.close());

  test('邀请只能从 pending 迁移一次', () async {
    final invite = await games.createInvite(
      residentId: 'r1',
      gameId: 'gomoku',
      initiator: 'resident',
      note: '来一局',
    );
    expect((await games.pendingInvites('r1')).single.id, invite.id);

    expect(
      await games.resolveInvite(invite.id, GameInviteStatus.accepted),
      isTrue,
    );
    expect(
      await games.resolveInvite(invite.id, GameInviteStatus.declined),
      isFalse,
      reason: '接受后不能再拒绝',
    );
    final saved = await games.findInvite(invite.id);
    expect(saved?.status, GameInviteStatus.accepted);
    expect(await games.pendingInvites('r1'), isEmpty);
  });

  test('过期的邀请会被标成 expired，不再出现在待处理里', () async {
    final now = DateTime(2026, 11, 1, 12);
    final invite = await games.createInvite(
      residentId: 'r1',
      gameId: 'xiangqi',
      initiator: 'user',
      now: now,
    );
    expect(
      await games.pendingInvites('r1', now: now.add(const Duration(hours: 1))),
      hasLength(1),
    );
    expect(
      await games.expireStale(now: now.add(const Duration(days: 2))),
      1,
    );
    expect((await games.findInvite(invite.id))?.status, GameInviteStatus.expired);
    expect(
      await games.pendingInvites('r1', now: now.add(const Duration(days: 2))),
      isEmpty,
    );
  });

  test('对局和落子按顺序存下来，棋盘一起回放', () async {
    final match = await games.createMatch(
      residentId: 'r1',
      gameId: 'gomoku',
      board: List.filled(15, '.' * 15).join('/'),
      turn: GameSide.user,
    );
    await games.updateMatch(
      id: match.id,
      board: List.filled(15, '.' * 15).join('/'),
      turn: GameSide.resident,
      moveCount: 1,
    );
    await games.appendMove(
      matchId: match.id,
      seq: 1,
      by: GameSide.user,
      move: 'H8',
      board: 'after-one',
    );
    await games.appendMove(
      matchId: match.id,
      seq: 2,
      by: GameSide.resident,
      move: 'I9',
      board: 'after-two',
    );

    final moves = await games.movesFor(match.id);
    expect(moves.map((move) => move.move), ['H8', 'I9']);
    expect(moves.last.board, 'after-two');
    final saved = await games.findMatch(match.id);
    expect(saved?.turn, GameSide.resident);
    expect(saved?.moveCount, 1);
  });

  test('条件更新挡住并发落子：状态变了就写不进去', () async {
    final match = await games.createMatch(
      residentId: 'r1',
      gameId: 'gomoku',
      board: 'board-0',
      turn: GameSide.user,
    );
    expect(
      await games.updateMatch(
        id: match.id,
        board: 'board-x',
        turn: GameSide.resident,
        moveCount: 1,
        expectActive: true,
        expectedTurn: GameSide.resident,
        expectedMoveCount: 0,
      ),
      isFalse,
      reason: '轮到用户时，住民那一步不能写',
    );
    expect(
      await games.updateMatch(
        id: match.id,
        board: 'board-1',
        turn: GameSide.resident,
        moveCount: 1,
        expectActive: true,
        expectedTurn: GameSide.user,
        expectedMoveCount: 0,
      ),
      isTrue,
    );
    expect(
      await games.updateMatch(
        id: match.id,
        board: 'board-2',
        turn: GameSide.user,
        moveCount: 2,
        expectActive: true,
        expectedTurn: GameSide.user,
        expectedMoveCount: 0,
      ),
      isFalse,
      reason: '第二次基于旧快照的写入必须失败',
    );
  });

  test('棋盘边聊天按时间顺序存，不会混进私信', () async {
    final match = await games.createMatch(
      residentId: 'r1',
      gameId: 'gomoku',
      board: 'board',
      turn: GameSide.user,
    );
    await games.addMessage(
      matchId: match.id,
      residentId: 'r1',
      by: GameSide.user,
      content: '这步好阴险',
    );
    await games.addMessage(
      matchId: match.id,
      residentId: 'r1',
      by: GameSide.resident,
      content: '兵不厌诈',
    );
    final list = await games.messagesFor(match.id);
    expect(list.map((message) => message.content), ['这步好阴险', '兵不厌诈']);
    expect(list.last.by, GameSide.resident);
  });

  test('进行中的对局流只返回 active', () async {
    final active = await games.createMatch(
      residentId: 'r1',
      gameId: 'gomoku',
      board: 'board',
      turn: GameSide.user,
    );
    final done = await games.createMatch(
      residentId: 'r1',
      gameId: 'xiangqi',
      board: 'board',
      turn: GameSide.user,
    );
    await games.updateMatch(
      id: done.id,
      board: 'board',
      turn: GameSide.user,
      moveCount: 3,
      status: GameMatchStatus.finished,
      result: 'user_win',
    );

    final list = await games.watchActiveMatches().first;
    expect(list.map((match) => match.id), [active.id]);
  });
}
