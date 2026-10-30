import 'package:echo/domain/services/resident_tool_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模型把参数类型写错时，工具层不能跟着崩。
/// 这些值都是真实模型见过的形状：数字当字符串、字符串当布尔、null。
void main() {
  test('文本参数：数字转成字符串，缺省用 fallback', () {
    expect(ResidentToolSession.textArg({'content': 123}, 'content'), '123');
    expect(ResidentToolSession.textArg({'content': true}, 'content'), 'true');
    expect(
      ResidentToolSession.textArg({}, 'content', fallback: '他刚说的'),
      '他刚说的',
    );
  });

  test('布尔参数：认 true/false、1/0 和字符串', () {
    expect(ResidentToolSession.flagArg({'as_voice': true}, 'as_voice'), isTrue);
    expect(ResidentToolSession.flagArg({'as_voice': 1}, 'as_voice'), isTrue);
    expect(
      ResidentToolSession.flagArg({'as_voice': 'true'}, 'as_voice'),
      isTrue,
    );
    expect(
      ResidentToolSession.flagArg({'as_voice': 'false'}, 'as_voice'),
      isFalse,
    );
    expect(
      ResidentToolSession.flagArg({'as_voice': '乱写'}, 'as_voice'),
      isFalse,
    );
    expect(
      ResidentToolSession.flagArg({}, 'include_comments', fallback: true),
      isTrue,
    );
  });

  test('数字参数：字符串里的整数也认', () {
    expect(ResidentToolSession.intArg({'days': 3}, 'days'), 3);
    expect(ResidentToolSession.intArg({'days': '3'}, 'days'), 3);
    expect(ResidentToolSession.intArg({'days': '三天'}, 'days'), isNull);
  });

  test('可选文本：空白等于没给', () {
    expect(
      ResidentToolSession.optionalTextArg({'topic': '  '}, 'topic'),
      isNull,
    );
    expect(
      ResidentToolSession.optionalTextArg({'topic': ' 深夜 '}, 'topic'),
      '深夜',
    );
  });
}
