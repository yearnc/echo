import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game.dart';
import 'game_engine.dart';
import 'gomoku_engine.dart';
import 'xiangqi_engine.dart';

/// 游戏注册表：加新游戏只需要在这里多一行。
class GameRegistry {
  GameRegistry._();

  static final Map<String, GameEngine> _engines = {
    for (final engine in const <GameEngine>[GomokuEngine(), XiangqiEngine()])
      engine.definition.id: engine,
  };

  static List<GameEngine> get all => _engines.values.toList(growable: false);

  /// 内置游戏定义：两人棋类 + 狼人杀。
  ///
  /// 狼人杀没有棋盘引擎，走自己的 `WerewolfService`；但它仍然属于
  /// “内置游戏”，邀请页、日志和记忆都按同一套游戏元数据展示。
  static const GameDefinition werewolf = GameDefinition(
    id: 'werewolf',
    name: '狼人杀',
    description: '9 人局：狼人、预言家、女巫、猎人和村民。你和固定住民同场。',
    minPlayers: 9,
    maxPlayers: 9,
  );

  static List<GameDefinition> get definitions => [
    for (final engine in _engines.values) engine.definition,
    werewolf,
  ];

  static List<GameDefinition> get boardDefinitions => [
    for (final engine in _engines.values) engine.definition,
  ];

  static GameEngine? byId(String id) => _engines[id];

  static GameDefinition? definitionById(String id) {
    for (final definition in definitions) {
      if (definition.id == id) return definition;
    }
    if (id.startsWith('plugin:')) {
      return null; // 插件定义由 GamePluginRepository 提供。
    }
    return null;
  }

  static GameEngine? byToolName(String toolName) {
    for (final engine in _engines.values) {
      if (engine.moveToolName == toolName) return engine;
    }
    return null;
  }
}

final gameRegistryProvider = Provider<GameRegistry>((ref) => GameRegistry._());
