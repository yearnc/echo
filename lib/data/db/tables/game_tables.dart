import 'package:drift/drift.dart';

/// 游戏邀请（v4.8）。
///
/// 住民邀请用户，或用户邀请住民。接受/拒绝是状态机，不直接开局；
/// 私信里只放一张指向这里 id 的卡片，邀请被撤回/过期时卡片也跟着变。
@DataClassName('GameInviteRow')
@TableIndex(name: 'game_invites_resident', columns: {#residentId})
class GameInvites extends Table {
  TextColumn get id => text()();
  TextColumn get residentId => text()();
  TextColumn get gameId => text()();

  /// user / resident
  TextColumn get initiator => text()();

  /// pending / accepted / declined / expired / cancelled
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get note => text().withDefault(const Constant(''))();

  /// 私信里那张邀请卡片的 message id。
  TextColumn get messageId => text().nullable()();

  /// 接受后开出来的对局 id；卡片据此直接进棋盘。
  TextColumn get matchId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get expiresAt => integer()();
  IntColumn get resolvedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 一局对弈（v4.8）。
///
/// 棋盘按游戏自己的格式存字符串；胜负、轮次这类公共信息留在列上，
/// 界面和列表不用解析棋盘就能排序/显示。
@DataClassName('GameMatchRow')
@TableIndex(name: 'game_matches_resident', columns: {#residentId})
@TableIndex(name: 'game_matches_status', columns: {#status})
class GameMatches extends Table {
  TextColumn get id => text()();
  TextColumn get residentId => text()();
  TextColumn get gameId => text()();

  /// active / finished / abandoned
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get board => text()();

  /// user / resident
  TextColumn get turn => text().withDefault(const Constant('user'))();

  /// user_win / resident_win / draw，进行中为空。
  TextColumn get result => text().withDefault(const Constant(''))();
  IntColumn get moveCount => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 对局内的文字交流（v4.8）。
///
/// 不写进私信：下棋时说的一句“这步好阴险”是棋盘边的对话，
/// 挂断后由住民总结成记忆，而不是变成聊天记录。
@DataClassName('GameMessageRow')
@TableIndex(name: 'game_messages_match', columns: {#matchId})
class GameMessages extends Table {
  TextColumn get id => text()();
  TextColumn get matchId => text()();
  TextColumn get residentId => text()();

  /// user / resident
  TextColumn get by => text()();
  TextColumn get content => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 落子记录（v4.8）：回放、悔棋、给模型看“刚才走过什么”。
@DataClassName('GameMoveRow')
@TableIndex(name: 'game_moves_match', columns: {#matchId})
class GameMoves extends Table {
  TextColumn get id => text()();
  TextColumn get matchId => text()();
  IntColumn get seq => integer()();

  /// user / resident
  TextColumn get by => text()();
  TextColumn get move => text()();

  /// 这一步走完之后的棋盘。回放和重复局面判断都靠它。
  TextColumn get board => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
