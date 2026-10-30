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

  test('开头的时间标记会被剥干净，叠几层都不留', () {
    const label = '[2026年10月28日 周三 中午 12:44] ';
    expect(
      sanitizeModelText('$label行吧，别磨蹭到天黑。'),
      '行吧，别磨蹭到天黑。',
    );
    expect(sanitizeModelText('$label$label行吧。'), '行吧。');
  });

  test('旧时间线的短格式和人称前缀也会被剥掉', () {
    const short = '[10月30日 21:32] ';
    expect(
      sanitizeModelText('$short你：没找到也正常。'),
      '没找到也正常。',
    );
    expect(
      sanitizeModelText('$short对方：那你复习了吗？'),
      '那你复习了吗？',
    );
    expect(sanitizeModelText('[21:32] 你看了屏幕：编辑器'), '你看了屏幕：编辑器');
  });

  test('模型一次抄回多条记录时，逐行洗掉前缀', () {
    const raw = '[10月30日 21:32] 你：没找到也正常。\n'
        '[10月30日 21:32] 你：复习了一遍也算数。';
    expect(
      sanitizeMessageBody(raw),
      '没找到也正常。\n复习了一遍也算数。',
    );
    expect(sanitizeMessageBody('在呢，你吃了吗？'), '在呢，你吃了吗？');
  });

  test('句子中间的时间不误伤', () {
    expect(
      sanitizeModelText('12:44 了，你吃饭没有？'),
      '12:44 了，你吃饭没有？',
    );
    expect(
      sanitizeModelText('明天中午再说吧'),
      '明天中午再说吧',
    );
    // 不是完整格式（少了周几/时段），不当成系统时间标记。
    expect(
      sanitizeModelText('[2026年10月28日] 那天我在郑州。'),
      '[2026年10月28日] 那天我在郑州。',
    );
  });
}
