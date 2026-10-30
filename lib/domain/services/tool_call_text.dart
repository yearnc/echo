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

/// 模型把历史里的时间前缀抄进正文时，开头的这一层要剥掉。
///
/// 三种都认：完整格式（`[2026年10月28日 周三 中午 12:44]`）、
/// 旧时间线的短格式（`[10月30日 21:32]`）、屏幕观察的纯时刻（`[21:32]`）。
/// 历史里带时间前缀是为了让住民知道消息是什么时候发的，不是为了教它
/// 在每次说话前盖个戳；2026-10-30 真机就是短格式没被认出来，
/// 模型把「[10月30日 21:32] 你：…」原样发进了私信。
final RegExp _leadingTimeLabel = RegExp(
  r'^\[\s*(?:\d{4}年\s*)?\d{1,2}月\d{1,2}日\s*'
  r'(?:周[一二三四五六日天]\s*)?'
  r'(?:(?:清晨|上午|中午|下午|傍晚|晚上|深夜)\s*)?'
  r'\d{1,2}:\d{2}\s*\]\s*',
);

/// 只有时刻的旧前缀（`[21:32]`）。
final RegExp _leadingClock = RegExp(r'^\[\s*\d{1,2}:\d{2}\s*\]\s*');

/// 对话记录里的人称前缀（`你：` / `对方：`）。
final RegExp _leadingSpeaker = RegExp(r'^(?:你|对方)\s*[：:]\s*');

/// 只剥时间前缀，不动人称——清洗旧记录时，用户那侧的“对方：”要留着。
String stripTimePrefixes(String raw) {
  var text = raw.trim();
  for (var i = 0; i < 4; i++) {
    final before = text;
    text = text
        .replaceFirst(_leadingTimeLabel, '')
        .replaceFirst(_leadingClock, '')
        .trim();
    if (text == before) break;
  }
  return text;
}

String stripLeadingTimeLabel(String raw) {
  var text = raw.trim();
  // 前缀可能叠着出现（时间 + 人称），一次剥一层、剥干净为止。
  for (var i = 0; i < 4; i++) {
    final before = text;
    text = text
        .replaceFirst(_leadingTimeLabel, '')
        .replaceFirst(_leadingClock, '')
        .replaceFirst(_leadingSpeaker, '')
        .trim();
    if (text == before) break;
  }
  return text;
}

/// 私信正文可能一次抄回好几行历史记录（每行都带 `[时间] 你：`）。
/// 逐行洗掉记录前缀、丢掉空行；正文中间的时间照旧不动。
///
/// [stripSpeaker] 只在模型要说的话上用；清洗历史记录时要按 role 区分，
/// 用户那侧的“对方：”是记录的一部分，不能剥。
String sanitizeMessageBody(String raw, {bool stripSpeaker = true}) {
  final source = hasToolCallMarkup(raw) ? sanitizeModelText(raw) : raw;
  final kept = <String>[];
  for (final line in source.split('\n')) {
    var clean = stripTimePrefixes(line);
    if (stripSpeaker) {
      clean = clean.replaceFirst(_leadingSpeaker, '').trim();
    }
    if (clean.isNotEmpty) kept.add(clean);
  }
  return kept.join('\n').trim();
}

/// 把模型文本里的工具调用标记洗掉，只留真正说的话。
///
/// 清洗后可能什么都不剩（模型这一轮只是在调工具），返回空串，
/// 调用方就知道“他没说话”。
String sanitizeModelText(String raw) {
  var text = raw;
  if (hasToolCallMarkup(text)) {
    text = text.replaceAll(_toolCallsBlock, ' ');
    // 没有 `<tool_calls>` 外壳时，逐段去掉 invoke 块。
    text = text.replaceAll(_invoke, ' ');
    // 兜底：没配对的半个标签、孤立的标记都清掉。
    text = text.replaceAll(_tag, ' ');
    text = text.replaceAll(_marker, ' ');
    text = text.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }
  return stripLeadingTimeLabel(text);
}
