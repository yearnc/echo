import 'package:echo/domain/services/community_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

/// 这是"大家共同经历的那点事"，不是某个群体的日程表——
/// 所以这里连一条"开学""考试周"都不该有。
void main() {
  test('冬天说冷，夏天说热，春秋不念叨天气', () {
    expect(
      CommunityCalendar.of(DateTime(2026, 12, 10)).map((event) => event.title),
      contains('降温'),
    );
    expect(
      CommunityCalendar.of(DateTime(2026, 7, 8)).map((event) => event.title),
      contains('高温'),
    );
    expect(
      CommunityCalendar.of(DateTime(2026, 4, 8)).map((event) => event.title),
      isEmpty,
      reason: '四月的一个普通周三，没什么可说的——这才是多数日子的样子',
    );
  });

  test('周末排在天气前面：今天能不能歇，比刮什么风更值得说', () {
    // 2026-12-12 是周六
    final events = CommunityCalendar.of(DateTime(2026, 12, 12));

    expect(events.map((event) => event.title), ['周末', '降温']);
  });

  test('节日排在最前，因为那天大家说的都是这件事', () {
    final events = CommunityCalendar.of(DateTime(2026, 10, 2));

    expect(events.first.title, '国庆');
  });

  test('元旦只算头三天', () {
    expect(CommunityCalendar.of(DateTime(2026, 1, 2)).first.title, '元旦');
    expect(
      CommunityCalendar.of(DateTime(2026, 1, 20)).map((event) => event.title),
      isNot(contains('元旦')),
    );
  });

  test('社区里没有"某个群体的日程"', () {
    // 一月上旬：不放假的普通工作日，只有天气
    expect(
      CommunityCalendar.of(DateTime(2026, 1, 8)).map((event) => event.title),
      ['降温'],
    );
    // 九月开头的周三也不该有什么特别
    expect(
      CommunityCalendar.of(DateTime(2026, 9, 2)),
      isEmpty,
    );
  });

  test('最值得一提的那一件：有节日先报节日', () {
    expect(CommunityCalendar.strongestAt(DateTime(2026, 10, 1))!.title, '国庆');
    expect(CommunityCalendar.strongestAt(DateTime(2026, 4, 8)), isNull);
  });

  test('每件事都给模型留了话说，也给样本留了台词', () {
    for (final date in [
      DateTime(2026, 12, 12),
      DateTime(2026, 7, 8),
      DateTime(2026, 10, 2),
    ]) {
      for (final event in CommunityCalendar.of(date)) {
        expect(event.hint, isNotEmpty);
        expect(event.samples, isNotEmpty);
      }
    }
  });
}
