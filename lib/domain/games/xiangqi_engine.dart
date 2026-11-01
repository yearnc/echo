import 'package:cchess/cchess.dart';

import '../models/game.dart';
import 'game_engine.dart';

/// 中国象棋。规则交给 MIT 的 `cchess`，这里只做：
/// 用户/住民的执方映射、合法性二次校验、胜负/重复局面、给模型看的文字棋盘。
///
/// 棋盘存标准 FEN 的第一段（没有 ` w - - 0 1` 后缀）；走法写成
/// `from + to`，例如 `b0c2`。
class XiangqiEngine extends GameEngine {
  const XiangqiEngine();

  /// cchess 里 0 = 红（大写），1 = 黑（小写）。
  static int teamOf(GameSide side) => side == GameSide.user ? 0 : 1;

  @override
  GameDefinition get definition => const GameDefinition(
    id: 'xiangqi',
    name: '象棋',
    description: '中国象棋，红方先走；将死或困毙对方即胜。',
  );

  @override
  String initialBoard() => ChessFen.initFen;

  @override
  String get moveToolName => 'xiangqi_move';

  @override
  Map<String, dynamic> get moveToolSchema => {
    'type': 'function',
    'function': {
      'name': moveToolName,
      'description': '走一步象棋。坐标用 cchess 记法：列 a—i，行 0—9（红方在下）。',
      'parameters': {
        'type': 'object',
        'properties': {
          'match_id': {'type': 'string', 'description': '对局 id'},
          'from': {'type': 'string', 'description': '起点，如 b0'},
          'to': {'type': 'string', 'description': '终点，如 c2'},
        },
        'required': ['match_id', 'from', 'to'],
      },
    },
  };

  @override
  String normalizeMove(String raw) {
    var text = raw.toLowerCase().replaceAll(RegExp(r'[\s\-_,，]'), '');
    if (text.length == 4 &&
        RegExp(r'^[a-i][0-9][a-i][0-9]$').hasMatch(text)) {
      return text;
    }
    return raw.trim();
  }

  @override
  GameMoveResult apply({
    required String board,
    required String move,
    required GameSide by,
    List<String> history = const [],
  }) {
    final rule = _rule(board);
    if (rule == null) return GameMoveResult.rejected('棋局数据坏了，重新开一局吧');
    final normalized = normalizeMove(move);
    if (!RegExp(r'^[a-i][0-9][a-i][0-9]$').hasMatch(normalized)) {
      return GameMoveResult.rejected('走法看不懂，请写成 from+to，例如 b0c2');
    }
    final from = ChessPos.fromCode(normalized.substring(0, 2));
    final to = ChessPos.fromCode(normalized.substring(2));
    if (from.x < 0 ||
        from.x > 8 ||
        from.y < 0 ||
        from.y > 9 ||
        to.x < 0 ||
        to.x > 8 ||
        to.y < 0 ||
        to.y > 9) {
      return GameMoveResult.rejected('走法超出棋盘范围');
    }
    final piece = rule.fen[from.y][from.x];
    if (piece == '0') return GameMoveResult.rejected('起点没有棋子');
    final team = teamOf(by);
    if (ChessItem(piece).team != team) {
      return GameMoveResult.rejected('那颗棋子不是你的');
    }
    if (!_legal(rule, team).contains(normalized)) {
      return GameMoveResult.rejected('这一步不合法（可能被将军、蹩马腿或终点被占）');
    }

    final next = rule.fen.copy();
    if (!next.move(normalized)) {
      return GameMoveResult.rejected('这一步走不了');
    }
    final nextRule = ChessRule(next);
    if (nextRule.isKingMeet(team)) {
      return GameMoveResult.rejected('不能把两个将帅走到同一条线上');
    }
    final enemy = team == 0 ? 1 : 0;
    final won = nextRule.isCheckMate(enemy);
    final nextFen = next.fen;
    final repeats = history.where((item) => item == nextFen).length;
    final draw = !won && repeats >= 2;

    return GameMoveResult.ok(
      board: nextFen,
      message: won
          ? (nextRule.isCheck(enemy) ? '将死' : '困毙')
          : draw
          ? '同一局面重复三次，判和'
          : '',
      winner: won ? by : null,
      draw: draw,
    );
  }

  @override
  String describeForModel(String board, {required GameSide by}) {
    final rule = _rule(board);
    if (rule == null) return '棋局数据坏了。';
    final buffer = StringBuffer()
      ..writeln('中国象棋。你执${by == GameSide.user ? '红（帅仕相马车炮兵）' : '黑（将士象马车砲卒）'}。')
      ..writeln('列 a—i 从左到右，行 0—9 从下往上（红方在下方）。')
      ..writeln('走法写 from+to，例如 b0c2。');
    for (var y = 9; y >= 0; y--) {
      buffer.write('$y  ');
      for (var x = 0; x < 9; x++) {
        final code = rule.fen[y][x];
        buffer.write(_pieceLabel(code));
        if (x != 8) buffer.write(' ');
      }
      buffer.writeln();
    }
    buffer
      ..writeln('   a b c d e f g h i')
      ..writeln('FEN: ${rule.fen.fen}');
    return buffer.toString().trimRight();
  }

  @override
  String suggestMove(String board, {required GameSide by}) {
    final rule = _rule(board);
    if (rule == null) return '';
    final team = teamOf(by);
    final moves = _legal(rule, team);
    if (moves.isEmpty) return '';
    var best = moves.first;
    var bestScore = -1;
    for (final move in moves) {
      final target = ChessPos.fromCode(move.substring(2));
      final code = rule.fen[target.y][target.x];
      final captured = code == '0'
          ? 0
          : (ChessRule.chessWeight[code.toLowerCase()] ?? 0);
      // 能吃子优先吃大的；同等时偏好向前/靠中间，至少不会原地打转。
      final center = (target.x - 4).abs();
      final score = captured * 100 - center;
      if (score > bestScore) {
        bestScore = score;
        best = move;
      }
    }
    return best;
  }

  @override
  List<String> legalMoves(String board, {required GameSide by}) {
    final rule = _rule(board);
    if (rule == null) return const [];
    return _legal(rule, teamOf(by));
  }

  static ChessRule? _rule(String board) {
    try {
      return ChessRule.fromFen(board);
    } catch (_) {
      return null;
    }
  }

  static List<String> _legal(ChessRule rule, int team) {
    final moves = <String>[];
    for (final item in rule.fen.getAll()) {
      if (item.team != team) continue;
      for (final point in rule.movePoints(item.position)) {
        final move = '${item.position.toCode()}$point';
        final next = rule.fen.copy();
        if (!next.move(move)) continue;
        final nextRule = ChessRule(next);
        if (nextRule.isCheck(team) || nextRule.isKingMeet(team)) continue;
        moves.add(move);
      }
    }
    return moves;
  }

  static String _pieceLabel(String code) {
    if (code == '0') return '·';
    final isRed = code.codeUnitAt(0) < ChessFen.colIndexBase;
    final table = isRed ? ChessFen.nameRedMap : ChessFen.nameBlackMap;
    return table[code.toLowerCase()] ?? '?';
  }
}
