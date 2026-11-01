import 'dart:io';
import 'dart:ui' as ui;

import 'package:cchess/cchess.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/games/gomoku_engine.dart';
import '../../domain/models/game.dart';

const Color _wood = Color(0xFFF2E3C4);
const Color _woodEdge = Color(0xFFD9C39A);
const Color _line = Color(0xFF8A623C);
const Color _blackStone = Color(0xFF211C1A);
const Color _whiteStone = Color(0xFFFBFAF7);
const Color _redPiece = Color(0xFFB23A3A);
const Color _blackPiece = Color(0xFF26221F);

/// 五子棋棋盘。棋盘页和截图共用同一个 painter。
class GomokuBoard extends StatelessWidget {
  const GomokuBoard({
    super.key,
    required this.board,
    this.enabled = false,
    this.lastMove,
    this.onTap,
  });

  final String board;
  final bool enabled;
  final String? lastMove;
  final void Function(int x, int y)? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxWidth);
        return GestureDetector(
          onTapDown: enabled && onTap != null
              ? (details) {
                  final pos = GomokuPainter.hitCell(
                    details.localPosition,
                    size,
                  );
                  if (pos != null) onTap!(pos.$1, pos.$2);
                }
              : null,
          child: CustomPaint(
            size: size,
            painter: GomokuPainter(board: board, lastMove: lastMove),
          ),
        );
      },
    );
  }
}

class GomokuPainter extends CustomPainter {
  GomokuPainter({required this.board, this.lastMove});

  final String board;
  final String? lastMove;

  static const int n = GomokuEngine.size;

  static (int, int)? hitCell(Offset local, Size size) {
    final padding = size.width * 0.045;
    final cell = (size.width - padding * 2) / (n - 1);
    final x = ((local.dx - padding) / cell).round();
    final y = ((local.dy - padding) / cell).round();
    if (x < 0 || x >= n || y < 0 || y >= n) return null;
    return (x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rows = board.split('/');
    if (rows.length != n) return;
    final padding = size.width * 0.045;
    final cell = (size.width - padding * 2) / (n - 1);

    final bg = Paint()..color = _wood;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.width * 0.03),
      ),
      bg,
    );
    final edge = Paint()
      ..color = _woodEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.width * 0.03),
      ),
      edge,
    );

    final line = Paint()
      ..color = _line
      ..strokeWidth = size.width > 400 ? 1.2 : 1;
    for (var i = 0; i < n; i++) {
      final at = padding + cell * i;
      canvas.drawLine(
        Offset(padding, at),
        Offset(padding + cell * (n - 1), at),
        line,
      );
      canvas.drawLine(
        Offset(at, padding),
        Offset(at, padding + cell * (n - 1)),
        line,
      );
    }
    // 五个星位
    final star = Paint()..color = _line;
    for (final (x, y) in const [(3, 3), (11, 3), (7, 7), (3, 11), (11, 11)]) {
      canvas.drawCircle(
        Offset(padding + cell * x, padding + cell * y),
        cell * 0.08,
        star,
      );
    }

    final last = _parse(lastMove);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final cellValue = rows[y][x];
        if (cellValue == '.') continue;
        final center = Offset(padding + cell * x, padding + cell * y);
        final radius = cell * 0.42;
        if (cellValue == 'b') {
          canvas.drawCircle(center, radius, Paint()..color = _blackStone);
        } else {
          canvas.drawCircle(center, radius, Paint()..color = _whiteStone);
          canvas.drawCircle(
            center,
            radius,
            Paint()
              ..color = const Color(0xFF9B9B9B)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        }
        if (last != null && last.$1 == x && last.$2 == y) {
          canvas.drawCircle(
            center,
            radius * 0.28,
            Paint()
              ..color = cellValue == 'b' ? _whiteStone : _blackStone,
          );
        }
      }
    }

    // 坐标标注：视觉模型看图时也能对回文字棋盘里的 A1—O15。
    final labelStyle = TextStyle(
      color: _line,
      fontSize: cell * 0.28,
      fontWeight: FontWeight.w600,
    );
    for (var x = 0; x < n; x++) {
      _label(
        canvas,
        String.fromCharCode(65 + x),
        Offset(padding + cell * x, padding + cell * (n - 1) + cell * 0.35),
        labelStyle,
      );
    }
    for (var y = 0; y < n; y++) {
      _label(
        canvas,
        '${y + 1}',
        Offset(padding - cell * 0.55, padding + cell * y),
        labelStyle,
      );
    }
  }

  static void _label(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  static (int, int)? _parse(String? move) {
    if (move == null) return null;
    final match = RegExp(r'^([A-O])(\d{1,2})$').firstMatch(move);
    if (match == null) return null;
    return (
      match.group(1)!.codeUnitAt(0) - 65,
      int.parse(match.group(2)!) - 1,
    );
  }

  @override
  bool shouldRepaint(covariant GomokuPainter old) =>
      old.board != board || old.lastMove != lastMove;
}

