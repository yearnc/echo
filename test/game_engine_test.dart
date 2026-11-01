import 'package:echo/domain/games/game_registry.dart';
import 'package:echo/domain/games/game_tools.dart';
import 'package:echo/domain/games/gomoku_engine.dart';
import 'package:echo/domain/games/xiangqi_engine.dart';
import 'package:echo/domain/services/game_session_registry.dart';
import 'package:echo/domain/models/game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('五子棋', () {
    const engine = GomokuEngine();

    test('初始棋盘 15×15，走 H8 落在第 8 行第 H 列', () {
      final board = engine.initialBoard();
      expect(board.split('/').length, 15);
      expect(board.split('/').every((row) => row.length == 15), isTrue);

      final result = engine.apply(
        board: board,
        move: 'H8',
        by: GameSide.user,
      );
      expect(result.ok, isTrue);
      final rows = result.board.split('/');
      expect(rows[7][7], 'b');
    });

    test('同一个点不能重复落子，非法坐标会被拒绝', () {
      final first = engine.apply(
        board: engine.initialBoard(),
        move: 'H8',
        by: GameSide.user,
      );
      expect(
        engine.apply(board: first.board, move: 'H8', by: GameSide.resident).ok,
        isFalse,
      );
      expect(
        engine.apply(board: first.board, move: 'Z99', by: GameSide.resident).ok,
        isFalse,
      );
    });

    test('横向连成五子判胜', () {
      var board = engine.initialBoard();
      var last = engine.apply(
        board: board,
        move: 'D8',
        by: GameSide.user,
      );
      expect(last.ok, isTrue);
      board = last.board;
      for (final col in ['E', 'F', 'G', 'H']) {
        last = engine.apply(board: board, move: '${col}8', by: GameSide.user);
        expect(last.ok, isTrue);
        board = last.board;
      }
      expect(last.winner, GameSide.user);
      expect(last.isOver, isTrue);
    });

    test('兜底落点总是合法的空位', () {
      final move = engine.suggestMove(engine.initialBoard(), by: GameSide.resident);
      expect(move, isNotEmpty);
      final result = engine.apply(
        board: engine.initialBoard(),
        move: move,
        by: GameSide.resident,
      );
      expect(result.ok, isTrue);
    });
  });

  group('对局会话', () {
    test('对局登记后，桌宠观察会被暂停', () {
      GameSessionRegistry.clear();
      expect(GameSessionRegistry.hasAny, isFalse);
      GameSessionRegistry.begin('match_1', 'resident_1');
      expect(GameSessionRegistry.hasAny, isTrue);
      expect(GameSessionRegistry.isActiveResident('resident_1'), isTrue);
      expect(GameSessionRegistry.isActiveResident('resident_2'), isFalse);
      GameSessionRegistry.end('match_1');
      expect(GameSessionRegistry.hasAny, isFalse);
    });
  });

  group('工具发现', () {
    test('基础游戏工具齐全，走棋工具能按名字找到引擎', () {
      final names = [
        for (final tool in GameTools.baseTools)
          (tool['function'] as Map)['name'],
      ];
      expect(names, containsAll([
        GameTools.listGameTools,
        GameTools.inviteGame,
        GameTools.respondInvite,
        GameTools.resign,
      ]));
      expect(GameRegistry.byToolName('gomoku_place')?.definition.id, 'gomoku');
      expect(GameRegistry.byToolName('xiangqi_move')?.definition.id, 'xiangqi');
    });
  });

  group('象棋', () {
    const engine = XiangqiEngine();

    test('红马 b0 可以走到 c2', () {
      final result = engine.apply(
        board: engine.initialBoard(),
        move: 'b0c2',
        by: GameSide.user,
      );
      expect(result.ok, isTrue, reason: result.message);
      expect(result.board, isNot(engine.initialBoard()));
    });

    test('不合法走法和走错方的棋子都会被拒绝', () {
      expect(
        engine.apply(
          board: engine.initialBoard(),
          move: 'b0b1',
          by: GameSide.user,
        ).ok,
        isFalse,
      );
      expect(
        engine.apply(
          board: engine.initialBoard(),
          move: 'b9c7',
          by: GameSide.user,
        ).ok,
        isFalse,
      );
    });

    test('红黑双方都能走出合法棋，兜底也合法', () {
      final red = engine.apply(
        board: engine.initialBoard(),
        move: 'b0c2',
        by: GameSide.user,
      );
      expect(red.ok, isTrue);
      final black = engine.apply(
        board: red.board,
        move: 'b9c7',
        by: GameSide.resident,
      );
      expect(black.ok, isTrue, reason: black.message);

      final fallback = engine.suggestMove(black.board, by: GameSide.user);
      expect(fallback, isNotEmpty);
      expect(
        engine.apply(
          board: black.board,
          move: fallback,
          by: GameSide.user,
        ).ok,
        isTrue,
      );
    });

    test('不能把挡在两将之间的子挪开让将帅照面', () {
      const fen = '4k4/9/9/9/4R4/9/9/9/9/4K4';
      expect(
        engine.legalMoves(fen, by: GameSide.user),
        isNot(contains('e5d5')),
      );
      expect(
        engine.apply(
          board: fen,
          move: 'e5d5',
          by: GameSide.user,
        ).ok,
        isFalse,
      );
    });

    test('文字棋盘包含坐标和 FEN', () {
      final text = engine.describeForModel(
        engine.initialBoard(),
        by: GameSide.resident,
      );
      expect(text, contains('a—i'));
      expect(text, contains('FEN:'));
    });
  });
}
