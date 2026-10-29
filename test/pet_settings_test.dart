import 'package:echo/domain/models/pet_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('桌宠时段', () {
    const day = PetShift(
      id: 'a',
      residentId: 'r1',
      startMinute: 8 * 60,
      endMinute: 22 * 60,
    );
    const night = PetShift(
      id: 'b',
      residentId: 'r2',
      startMinute: 22 * 60,
      endMinute: 6 * 60,
    );

    test('普通时段：含开始、不含结束', () {
      expect(day.covers(8 * 60), isTrue);
      expect(day.covers(12 * 60), isTrue);
      expect(day.covers(22 * 60 - 1), isTrue);
      expect(day.covers(22 * 60), isFalse);
      expect(day.covers(7 * 60 + 59), isFalse);
    });

    test('跨零点：晚上和凌晨都覆盖，白天不覆盖', () {
      expect(night.covers(22 * 60), isTrue);
      expect(night.covers(23 * 60 + 59), isTrue);
      expect(night.covers(0), isTrue);
      expect(night.covers(5 * 60 + 59), isTrue);
      expect(night.covers(6 * 60), isFalse);
      expect(night.covers(12 * 60), isFalse);
    });

    test('开始等于结束视为空时段，避免整天被一个人占住', () {
      const empty = PetShift(
        id: 'x',
        residentId: 'r',
        startMinute: 0,
        endMinute: 0,
      );
      expect(empty.covers(0), isFalse);
      expect(empty.covers(720), isFalse);
    });

    test('分钟格式化与展示', () {
      expect(PetShift.clock(0), '00:00');
      expect(PetShift.clock(8 * 60 + 5), '08:05');
      expect(PetShift.clock(24 * 60 + 30), '00:30');
      expect(day.label, '08:00—22:00');
    });
  });

  group('外观', () {
    test('半透明默认开，copyWith 只改这一项', () {
      const settings = PetSettings(enabled: true, realtimeFrames: 4);
      expect(settings.translucent, isTrue);

      final solid = settings.copyWith(translucent: false);
      expect(solid.translucent, isFalse);
      expect(solid.enabled, isTrue);
      expect(solid.realtimeFrames, 4);
    });
  });
}