/// 象棋棋盘。红方在下方（y=0），绘制时 y=9 在最上面。
class XiangqiBoard extends StatelessWidget {
  const XiangqiBoard({
    super.key,
    required this.board,
    this.enabled = false,
    this.selected,
    this.targets = const {},
    this.onTap,
  });

  final String board;
  final bool enabled;
  final (int, int)? selected;
  final Set<(int, int)> targets;
  final void Function(int x, int y)? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxWidth * 10 / 9;
        final size = Size(constraints.maxWidth, height);
        return GestureDetector(
          onTapDown: enabled && onTap != null
              ? (details) {
                  final pos = XiangqiPainter.hitPoint(
                    details.localPosition,
                    size,
                  );
                  if (pos != null) onTap!(pos.$1, pos.$2);
                }
              : null,
          child: CustomPaint(
            size: size,
            painter: XiangqiPainter(
              board: board,
              selected: selected,
              targets: targets,
            ),
          ),
        );
      },
    );
  }
}

class XiangqiPainter extends CustomPainter {
  XiangqiPainter({required this.board, this.selected, this.targets = const {}});

  final String board;
  final (int, int)? selected;
  final Set<(int, int)> targets;

  static (int, int)? hitPoint(Offset local, Size size) {
    final offset = _geometry(size);
    if (offset == null) return null;
    final (left, top, cell) = offset;
    final x = ((local.dx - left) / cell).round();
    final y = 9 - ((local.dy - top) / cell).round();
    if (x < 0 || x > 8 || y < 0 || y > 9) return null;
    return (x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _geometry(size);
    if (geometry == null) return;
    final (left, top, cell) = geometry;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(cell * 0.25),
      ),
      Paint()..color = _wood,
    );
    final line = Paint()
      ..color = _line
      ..strokeWidth = size.width > 400 ? 1.3 : 1;

    Offset at(int x, int y) => Offset(left + cell * x, top + cell * (9 - y));

