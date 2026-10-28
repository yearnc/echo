import 'package:echo/data/repositories/resident_alarm_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('闹钟时间解析', () {
    final now = DateTime(2026, 10, 28, 12, 30);

    test('分钟数按相对时间算', () {
      expect(parseAlarmWhen('90', now: now), DateTime(2026, 10, 28, 14, 0));
      expect(parseAlarmWhen('2h', now: now), DateTime(2026, 10, 28, 14, 30));
      expect(parseAlarmWhen('45m', now: now), DateTime(2026, 10, 28, 13, 15));
    });

    test('HH:mm 今天还没过就是今天，过了就顺延到明天', () {
      expect(parseAlarmWhen('21:30', now: now), DateTime(2026, 10, 28, 21, 30));
      expect(parseAlarmWhen('08:00', now: now), DateTime(2026, 10, 29, 8, 0));
    });

    test('完整日期时间', () {
      expect(
        parseAlarmWhen('2026-10-29 08:00', now: now),
        DateTime(2026, 10, 29, 8, 0),
      );
      expect(
        parseAlarmWhen('2026-10-29T08:00', now: now),
        DateTime(2026, 10, 29, 8, 0),
      );
    });

    test('太近、太远、看不懂都返回 null', () {
      expect(parseAlarmWhen('1', now: now), isNull, reason: '最短 5 分钟');
      expect(parseAlarmWhen('40d', now: now), isNull, reason: '只认 m/h');
      expect(parseAlarmWhen('31d', now: now), isNull);
      expect(parseAlarmWhen('25:99', now: now), isNull);
      expect(parseAlarmWhen('2026-13-01 08:00', now: now), isNull);
      expect(parseAlarmWhen('晚点吧', now: now), isNull);
      expect(parseAlarmWhen('', now: now), isNull);
    });

    test('超过 30 天的绝对时间不接受', () {
      expect(parseAlarmWhen('2026-12-01 08:00', now: now), isNull);
    });
  });
}
