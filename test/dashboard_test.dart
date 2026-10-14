import 'package:drift/native.dart';
import 'package:echo/core/constants/app_texts.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/db/database_provider.dart';
import 'package:echo/domain/services/dashboard_stats.dart';
import 'package:echo/features/dashboard/dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

TimedCount _at(DateTime time, [int value = 1]) => (at: time, value: value);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('看板的聚合', () {
    final now = DateTime(2026, 10, 14, 21);

    test('按自然日分桶，最后一个格子装今天', () {
      final totals = DashboardStats.dailyTotals([
        _at(DateTime(2026, 10, 14, 9)),
        _at(DateTime(2026, 10, 14, 23)),
        _at(DateTime(2026, 10, 13, 1)),
      ], days: 7, now: now);

      expect(totals.length, 7);
      expect(totals.last, 2, reason: '今天两条');
      expect(totals[5], 1, reason: '昨天一条');
      expect(totals.take(5).every((v) => v == 0), isTrue);
    });

    test('窗口外的和将来的都不算', () {
      final totals = DashboardStats.dailyTotals([
        _at(DateTime(2026, 10, 1)), // 太老
        _at(DateTime(2026, 10, 15)), // 还没发生
      ], days: 7, now: now);

      expect(totals.every((v) => v == 0), isTrue);
    });

    test('一批点赞按它代表的人数记，不是按条数记', () {
      final totals = DashboardStats.dailyTotals([
        _at(DateTime(2026, 10, 14, 10), 18), // 一撮匿名的人
      ], days: 7, now: now);

      expect(totals.last, 18);
    });

    test('高峰取最忙的那个钟点；一次都没有时没有高峰', () {
      final hours = DashboardStats.hourlyTotals([
        DateTime(2026, 10, 13, 20),
        DateTime(2026, 10, 13, 20),
        DateTime(2026, 10, 14, 8),
      ]);

      expect(hours[20], 2);
      expect(DashboardStats.busiestHour(hours), 20);
      expect(DashboardStats.busiestHour(List<int>.filled(24, 0)), isNull);
    });

    test('前半段是 0 时不说百分比', () {
      expect(DashboardStats.growthPercent([0, 0, 0, 1, 2, 3]), isNull);
      expect(DashboardStats.growthPercent([1, 1, 1, 2, 2, 2]), 100);
      expect(DashboardStats.growthPercent([2, 2, 2, 1, 1, 1]), -50);
    });

    test('星期与钟点用中文的一个说法', () {
      expect(DashboardStats.weekdayLabel(DateTime(2026, 10, 14)), '三');
      expect(DashboardStats.hourLabel(20), '晚上 8 点');
      expect(DashboardStats.hourLabel(0), '凌晨 0 点');
      expect(DashboardStats.hourLabel(12), '中午 12 点');
    });
  });

  group('两种模式看的是两套数据', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);
    });

    test('回响侧：没有互动时也不该炸，数字全为 0', () async {
      final data = await container.read(echoDashboardProvider.future);

      expect(data.likesPerDay.length, 7);
      expect(data.likesToday, 0);
      expect(data.followers, 0);
      expect(data.busiestHour, isNull);
    });

    test('清醒侧：只数真实记录，一条 AI 数据都不碰', () async {
      final data = await container.read(clearDashboardProvider.future);

      expect(data.recordsThisWeek, 0);
      expect(data.actionsThisWeek, 0);
      expect(data.valuesCount, 0);
      expect(data.recordsPerDay.length, 7);
    });

    testWidgets('回响模式的看板必须带着那句 AI 标注', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DashboardPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 这句话在页面最底下，先滚下去（ListView 只建可见的那几屏）。
      final notice = find.text(AppTexts.aiDataNotice);
      await tester.scrollUntilVisible(notice, 240);

      // 规划书 §3.10：这一句在看板上不可省略。
      expect(notice, findsOneWidget);
    });
  });
}
