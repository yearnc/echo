import '../models/game.dart';
import 'game_engine.dart';

/// 15×15 五子棋。
///
/// 棋盘用 15 行、每行 15 个字符存：`.` 空、`b` 用户（黑）、`w` 住民（白）。
/// 行从上往下，列从左往右；走法写成 `H8` 这种“列字母 + 行号”。
class GomokuEngine extends GameEngine {
  const GomokuEngine();

  static const int size = 15;
  static const String _empty = '.';

  @override
  GameDefinition get definition => const GameDefinition(
    id: 'gomoku',
    name: '五子棋',
    description: '15×15，先连成五子的一方赢。',
  );

  @override
  String initialBoard() =>
      List<String>.filled(size, _empty * size).join('/');

  @override
  String get moveToolName => 'gomoku_place';

  @override
  Map<String, dynamic> get moveToolSchema => {
    'type': 'function',
    'function': {
      'name': moveToolName,
      'description': '在五子棋棋盘上落一子。列 A—O，行 1—15。',
      'parameters': {
        'type': 'object',
        'properties': {
          'match_id': {'type': 'string', 'description': '对局 id'},
          'position': {
            'type': 'string',
            'description': '落点，如 H8（列 H、第 8 行）',
          },
        },
        'required': ['match_id', 'position'],
      },
    },
  };

  @override
  String normalizeMove(String raw) {
    final match = RegExp(
      r'^\s*([A-Oa-o])\s*[-_,，]?\s*(\d{1,2})\s*$',
    ).firstMatch(raw);
    if (match == null) return raw.trim();
    final col = match.group(1)!.toUpperCase();
    final row = int.tryParse(match.group(2)!);
    if (row == null || row < 1 || row > size) return raw.trim();
    return '$col$row';
  }

  @override
  GameMoveResult apply({
    required String board,
    required String move,
    required GameSide by,
    List<String> history = const [],
  }) {
    final rows = _rows(board);
    if (rows == null) return GameMoveResult.rejected('棋盘数据坏了，重新开一局吧');
    final pos = _parse(move);
    if (pos == null) {
      return GameMoveResult.rejected('落点看不懂，请用 H8 这种格式（列 A—O、行 1—15）');
    }
    final (x, y) = pos;
    if (rows[y][x] != _empty) return GameMoveResult.rejected('这个位置已经有子了');
    final stone = by == GameSide.user ? 'b' : 'w';
    final next = [
      for (var row = 0; row < size; row++)
        row == y
            ? '${rows[row].substring(0, x)}$stone${rows[row].substring(x + 1)}'
            : rows[row],
    ];
    final won = _wins(next, x, y, stone);
    final full = next.every((row) => !row.contains(_empty));
    return GameMoveResult.ok(
      board: next.join('/'),
      message: won ? '连成五子' : '',
      winner: won ? by : null,
      draw: !won && full,
    );
  }

