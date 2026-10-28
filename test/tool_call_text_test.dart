import 'package:echo/domain/services/tool_call_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// DeepSeek 的文本式工具调用。真机上它被当成普通回复发进私信过，
/// 所以这里既验解析，也验“洗掉之后不许留下任何标记”。
const String _dsml = '''
<｜｜DSML｜｜tool_calls>
<｜｜DSML｜｜invoke name="send_dm">
<｜｜DSML｜｜parameter name="content" string="true">十二点了。起来没，还是躺了一上午？</｜｜DSML｜｜parameter>
</｜｜DSML｜｜invoke>
</｜｜DSML｜｜tool_calls>''';

void main() {
  test('能认出 DSML 标记', () {
    expect(hasToolCallMarkup(_dsml), isTrue);
    expect(hasToolCallMarkup('普通的一句话'), isFalse);
  });

  test('把文本调用解析成工具名和参数', () {
    final calls = parseTextToolCalls(_dsml);
    expect(calls, hasLength(1));
    expect(calls.single.name, 'send_dm');
    expect(
      calls.single.arguments['content'],
      '十二点了。起来没，还是躺了一上午？',
    );
  });

  test('一次可以解析多个调用', () {
    const raw = '''
<｜｜DSML｜｜tool_calls>
<｜｜DSML｜｜invoke name="memory_search">
<｜｜DSML｜｜parameter name="query" string="true">考试</｜｜DSML｜｜parameter>
<｜｜DSML｜｜parameter name="limit" string="false">3</｜｜DSML｜｜parameter>
</｜｜DSML｜｜invoke>
<｜｜DSML｜｜invoke name="list_tools">
</｜｜DSML｜｜invoke>
</｜｜DSML｜｜tool_calls>''';
    final calls = parseTextToolCalls(raw);
    expect(calls.map((call) => call.name), ['memory_search', 'list_tools']);
    expect(calls.first.arguments['query'], '考试');
    expect(calls.first.arguments['limit'], 3);
  });

  test('ASCII 竖线也认', () {
    const raw =
        '<||DSML||tool_calls><||DSML||invoke name="finish"></||DSML||invoke>'
        '</||DSML||tool_calls>';
    expect(parseTextToolCalls(raw).single.name, 'finish');
  });

  test('洗掉标记后只留下模型真正说的话', () {
    const raw = '我先看看。'
        '\n$_dsml\n'
        '（标记后面的话）';
    final clean = sanitizeModelText(raw);
    expect(clean, isNot(contains('DSML')));
    expect(clean, contains('我先看看。'));
    expect(clean, contains('（标记后面的话）'));
  });

  test('只有调用、没有说话时洗成空串', () {
    expect(sanitizeModelText(_dsml), isEmpty);
    expect(sanitizeModelText('  <｜｜DSML｜｜invoke name="x">  '), isEmpty);
  });

  test('普通文本原样返回（去掉首尾空白）', () {
    expect(sanitizeModelText('  在呢，你吃了吗？ '), '在呢，你吃了吗？');
  });
}
