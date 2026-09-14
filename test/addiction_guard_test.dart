import 'dart:math';

import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/addiction_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/domain/models/echo_settings.dart';
import 'package:echo/domain/models/safety_settings.dart';
import 'package:echo/domain/services/addiction_guard.dart';
import 'package:echo/domain/services/interaction_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// 防沉迷提醒与冷静模式的逻辑测试。
void main() {
  late AppDatabase db;
  late AddictionRepository addiction;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addiction = AddictionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  AddictionGuard guardWith(SafetySettings settings) => AddictionGuard(
    repository: addiction,
    readSettings: () => settings,
  );

  group('防沉迷提醒', () {
    test('总开关关闭时永远不提醒', () async {
      final guard = guardWith(
        const SafetySettings(addictionGuard: false, feedbackViewThreshold: 1),
      );
      await guard.recordView('p1');

      expect(await guard.evaluate(), isNull);
    });

    test('次数没到阈值时不提醒', () async {
      final guard = guardWith(const SafetySettings(feedbackViewThreshold: 3));
      await guard.recordView('p1');
      await guard.recordView('p1');

      expect(await guard.evaluate(), isNull);
    });

    test('达到阈值时给出提醒文案', () async {
      final guard = guardWith(const SafetySettings(feedbackViewThreshold: 2));
      await guard.recordView('p1');
      await guard.recordView('p1');

      expect(await guard.evaluate(), isNotNull);
    });

    test('同一个窗口里只提醒一次', () async {
      final guard = guardWith(const SafetySettings(feedbackViewThreshold: 2));
      await guard.recordView('p1');
      await guard.recordView('p1');

      expect(await guard.evaluate(), isNotNull);
      expect(
        await guard.evaluate(),
        isNull,
        reason: '连着弹三次只会让人想去关掉这个开关',
      );
    });

    test('阈值调高之后不再触发', () async {
      await addiction.recordFeedbackView();
      await addiction.recordFeedbackView();

      expect(
        await guardWith(const SafetySettings(feedbackViewThreshold: 2))
            .evaluate(),
        isNotNull,
      );
      expect(
        await guardWith(const SafetySettings(feedbackViewThreshold: 10))
            .evaluate(),
        isNull,
      );
    });
  });

  group('冷静模式排期延迟', () {
    List<AiPersona> personas() => [
      const AiPersona(
        id: 'p1',
        name: '测试住民',
        personalityType: '温柔',
        likeProbability: 1,
        commentProbability: 1,
      ),
    ];

    test('没有延迟时首条反馈很快到', () {
      final planner = InteractionPlanner(random: Random(7));
      final planned = planner.plan(
        now: DateTime(2026, 9, 14, 10),
        personas: personas(),
        settings: EchoSettings.defaults,
        delay: Duration.zero,
      );
      final now = DateTime(2026, 9, 14, 10);
      final earliest = planned
          .map((item) => item.scheduledAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);

      expect(earliest.difference(now), lessThan(const Duration(minutes: 5)));
    });

    test('开启冷静模式后整批排期都往后推', () {
      const delay = Duration(minutes: 10);
      final now = DateTime(2026, 9, 14, 10);

      // 两次各用一个同种子的随机源：共用同一个实例会让第二次的随机状态
      // 接着往下走，排出来的条数就不一样了。
      final plain = InteractionPlanner(random: Random(7)).plan(
        now: now,
        personas: personas(),
        settings: EchoSettings.defaults,
      );
      final cooled = InteractionPlanner(random: Random(7)).plan(
        now: now,
        personas: personas(),
        settings: EchoSettings.defaults,
        delay: delay,
      );

      expect(cooled, hasLength(plain.length));
      for (var i = 0; i < plain.length; i++) {
        expect(
          cooled[i].scheduledAt.difference(plain[i].scheduledAt),
          delay,
          reason: '延迟是整体平移，不是重排',
        );
      }
    });

    test('延迟后最短等待时间不短于延迟窗口', () {
      final planner = InteractionPlanner(random: Random(3));
      const delay = Duration(minutes: 10);
      final now = DateTime(2026, 9, 14, 10);

      final cooled = planner.plan(
        now: now,
        personas: personas(),
        settings: EchoSettings.defaults,
        delay: delay,
      );

      final earliest = cooled
          .map((item) => item.scheduledAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      expect(earliest.difference(now), greaterThanOrEqualTo(delay));
    });
  });
}