    for (var y = 0; y < 10; y++) {
      canvas.drawLine(at(0, y), at(8, y), line);
    }
    for (var x = 0; x < 9; x++) {
      if (x == 0 || x == 8) {
        canvas.drawLine(at(x, 0), at(x, 9), line);
      } else {
        canvas.drawLine(at(x, 0), at(x, 4), line);
        canvas.drawLine(at(x, 5), at(x, 9), line);
      }
    }
    // 九宫斜线
    for (final y0 in const [0, 7]) {
      canvas.drawLine(at(3, y0), at(5, y0 + 2), line);
      canvas.drawLine(at(5, y0), at(3, y0 + 2), line);
    }
    // 河界
    final river = TextPainter(
      text: TextSpan(
        text: '楚 河          汉 界',
        style: TextStyle(
          color: _line.withValues(alpha: 0.65),
          fontSize: cell * 0.34,
          letterSpacing: cell * 0.05,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    river.paint(
      canvas,
      Offset(left + cell * 1.2, top + cell * 4.5 - river.height / 2),
    );

    final rule = _rule(board);
    if (rule == null) return;
    for (var y = 0; y < 10; y++) {
      for (var x = 0; x < 9; x++) {
        final code = rule.fen[y][x];
        if (code == '0') continue;
        final center = at(x, y);
        final isRed = code.codeUnitAt(0) < ChessFen.colIndexBase;
        canvas.drawCircle(
          center,
          cell * 0.405,
          Paint()..color = const Color(0xFFF8EFD8),
        );
        canvas.drawCircle(
          center,
          cell * 0.405,
          Paint()
            ..color = isRed ? _redPiece : _blackPiece
            ..style = PaintingStyle.stroke
            ..strokeWidth = size.width > 400 ? 2.2 : 1.5,
        );
        final label = TextPainter(
          text: TextSpan(
            text: _pieceLabel(code),
            style: TextStyle(
              color: isRed ? _redPiece : _blackPiece,
              fontSize: cell * 0.48,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(
          canvas,
          center - Offset(label.width / 2, label.height / 2),
        );
      }
    }

    if (selected != null) {
      canvas.drawCircle(
        at(selected!.$1, selected!.$2),
        cell * 0.46,
        Paint()
          ..color = const Color(0xFF3A7BD5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    for (final target in targets) {
      canvas.drawCircle(
        at(target.$1, target.$2),
        cell * 0.12,
        Paint()..color = const Color(0xFF3A7BD5).withValues(alpha: 0.65),
      );
    }

    final labelStyle = TextStyle(
      color: _line,
      fontSize: cell * 0.26,
      fontWeight: FontWeight.w600,
    );
    for (var x = 0; x < 9; x++) {
      _label(
        canvas,
        String.fromCharCode(97 + x),
        Offset(left + cell * x, top + cell * 9 + cell * 0.45),
        labelStyle,
      );
    }
    for (var y = 0; y < 10; y++) {
      _label(
        canvas,
        '$y',
        Offset(left - cell * 0.45, top + cell * (9 - y)),
        labelStyle,
      );
    }
  }

  static void _label(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  static (double, double, double)? _geometry(Size size) {
    const padding = 22.0;
    final cell = ((size.width - padding * 2) / 8)
        .clamp(0.0, (size.height - padding * 2) / 9);
    final boardWidth = cell * 8;
    final boardHeight = cell * 9;
    return (
      (size.width - boardWidth) / 2,
      (size.height - boardHeight) / 2,
      cell,
    );
  }

  static ChessRule? _rule(String board) {
    try {
      return ChessRule.fromFen(board);
    } catch (_) {
      return null;
    }
  }

  static String _pieceLabel(String code) {
    final isRed = code.codeUnitAt(0) < ChessFen.colIndexBase;
    final table = isRed ? ChessFen.nameRedMap : ChessFen.nameBlackMap;
    return table[code.toLowerCase()] ?? '?';
  }

  @override
  bool shouldRepaint(covariant XiangqiPainter old) =>
      old.board != board ||
      old.selected != selected ||
      old.targets != targets;
}

/// 把棋盘画成 PNG 交给视觉模型。走棋可能发生在没有页面上下文的时候，
/// 所以不能依赖 RepaintBoundary。
class BoardImageRenderer {
  BoardImageRenderer();

  final Map<String, String> _cache = {};

  Future<String?> render(GameMatch match) async {
    final key = '${match.gameId}:${match.board}';
    final cached = _cache[key];
    if (cached != null && File(_path(cached)).existsSync()) return cached;

    try {
      final size = match.gameId == 'xiangqi'
          ? const Size(720, 800)
          : const Size(720, 720);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = _wood,
      );
      if (match.gameId == 'xiangqi') {
        XiangqiPainter(board: match.board).paint(canvas, size);
      } else {
        GomokuPainter(board: match.board).paint(canvas, size);
      }
      final picture = recorder.endRecording();
      ui.Image? image;
      try {
        image = await picture.toImage(
          size.width.round(),
          size.height.round(),
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) return null;

        final dir = Directory(
          '${(await getTemporaryDirectory()).path}/game_boards',
        );
        if (!await dir.exists()) await dir.create(recursive: true);
        final file = File('${dir.path}/board_${key.hashCode}.png');
        await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        final ref = 'file:${file.path}';
        _cache[key] = ref;
        if (_cache.length > 12) {
          final oldestKey = _cache.keys.first;
          final oldRef = _cache.remove(oldestKey);
          if (oldRef != null) {
            try {
              final oldFile = File(_path(oldRef));
              if (oldFile.existsSync()) oldFile.deleteSync();
            } catch (_) {}
          }
        }
        return ref;
      } finally {
        image?.dispose();
        picture.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  static String _path(String ref) =>
      ref.startsWith('file:') ? ref.substring(5) : ref;
}
