import 'dart:convert';

/// 文本形态的工具调用（v3.10）。
///
/// DeepSeek 系模型的原生工具调用文本长这样：
///
/// ```
/// <｜｜DSML｜｜tool_calls>
/// <｜｜DSML｜｜invoke name="send_dm">
/// <｜｜DSML｜｜parameter name="content" string="true">十二点了，起来没？</｜｜DSML｜｜parameter>
/// </｜｜DSML｜｜invoke>
/// </｜｜DSML｜｜tool_calls>
/// ```
///
/// 正常情况下服务商把它解析进 `tool_calls` 字段；但有些模型/中转会把整段
/// 原样塞进 `content`。这时如果只看到“有内容”，就会把这段标记当成人说的话
/// ——私信里出现一坨 `<｜｜DSML｜｜...>` 就是这么来的。
///
/// 这里做两件事：把文本还原成真正的调用；把剩下的标记洗掉。
class ParsedTextToolCall {
  const ParsedTextToolCall({required this.name, required this.arguments});

  final String name;
  final Map<String, dynamic> arguments;
}

/// `｜`（全角）和 `|` 都见过，两种都认。
const String _bar = r'[｜|]';

final RegExp _marker = RegExp('</?$_bar{2}DSML$_bar{2}');

/// 半个标签（没有配对闭标签时）也要整段去掉：
/// `<｜｜DSML｜｜invoke name="x">`、`</｜｜DSML｜｜parameter>`。
final RegExp _tag = RegExp('</?$_bar{2}DSML$_bar{2}[^<>]*>');

final RegExp _invoke = RegExp(
  '<$_bar{2}DSML$_bar{2}invoke\\s+name="([^"]*)"\\s*>'
  '([\\s\\S]*?)'
  '</$_bar{2}DSML$_bar{2}invoke>',
);

final RegExp _parameter = RegExp(
  '<$_bar{2}DSML$_bar{2}parameter\\s+name="([^"]*)"'
  '(?:\\s+string="(true|false)")?\\s*>'
  '([\\s\\S]*?)'
  '</$_bar{2}DSML$_bar{2}parameter>',
);

/// 整段 `tool_calls` 块：从开标签一直到闭标签，连里面的内容一起丢掉。
final RegExp _toolCallsBlock = RegExp(
  '<$_bar{2}DSML$_bar{2}tool_calls>[\\s\\S]*?'
  '</$_bar{2}DSML$_bar{2}tool_calls>',
);

/// 这个文本里有没有工具调用标记。
bool hasToolCallMarkup(String text) => _marker.hasMatch(text);

/// 把文本形态的工具调用解析出来。解析不出来就返回空数组。
List<ParsedTextToolCall> parseTextToolCalls(String raw) {
  if (!hasToolCallMarkup(raw)) return const [];
  final calls = <ParsedTextToolCall>[];
  for (final match in _invoke.allMatches(raw)) {
    final name = (match.group(1) ?? '').trim();
    if (name.isEmpty) continue;
    calls.add(
      ParsedTextToolCall(
        name: name,
        arguments: _parseParameters(match.group(2) ?? ''),
      ),
    );
  }
  return calls;
}

Map<String, dynamic> _parseParameters(String block) {
  final arguments = <String, dynamic>{};
  for (final match in _parameter.allMatches(block)) {
    final key = (match.group(1) ?? '').trim();
    if (key.isEmpty) continue;
    final isString = match.group(2) == 'true';
    final value = _unwrap(match.group(3) ?? '');
    arguments[key] = isString ? value : _typed(value);
  }
  return arguments;
}

/// 参数值里偶尔被模型加上首尾换行/缩进，去掉外面的空白，保留内容本身。
String _unwrap(String raw) {
  var text = raw;
  if (text.startsWith('\n')) text = text.substring(1);
  if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
  return text;
}

/// `string="false"` 的参数按 JSON 解；解不出来就当字符串。
Object? _typed(String raw) {
  final text = raw.trim();
  try {
    return jsonDecode(text);
  } catch (_) {
    return text;
  }
}

/// 把模型文本里的工具调用标记洗掉，只留真正说的话。
///
/// 清洗后可能什么都不剩（模型这一轮只是在调工具），返回空串，
/// 调用方就知道“他没说话”。
String sanitizeModelText(String raw) {
  if (!hasToolCallMarkup(raw)) return raw.trim();
  var text = raw.replaceAll(_toolCallsBlock, ' ');
  // 没有 `<tool_calls>` 外壳时，逐段去掉 invoke 块。
  text = text.replaceAll(_invoke, ' ');
  // 兜底：没配对的半个标签、孤立的标记都清掉。
  text = text.replaceAll(_tag, ' ');
  text = text.replaceAll(_marker, ' ');
  text = text.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}