  @override
  String describeForModel(String board, {required GameSide by}) {
    final rows = _rows(board);
    if (rows == null) return '棋盘数据坏了。';
    final buffer = StringBuffer()
      ..writeln('五子棋 15×15。你执${by == GameSide.user ? '黑（●）' : '白（○）'}。')
      ..writeln('列 A—O，行 1—15，从上往下。')
      ..write('    ');
    for (var x = 0; x < size; x++) {
      buffer.write(String.fromCharCode(65 + x));
      if (x != size - 1) buffer.write(' ');
    }
    buffer.writeln();
    for (var y = 0; y < size; y++) {
      buffer.write('${(y + 1).toString().padLeft(2)}  ');
      for (var x = 0; x < size; x++) {
        final cell = rows[y][x];
        buffer.write(
          cell == 'b'
              ? '●'
              : cell == 'w'
              ? '○'
              : '·',
        );
        if (x != size - 1) buffer.write(' ');
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  @override
  String suggestMove(String board, {required GameSide by}) {
    final rows = _rows(board);
    if (rows == null) return '';
    final stone = by == GameSide.user ? 'b' : 'w';
    final other = by == GameSide.user ? 'w' : 'b';
    (int, int)? best;
    var bestScore = -1;
    var bestDistance = 1 << 20;
    var hasStone = false;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (rows[y][x] != _empty) {
          hasStone = true;
          continue;
        }
        if (!_nearStone(rows, x, y)) continue;
        final attack = _lineScore(rows, x, y, stone);
        final defend = _lineScore(rows, x, y, other);
        final score = attack * 11 + defend * 10;
        final center = (x - 7).abs() + (y - 7).abs();
        if (score > bestScore ||
            (score == bestScore && center < bestDistance)) {
          bestScore = score;
          bestDistance = center;
          best = (x, y);
        }
      }
    }
    if (!hasStone) return 'H8';
    if (best == null) {
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          if (rows[y][x] == _empty) {
            return '${String.fromCharCode(65 + x)}${y + 1}';
          }
        }
      }
      return '';
    }
    return '${String.fromCharCode(65 + best.$1)}${best.$2 + 1}';
  }

  @override
  List<String> legalMoves(String board, {required GameSide by}) {
    final rows = _rows(board);
    if (rows == null) return const [];
    return [
      for (var y = 0; y < size; y++)
        for (var x = 0; x < size; x++)
          if (rows[y][x] == _empty)
            '${String.fromCharCode(65 + x)}${y + 1}',
    ];
  }

  static List<String>? _rows(String board) {
    final rows = board.split('/');
    if (rows.length != size) return null;
    if (rows.any((row) => row.length != size)) return null;
    return rows;
  }

  static (int, int)? _parse(String move) {
    final match = RegExp(r'^([A-Oa-o])(\d{1,2})$').firstMatch(move.trim());
    if (match == null) return null;
    final x = match.group(1)!.toUpperCase().codeUnitAt(0) - 65;
    final row = int.tryParse(match.group(2)!);
    if (row == null || row < 1 || row > size) return null;
    return (x, row - 1);
  }

  static bool _wins(List<String> rows, int x, int y, String stone) {
    const directions = [(1, 0), (0, 1), (1, 1), (1, -1)];
    for (final (dx, dy) in directions) {
      var count = 1;
      for (final sign in [1, -1]) {
        var cx = x + dx * sign;
        var cy = y + dy * sign;
        while (cx >= 0 &&
            cx < size &&
            cy >= 0 &&
            cy < size &&
            rows[cy][cx] == stone) {
          count++;
          cx += dx * sign;
          cy += dy * sign;
        }
      }
      if (count >= 5) return true;
    }
    return false;
  }

  static bool _nearStone(List<String> rows, int x, int y) {
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final cx = x + dx;
        final cy = y + dy;
        if (cx < 0 || cx >= size || cy < 0 || cy >= size) continue;
        if (rows[cy][cx] != _empty) return true;
      }
    }
    return false;
  }

  static int _lineScore(List<String> rows, int x, int y, String stone) {
    const directions = [(1, 0), (0, 1), (1, 1), (1, -1)];
    var best = 0;
    for (final (dx, dy) in directions) {
      var count = 1;
      var open = 0;
      for (final sign in [1, -1]) {
        var cx = x + dx * sign;
        var cy = y + dy * sign;
        while (cx >= 0 &&
            cx < size &&
            cy >= 0 &&
            cy < size &&
            rows[cy][cx] == stone) {
          count++;
          cx += dx * sign;
          cy += dy * sign;
        }
        if (cx >= 0 &&
            cx < size &&
            cy >= 0 &&
            cy < size &&
            rows[cy][cx] == _empty) {
          open++;
        }
      }
      final score = count >= 5
          ? 100000
          : count == 4
          ? (open == 2 ? 10000 : open == 1 ? 4000 : 0)
          : count == 3
          ? (open == 2 ? 1000 : open == 1 ? 200 : 0)
          : count == 2
          ? (open == 2 ? 100 : open == 1 ? 20 : 0)
          : 10;
      if (score > best) best = score;
    }
    return best;
  }
}
