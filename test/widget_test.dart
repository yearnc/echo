import 'package:echo/core/constants/app_texts.dart';
import 'package:echo/core/utils/relative_time.dart';
import 'package:echo/domain/models/app_mode.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/features/shared_widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppMode', () {
    test('两种模式的标签与 scope 正确', () {
      expect(AppMode.echo.label, '回响模式');
      expect(AppMode.clear.label, '清醒模式');
      expect(AppMode.echo.scope, 'echo');
      expect(AppMode.clear.scope, 'clear');
    });

    test('opposite 互为反向', () {
      expect(AppMode.echo.opposite, AppMode.clear);
      expect(AppMode.clear.opposite, AppMode.echo);
    });

    test('fromScope 只认 clear，其余一律回响', () {
      expect(AppMode.fromScope('clear'), AppMode.clear);
      expect(AppMode.fromScope('echo'), AppMode.echo);
      expect(AppMode.fromScope(null), AppMode.echo);
    });
  });

  group('RelativeTime', () {
    final now = DateTime(2026, 9, 11, 20, 30);

    test('一分钟内显示刚刚', () {
      expect(RelativeTime.format(now.subtract(const Duration(seconds: 30)), now: now),
          '刚刚');
    });

    test('一小时内显示分钟', () {
      expect(
          RelativeTime.format(now.subtract(const Duration(minutes: 26)), now: now),
          '26分钟前');
    });

    test('当天显示小时', () {
      expect(RelativeTime.format(now.subtract(const Duration(hours: 3)), now: now),
          '3小时前');
    });

    test('跨天显示昨天加时刻', () {
      final yesterdayEvening = DateTime(2026, 9, 10, 21, 5);
      expect(RelativeTime.format(yesterdayEvening, now: now), '昨天 21:05');
    });

    test('更早的同年日期显示月日', () {
      expect(RelativeTime.format(DateTime(2026, 9, 3, 8, 5), now: now), '9月3日 08:05');
    });

    test('跨年显示完整日期', () {
      expect(RelativeTime.format(DateTime(2025, 12, 31, 23, 0), now: now),
          '2025年12月31日');
    });
  });

  group('合规文案', () {
    test('回响模式小字逐字固定', () {
      expect(AppTexts.aiDisclaimer, '内容由AI生成，仅供参考');
    });

    test('清醒模式永久提示不可改写', () {
      expect(AppTexts.permanentNotice, '本 APP 不含真实用户，请勿将此处认可等同于现实价值。');
    });
  });

  group('AiPersona', () {
    test('fromJson 解析完整字段', () {
      final persona = AiPersona.fromJson(const {
        'id': 'persona_999',
        'name': '测试住民',
        'avatar': '',
        'activeHours': [8, 20],
        'likeProbability': 0.8,
        'commentProbability': 0.5,
        'badges': ['测试'],
        'commentSamples': ['你好'],
      });

      expect(persona.id, 'persona_999');
      expect(persona.name, '测试住民');
      expect(persona.activeHours, [8, 20]);
      expect(persona.likeProbability, 0.8);
      expect(persona.badges, ['测试']);
      expect(persona.commentSamples, ['你好']);
    });

    test('activeHours 为空时视为全天活跃', () {
      const persona = AiPersona(id: 'p', name: 'n');
      expect(persona.isActiveAt(DateTime(2026, 9, 11, 4)), isTrue);
    });
  });

  group('UserAvatar 文字兜底', () {
    testWidgets('没有图片时渲染昵称首字', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: UserAvatar(name: '温柔学姐', size: 40)),
      ));

      expect(find.text('温'), findsOneWidget);
    });

    testWidgets('空昵称不会崩', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: UserAvatar(name: '  ', size: 40)),
      ));

      expect(find.text('?'), findsOneWidget);
    });
  });
}
