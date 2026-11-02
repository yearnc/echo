library;

/// 小游戏的领域模型。
///
/// 棋盘本身按各游戏自己的格式存成字符串（五子棋是紧凑网格，象棋是 FEN），
/// 这样加新游戏不需要改表结构；具体规则由 `GameEngine` 负责。

enum GameSide { user, resident }

enum GameInviteStatus { pending, accepted, declined, expired, cancelled }

enum GameMatchStatus { active, finished, abandoned }

class GameDefinition {
  const GameDefinition({
    required this.id,
    required this.name,
    required this.description,
    this.minPlayers = 2,
    this.maxPlayers = 2,
    this.plugin = false,
    this.iconName = '',
  });

  final String id;
  final String name;
  final String description;

  /// 含用户在内的人数范围。两人棋类是 2/2；狼人杀固定 9/9。
  final int minPlayers;
  final int maxPlayers;

  /// 来自用户上传的声明式插件。
  final bool plugin;

  /// 插件自己声明的图标名（flutter 里只认几个内置图标，认不出用默认）。
  final String iconName;

  bool get multiplayer => maxPlayers > 2;
}

class GameInvite {
  const GameInvite({
    required this.id,
    required this.residentId,
    required this.gameId,
    required this.initiator,
    required this.status,
    required this.note,
    required this.createdAt,
    required this.expiresAt,
    this.messageId,
    this.matchId,
    this.resolvedAt,
  });

  final String id;
  final String residentId;
  final String gameId;

  /// user = 用户邀请住民；resident = 住民邀请用户。
  final String initiator;
  final GameInviteStatus status;
  final String note;
  final String? messageId;
  final String? matchId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? resolvedAt;

  bool get isPending => status == GameInviteStatus.pending;
  bool get fromResident => initiator == 'resident';
}

class GameMatch {
  const GameMatch({
    required this.id,
    required this.residentId,
    required this.gameId,
    required this.status,
    required this.board,
    required this.turn,
    required this.result,
    required this.moveCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String residentId;
  final String gameId;
  final GameMatchStatus status;

  /// 当前棋盘。格式由对应 `GameEngine` 解释。
  final String board;

  /// 轮到谁走。
  final GameSide turn;

  /// user_win / resident_win / draw，进行中为空。
  final String result;
  final int moveCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status == GameMatchStatus.active;
  bool get isUserTurn => turn == GameSide.user;
}

class GameMove {
  const GameMove({
    required this.id,
    required this.matchId,
    required this.seq,
    required this.by,
    required this.move,
    required this.board,
    required this.createdAt,
  });

  final String id;
  final String matchId;
  final int seq;
  final GameSide by;
  final String move;

  /// 走完这一步之后的棋盘。
  final String board;
  final DateTime createdAt;
}

/// 引擎落子后的结果：成功就带新棋盘，失败带一句给模型看的原因。
class GameMoveResult {
  const GameMoveResult._({
    required this.ok,
    required this.board,
    required this.message,
    this.winner,
    this.draw = false,
  });

  factory GameMoveResult.ok({
    required String board,
    String message = '',
    GameSide? winner,
    bool draw = false,
  }) => GameMoveResult._(
    ok: true,
    board: board,
    message: message,
    winner: winner,
    draw: draw,
  );

  factory GameMoveResult.rejected(String message) =>
      GameMoveResult._(ok: false, board: '', message: message);

  final bool ok;
  final String board;
  final String message;
  final GameSide? winner;
  final bool draw;

  bool get isOver => winner != null || draw;
}

/// 多人对局的一位参与者（v50）。
class GameMatchPlayer {
  const GameMatchPlayer({
    required this.id,
    required this.matchId,
    required this.name,
    required this.seat,
    required this.isUser,
    required this.alive,
    this.residentId = '',
    this.role = '',
    this.avatarAsset = '',
  });

  final String id;
  final String matchId;
  final String residentId;
  final String name;
  final int seat;
  final bool isUser;
  final bool alive;
  final String role;
  final String avatarAsset;
}

class GameMessage {
  const GameMessage({
    required this.id,
    required this.matchId,
    required this.residentId,
    required this.by,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String matchId;
  final String residentId;
  final GameSide by;
  final String content;
  final DateTime createdAt;
}

class GameActionResult {
  const GameActionResult({
    required this.ok,
    required this.message,
    this.match,
    this.winner,
  });

  final bool ok;
  final String message;
  final GameMatch? match;
  final GameSide? winner;
}

GameSide? gameSideByName(String? raw) {
  if (raw == null) return null;
  for (final side in GameSide.values) {
    if (side.name == raw) return side;
  }
  return null;
}

GameInviteStatus gameInviteStatusByName(String raw) {
  for (final status in GameInviteStatus.values) {
    if (status.name == raw) return status;
  }
  return GameInviteStatus.pending;
}

GameMatchStatus gameMatchStatusByName(String raw) {
  for (final status in GameMatchStatus.values) {
    if (status.name == raw) return status;
  }
  return GameMatchStatus.active;
}
