import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game.dart';
import 'game_engine.dart';
import 'gomoku_engine.dart';
import 'xiangqi_engine.dart';

/// 游戏注册表：加新游戏只需要在这里多一行。
class GameRegistry {
  GameRegistry._();

  static final Map<String, GameEngine> _engines = {
    for (final engine in const <GameEngine>[
      GomokuEngine(),
      XiangqiEngine(),
    ])
      engine.definition.id: engine,
  };

  static List<GameEngine> get all => _engines.values.toList(growable: false);

  static List<GameDefinition> get definitions =>
      [for (final engine in _engines.values) engine.definition];

  static GameEngine? byId(String id) => _engines[id];

  static GameEngine? byToolName(String toolName) {
    for (final engine in _engines.values) {
      if (engine.moveToolName == toolName) return engine;
    }
    return null;
  }
}

final gameRegistryProvider = Provider<GameRegistry>(
  (ref) => GameRegistry._(),
);
