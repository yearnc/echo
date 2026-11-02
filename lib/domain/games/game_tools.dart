import 'game_registry.dart';

/// 住户能看到的游戏工具。
///
/// 基础工具只有「发现」和「邀请/回应」；具体走棋工具由
/// `list_game_tools` 返回后动态挂载，这样每个游戏可以有完全不同的参数，
/// 又不用把一整套工具常驻在每次唤醒里。
class GameTools {
  GameTools._();

  static const String listGameTools = 'list_game_tools';
  static const String inviteGame = 'invite_game';
  static const String respondInvite = 'respond_game_invite';
  static const String resign = 'game_resign';

  static Map<String, dynamic> get resignTool => {
    'type': 'function',
    'function': {
      'name': resign,
      'description': '认输并结束当前对局。',
      'parameters': {
        'type': 'object',
        'properties': {
          'match_id': {'type': 'string'},
        },
        'required': ['match_id'],
      },
    },
  };

  static List<Map<String, dynamic>> get baseTools => [
    {
      'type': 'function',
      'function': {
        'name': listGameTools,
        'description':
            '看看你现在在玩什么、有没有等你回应或轮到你的对局。'
            '走棋工具在每一轮都已经直接挂上了，这里只查状态，不用等下一次请求。',
        'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': inviteGame,
        'description': '邀请对方一起玩一局小游戏。对方接受后才会开局。',
        'parameters': {
          'type': 'object',
          'properties': {
            'game': {
              'type': 'string',
              'enum': [
                for (final game in GameRegistry.boardDefinitions) game.id,
              ],
              'description': '游戏 id（两人棋类；狼人杀由用户发起多人房间）',
            },
            'note': {'type': 'string', 'description': '想附带说的话，可空'},
          },
          'required': ['game'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': respondInvite,
        'description': '接受或拒绝一条还没处理的游戏邀请。',
        'parameters': {
          'type': 'object',
          'properties': {
            'invite_id': {'type': 'string'},
            'accept': {'type': 'boolean'},
            'note': {'type': 'string', 'description': '想回的一句话，可空'},
          },
          'required': ['invite_id', 'accept'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': resign,
        'description': '认输并结束当前对局。',
        'parameters': {
          'type': 'object',
          'properties': {
            'match_id': {'type': 'string'},
          },
          'required': ['match_id'],
        },
      },
    },
  ];

  static List<Map<String, dynamic>> skillToolsFor(Iterable<String> names) {
    final tools = <Map<String, dynamic>>[];
    for (final name in names) {
      final engine = GameRegistry.byToolName(name);
      if (engine != null) tools.add(engine.moveToolSchema);
    }
    return tools;
  }

  /// MCP 风格的“工具目录”（v50）。
  ///
  /// 以前模型要先调用 `list_game_tools`，下一次请求才拿得到走棋工具；
  /// 现在所有内置走棋工具在每轮唤醒时直接挂上，和 MCP 的 tools/list
  /// 在请求前就能拿到工具清单是一回事。插件工具由 GameService 追加。
  static List<Map<String, dynamic>> get allBuiltinTools => [
    ...baseTools,
    for (final engine in GameRegistry.all) engine.moveToolSchema,
  ];
}
