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

  /// 一次多人邀请共用同一个 partyId（v50）。
  ///
  /// 两人棋类的 partyId 为空；狼人杀这类多人局把同一批邀请串起来，
  /// 每张卡片仍能单独接受/拒绝。
  TextColumn get partyId => text().withDefault(const Constant(''))();
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

/// 多人对局的参与者（v50）。
///
/// 两人棋类也会写两行：用户一行、住民一行，方便统一的参与者列表。
/// 狼人杀里每一行还带角色和存活状态；`role` 只对局内可见。
@DataClassName('GameMatchPlayerRow')
@TableIndex(name: 'game_match_players_match', columns: {#matchId})
class GameMatchPlayers extends Table {
  TextColumn get id => text()();
  TextColumn get matchId => text()();

  /// 固定住民的 id；内置 AI 玩家和用户为空。
  TextColumn get residentId => text().withDefault(const Constant(''))();
  TextColumn get name => text()();
  IntColumn get seat => integer()();
  BoolColumn get isUser => boolean().withDefault(const Constant(false))();

  /// 是否还活着（狼人杀）。
  BoolColumn get alive => boolean().withDefault(const Constant(true))();

  /// werewolf / seer / witch / hunter / villager；其他游戏为空。
  TextColumn get role => text().withDefault(const Constant(''))();

  /// 头像引用，空则用名字生成。
  TextColumn get avatarAsset => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 对局的扩展状态（v50）。
///
/// 狼人杀和上传的声明式插件不适合塞进 `game_matches.board` 那种字符串棋盘，
/// 这里按 matchId 存一份 JSON：阶段、日志、夜晚行动、插件状态都在里面。
@DataClassName('GameStateRow')
class GameStates extends Table {
  TextColumn get matchId => text()();
  TextColumn get stateJson => text().withDefault(const Constant('{}'))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {matchId};
}

/// 用户从 GitHub 安装的声明式游戏插件（v50）。
///
/// 插件只是一份 JSON：工具、状态、规则都由数据描述，APP 不执行任何
/// 远程代码。`sourceUrl` 保留原始链接，方便用户重新拉取或删除。
@DataClassName('GamePluginRow')
@TableIndex(name: 'game_plugins_source', columns: {#sourceUrl})
class GamePlugins extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get sourceUrl => text()();
  TextColumn get manifestJson => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get minPlayers => integer().withDefault(const Constant(1))();
  IntColumn get maxPlayers => integer().withDefault(const Constant(1))();
  IntColumn get installedAt => integer()();
  IntColumn get updatedAt => integer()();

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
