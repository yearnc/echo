import 'package:echo/domain/services/resident_context_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// 桌宠和私信共用一段短期上下文，但必须按住民分开——
/// 换控制者时，上一位看到的屏幕不能漏给下一位。
void main() {
  test('按住民分开存，互不串味', () {
    final log = ResidentContextLog();
    log.add('a', 'a 看到编辑器');
    log.add('b', 'b 看到浏览器');

    expect(log.recent('a'), ['a 看到编辑器']);
    expect(log.recent('b'), ['b 看到浏览器']);
    expect(log.recent('c'), isEmpty);
  });

  test('只留最近若干条', () {
    final log = ResidentContextLog();
    for (var i = 0; i < ResidentContextLog.maxLines + 3; i++) {
      log.add('a', '第 $i 条');
    }
    final lines = log.recent('a');
    expect(lines.length, ResidentContextLog.maxLines);
    expect(lines.first, '第 3 条');
    expect(lines.last, '第 ${ResidentContextLog.maxLines + 2} 条');
    expect(log.recent('a', limit: 2), [
      '第 ${ResidentContextLog.maxLines + 1} 条',
      '第 ${ResidentContextLog.maxLines + 2} 条',
    ]);
  });

  test('空白不占位置，clear 只清一个人', () {
    final log = ResidentContextLog();
    log.add('a', '   ');
    log.add('a', '一句');
    log.add('b', '另一句');

    expect(log.recent('a'), ['一句']);
    log.clear('a');
    expect(log.recent('a'), isEmpty);
    expect(log.recent('b'), ['另一句']);
  });
}
