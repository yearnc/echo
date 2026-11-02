import 'dart:convert';

import 'package:echo/domain/models/game_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const manifest = '''
{
  "schema": "echo.game.v1",
  "id": "word_duel",
  "name": "词语对决",
  "description": "猜一个词。",
  "min_players": 2,
  "max_players": 2,
  "initial_state": {"score": 0, "done": false, "log": []},
  "state_fields": [
    {"key": "score", "label": "得分", "type": "number"}
  ],
  "tools": [
    {
      "name": "guess",
      "description": "猜一次",
      "parameters": {
        "type": "object",
        "properties": {"word": {"type": "string"}},
        "required": ["word"]
      },
      "effects": [
        {"op": "append_log", "template": "你猜了 {word}"},
        {"op": "inc", "path": "score", "by": 1}
      ],
      "finish_when": {"path": "score", "op": "gte", "value": 2},
      "result": "猜对了"
    }
  ]
}
''';

  test('解析声明式插件并执行效果', () {
    final plugin = GamePlugin.parse(manifest, sourceUrl: 'https://example.test');
    expect(plugin.gameId, 'plugin:word_duel');
    expect(plugin.definition.maxPlayers, 2);
    final interpreter = PluginInterpreter(plugin);
    final state = interpreter.initialState;
    final tool = plugin.tools.single;
    expect(interpreter.available(tool, state), isTrue);

    final first = interpreter.apply(tool, {'word': '苹果'}, state);
    expect(first.ok, isTrue);
    expect(first.state['score'], 1);
    expect(first.finished, isFalse);
    expect((first.state['log'] as List).single, '你猜了 苹果');

    final second = interpreter.apply(tool, {'word': '香蕉'}, first.state);
    expect(second.state['score'], 2);
    expect(second.finished, isTrue);
    expect(second.result, '猜对了');
  });

  test('条件不满足时工具不可用', () {
    final plugin = GamePlugin.parse(
      manifest.replaceFirst(
        '"effects"',
        '"when": [{"path": "score", "op": "gte", "value": 5}], "effects"',
      ),
      sourceUrl: 'https://example.test',
    );
    final interpreter = PluginInterpreter(plugin);
    expect(interpreter.available(plugin.tools.single, interpreter.initialState),
        isFalse);
    final result = interpreter.apply(
      plugin.tools.single,
      {'word': '苹果'},
      interpreter.initialState,
    );
    expect(result.ok, isFalse);
  });

  test('拒绝不认识的 schema 和 id', () {
    expect(
      () => GamePlugin.parse('{"schema":"other"}', sourceUrl: 'x'),
      throwsFormatException,
    );
    final badId = manifest.replaceFirst('"word_duel"', '"Word Duel"');
    expect(
      () => GamePlugin.parse(badId, sourceUrl: 'x'),
      throwsFormatException,
    );
  });

  test('状态可以编码后还原', () {
    final plugin = GamePlugin.parse(manifest, sourceUrl: 'x');
    final interpreter = PluginInterpreter(plugin);
    final state = interpreter.initialState;
    final result = interpreter.apply(plugin.tools.single, {'word': '苹果'}, state);
    final decoded = jsonDecode(interpreter.encode(result.state));
    expect(decoded['score'], 1);
  });
}
