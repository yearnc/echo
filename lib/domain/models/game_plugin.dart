import 'dart:convert';

import 'game.dart';

/// 用户上传的声明式游戏插件（v50）。
///
/// 插件只是一份 JSON：不执行任何远程代码，也不下载可执行文件。
/// APP 用这里的解释器读取状态、执行工具、判定胜负。这样国内网络下
/// 也能只靠一次 JSON 下载把游戏“装”进本地，之后离线可玩。
class GamePlugin {
  const GamePlugin({
    required this.id,
    required this.name,
    required this.description,
    required this.sourceUrl,
    required this.minPlayers,
    required this.maxPlayers,
    required this.initialState,
    required this.tools,
    required this.stateFields,
    required this.manifestJson,
    this.enabled = true,
  });

  /// 插件 id，会加 `plugin:` 前缀成为游戏 id。
  final String id;
  final String name;
  final String description;
  final String sourceUrl;
  final int minPlayers;
  final int maxPlayers;
  final Map<String, dynamic> initialState;
  final List<PluginTool> tools;
  final List<PluginStateField> stateFields;

  /// 原始清单，存库；重新拉取时比对用。
  final String manifestJson;
  final bool enabled;

  String get gameId => 'plugin:$id';

  GameDefinition get definition => GameDefinition(
    id: gameId,
    name: name,
    description: description,
    minPlayers: minPlayers,
    maxPlayers: maxPlayers,
    plugin: true,
  );

  static GamePlugin parse(String raw, {required String sourceUrl}) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('插件清单必须是一个 JSON 对象');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['schema'] != 'echo.game.v1') {
      throw const FormatException('不认识的插件格式，需要 schema = "echo.game.v1"');
    }
    final id = _text(map['id']);
    if (!RegExp(r'^[a-z][a-z0-9_]{2,31}$').hasMatch(id)) {
      throw const FormatException(
        'id 只能用小写字母、数字和下划线，3—32 个字符，且以字母开头',
      );
    }
    final name = _text(map['name']);
    if (name.isEmpty || name.length > 40) {
      throw const FormatException('name 不能为空，最多 40 个字');
    }
    final minPlayers = _int(map['min_players'], fallback: 1).clamp(1, 9);
    final maxPlayers = _int(map['max_players'], fallback: 1).clamp(
      minPlayers,
      9,
    );
    final initial = map['initial_state'];
    if (initial is! Map) {
      throw const FormatException('initial_state 必须是一个对象');
    }
    final rawTools = map['tools'];
    if (rawTools is! List || rawTools.isEmpty || rawTools.length > 30) {
      throw const FormatException('tools 需要有 1—30 个工具');
    }
    final tools = <PluginTool>[];
    final seen = <String>{};
    for (final item in rawTools) {
      if (item is! Map) throw const FormatException('tools 里每一项都必须是对象');
      final tool = PluginTool.parse(Map<String, dynamic>.from(item));
      if (!seen.add(tool.name)) {
        throw FormatException('工具名重复：${tool.name}');
      }
      // 模型侧工具名会变成 echo_<插件id>_<工具名>，OpenAI 兼容接口
      // 一般限制 64 个字符；太长会被服务商拒绝。
      if ('echo_${id}_${tool.name}'.length > 64) {
        throw FormatException(
          '插件 id 和工具名 $tool.name 拼起来太长（超过 64 字符），'
          '请缩短其中一个',
        );
      }
      tools.add(tool);
    }
    final fields = <PluginStateField>[];
    final rawFields = map['state_fields'];
    if (rawFields is List) {
      for (final item in rawFields) {
        if (item is Map) {
          final field = PluginStateField.parse(Map<String, dynamic>.from(item));
          if (field.key.isNotEmpty) fields.add(field);
        }
      }
    }
    return GamePlugin(
      id: id,
      name: name,
      description: _text(map['description']),
      sourceUrl: sourceUrl,
      minPlayers: minPlayers,
      maxPlayers: maxPlayers,
      initialState: Map<String, dynamic>.from(initial),
      tools: tools,
      stateFields: fields,
      manifestJson: raw,
    );
  }

  static String _text(Object? value) => value is String ? value.trim() : '';

  static int _int(Object? value, {required int fallback}) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }
}

class PluginStateField {
  const PluginStateField({
    required this.key,
    required this.label,
    this.kind = 'text',
  });

  final String key;
  final String label;

  /// text / number / bool
  final String kind;

