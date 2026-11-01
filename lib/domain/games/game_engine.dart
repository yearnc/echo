import '../models/game.dart';

/// 一个可扩建的棋类引擎。
///
/// 棋盘统一用字符串表示，具体格式由各引擎自己解释；公共层只认下面的接口，
/// 所以加新游戏时不需要动对局表、邀请表或工具分发。
abstract class GameEngine {
  const GameEngine();

  GameDefinition get definition;

  /// 新开一局时的棋盘。
  String initialBoard();

  /// 走在此引擎里叫什么工具。模型通过 `list_game_tools` 拿到它。
  String get moveToolName;
  Map<String, dynamic> get moveToolSchema;

  /// 把用户/模型给的走法规范化；看不懂就原样返回，由 [apply] 拒绝。
  String normalizeMove(String raw);

  /// 校验并落子。失败时 [GameMoveResult.ok] 为 false，board 为空。
  GameMoveResult apply({
    required String board,
    required String move,
    required GameSide by,
    List<String> history = const [],
  });

  /// 给模型看的文字棋盘 + 走法说明。
  String describeForModel(String board, {required GameSide by});

  /// 模型连续走不出合法棋时，引擎自己兜一个合法落点。
  String suggestMove(String board, {required GameSide by});

  /// 当前这一方所有合法走法，用于 UI 提示和兜底。
  List<String> legalMoves(String board, {required GameSide by});

  /// 日志/聊天卡片里显示的走法（如“H8”）。
  String displayMove(String move) => move;
}