  static PluginStateField parse(Map<String, dynamic> map) => PluginStateField(
    key: GamePlugin._text(map['key']),
    label: GamePlugin._text(map['label']),
    kind: switch (GamePlugin._text(map['type'])) {
      'number' => 'number',
      'bool' => 'bool',
      _ => 'text',
    },
  );
}

class PluginTool {
  const PluginTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.effects,
    this.when = const [],
    this.finishWhen,
    this.result = '',
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final List<PluginEffect> effects;

  /// 不满足条件时，这个工具不出现在目录里，也不允许执行。
  final List<PluginCondition> when;

  /// 执行完这一步后如果满足，整局结束。
  final PluginCondition? finishWhen;
  final String result;

  /// 给模型看的工具名：加插件前缀，避免和内置工具重名。
  String toolName(String pluginId) => 'echo_${pluginId}_$name';

  static PluginTool parse(Map<String, dynamic> map) {
    final name = GamePlugin._text(map['name']);
    if (!RegExp(r'^[a-z][a-z0-9_]{1,31}$').hasMatch(name)) {
      throw FormatException(
        '工具名 "$name" 不合法：小写字母开头，2—32 个字符',
      );
    }
    final rawParams = map['parameters'];
    final params = rawParams is Map
        ? Map<String, dynamic>.from(rawParams)
        : <String, dynamic>{'type': 'object', 'properties': <String, dynamic>{}};
    final rawEffects = map['effects'];
    if (rawEffects is! List || rawEffects.isEmpty) {
      throw FormatException('工具 $name 至少需要一个 effect');
    }
    final effects = [
      for (final item in rawEffects)
        if (item is Map)
          PluginEffect.parse(Map<String, dynamic>.from(item)),
    ];
    final rawWhen = map['when'];
    final when = rawWhen is List
        ? [
            for (final item in rawWhen)
              if (item is Map)
                PluginCondition.parse(Map<String, dynamic>.from(item)),
          ]
        : const <PluginCondition>[];
    final rawFinish = map['finish_when'];
    final finishWhen = rawFinish is Map
        ? PluginCondition.parse(Map<String, dynamic>.from(rawFinish))
        : null;
    return PluginTool(
      name: name,
      description: GamePlugin._text(map['description']),
      parameters: params,
      effects: effects,
      when: when,
      finishWhen: finishWhen,
      result: GamePlugin._text(map['result']),
    );
  }
}

class PluginEffect {
  const PluginEffect({
    required this.op,
    this.path = '',
    this.value,
    this.by = 0,
    this.template = '',
  });

  /// set / inc / append_log / set_result
  final String op;
  final String path;
  final Object? value;
  final int by;
  final String template;

  static PluginEffect parse(Map<String, dynamic> map) {
    final op = GamePlugin._text(map['op']);
    if (!const {'set', 'inc', 'append_log', 'set_result'}.contains(op)) {
      throw FormatException('不支持的 effect：$op');
    }
    return PluginEffect(
      op: op,
      path: GamePlugin._text(map['path']),
      value: map['value'],
      by: map['by'] is num ? (map['by'] as num).toInt() : 0,
      template: GamePlugin._text(map['template']),
    );
  }
}

class PluginCondition {
  const PluginCondition({
    required this.path,
    required this.op,
    required this.value,
  });

  final String path;

  /// eq / neq / gte / lte / truthy / falsy
  final String op;
  final Object? value;

  static PluginCondition parse(Map<String, dynamic> map) {
    final op = GamePlugin._text(map['op']);
    if (!const {'eq', 'neq', 'gte', 'lte', 'truthy', 'falsy'}.contains(op)) {
      throw FormatException('不支持的条件：$op');
    }
    return PluginCondition(
      path: GamePlugin._text(map['path']),
      op: op,
      value: map['value'],
    );
  }
}

/// 插件的一次执行结果。
class PluginApplyResult {
  const PluginApplyResult({
    required this.ok,
    required this.message,
    required this.state,
    this.finished = false,
    this.result = '',
  });

  final bool ok;
  final String message;
  final Map<String, dynamic> state;
  final bool finished;
  final String result;
}

/// 声明式插件的解释器。
class PluginInterpreter {
  const PluginInterpreter(this.plugin);

  final GamePlugin plugin;

  Map<String, dynamic> get initialState => _deepCopy(plugin.initialState);

  Map<String, dynamic> restore(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // 损坏的存档从初始状态重新开始。
    }
    return initialState;
  }

  String encode(Map<String, dynamic> state) => jsonEncode(state);

  /// 工具当前是否可用（用于目录和用户按钮）。
  bool available(PluginTool tool, Map<String, dynamic> state) =>
      tool.when.every((condition) => _check(condition, state));

  /// 把当前状态渲染成几行给人看的文字。
  List<String> describe(Map<String, dynamic> state) {
    final lines = <String>[];
    for (final field in plugin.stateFields) {
      final value = _readPath(state, field.key);
      if (value == null) continue;
      lines.add('${field.label.isEmpty ? field.key : field.label}：$value');
    }
    final log = state['log'];
    if (log is List) {
      for (final item in log.reversed.take(6).toList().reversed) {
        if (item is String && item.trim().isNotEmpty) lines.add(item);
      }
    }
    return lines;
  }

  /// 执行一个工具。args 来自用户或模型。
  PluginApplyResult apply(
    PluginTool tool,
    Map<String, Object?> args,
    Map<String, dynamic> state,
  ) {
    if (!available(tool, state)) {
      return PluginApplyResult(
        ok: false,
        message: '现在还不能这样做',
        state: state,
      );
    }
    var next = _deepCopy(state);
    final log = <String>[];
    for (final effect in tool.effects) {
      switch (effect.op) {
        case 'set':
          _writePath(
            next,
            effect.path,
            _resolveValue(effect.value, args, next),
          );
        case 'inc':
          final current = _readPath(next, effect.path);
          final base = current is num ? current.toInt() : 0;
          _writePath(next, effect.path, base + effect.by);
        case 'append_log':
          final line = _render(effect.template, args, next);
          if (line.trim().isNotEmpty) log.add(line.trim());
        case 'set_result':
          next['_result'] = _render(effect.template, args, next);
      }
    }
    if (log.isNotEmpty) {
      final existing = next['log'];
      final lines = existing is List
          ? List<Object?>.from(existing)
          : <Object?>[];
      lines.addAll(log);
      next['log'] = lines;
    }
    final finished =
        tool.finishWhen != null && _check(tool.finishWhen!, next);
    final result = tool.result.isNotEmpty
        ? tool.result
        : (next['_result'] is String ? next['_result'] as String : '');
    return PluginApplyResult(
      ok: true,
      message: log.isEmpty ? '这一步完成了' : log.last,
      state: next,
      finished: finished,
      result: result,
    );
  }

  bool _check(PluginCondition condition, Map<String, dynamic> state) {
    final actual = _readPath(state, condition.path);
    switch (condition.op) {
      case 'eq':
        return '$actual' == '${condition.value}';
      case 'neq':
        return '$actual' != '${condition.value}';
      case 'gte':
        return _number(actual) >= _number(condition.value);
      case 'lte':
        return _number(actual) <= _number(condition.value);
      case 'truthy':
        return actual != null && actual != false && actual != 0 && actual != '';
      case 'falsy':
        return actual == null || actual == false || actual == 0 || actual == '';
    }
    return false;
  }

  static double _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }

  Object? _resolveValue(
    Object? value,
    Map<String, Object?> args,
    Map<String, dynamic> state,
  ) {
    if (value is String) return _render(value, args, state);
    return value;
  }

  /// 模板只支持两种占位：`{参数名}` 和 `{state.路径}`。
  String _render(
    String template,
    Map<String, Object?> args,
    Map<String, dynamic> state,
  ) {
    return template.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (match) {
      final key = match.group(1)!.trim();
      if (key.startsWith('state.')) {
        final value = _readPath(state, key.substring(6));
        return value == null ? '' : '$value';
      }
      final value = args[key];
      return value == null ? '' : '$value';
    });
  }

  static Object? _readPath(Map<String, dynamic> state, String path) {
    if (path.isEmpty) return null;
    Object? current = state;
    for (final part in path.split('.')) {
      if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  static void _writePath(
    Map<String, dynamic> state,
    String path,
    Object? value,
  ) {
    if (path.isEmpty) return;
    final parts = path.split('.');
    var current = state;
    for (var i = 0; i < parts.length - 1; i++) {
      final next = current[parts[i]];
      if (next is Map) {
        current = Map<String, dynamic>.from(next);
        state[parts[i]] = current;
      } else {
        final created = <String, dynamic>{};
        current[parts[i]] = created;
        current = created;
      }
    }
    current[parts.last] = value;
  }

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> source) {
    return jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  }
}
