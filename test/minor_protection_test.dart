import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/db/database_provider.dart';
import 'package:echo/domain/models/app_mode.dart';
import 'package:echo/domain/services/mode_controller.dart';
import 'package:echo/domain/services/safety_controller.dart';
import 'package:echo/features/shared_widgets/mode_switch_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> writeSetting(String key, String value) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  group('未成年人保护（B11）', () {
    test('默认是关的：开它的动作该由人来做', () async {
      container.read(safetyControllerProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(safetyControllerProvider).minorProtection, isFalse);
    });

    test('开了之后写进库里，重开也还在', () async {
      await writeSetting(SafetyController.minorKey, 'true');

      final fresh = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(fresh.dispose);
      fresh.read(safetyControllerProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      expect(fresh.read(safetyControllerProvider).minorProtection, isTrue);
    });

    testWidgets('这道门开着的时候，切回响模式被拦下', (tester) async {
      await writeSetting(SafetyController.minorKey, 'true');
      container.read(safetyControllerProvider.notifier);
      // SafetyController 是从库里异步恢复的，而 widget 测试的时钟不会自己走：
      // 直接用 `await Future.delayed` 会一直挂着（真实时间要用 runAsync 推）。
      // 这里等到状态真的变成"锁着"再往下走——等不到就让后面那条断言说话。
      for (var i = 0; i < 30; i++) {
        if (container.read(safetyControllerProvider).minorProtection) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      expect(
        container.read(safetyControllerProvider).minorProtection,
        isTrue,
        reason: '设置没恢复出来，后面的拦截也就测不到了',
      );

      var switched = true;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () async {
                    switched = await runModeSwitch(context, ref, AppMode.echo);
                  },
                  child: const Text('切过去'),
                ),
              ),
            ),
          ),
        ),
      );

      final modeBefore = container.read(modeControllerProvider);

      await tester.tap(find.text('切过去'));
      await tester.pumpAndSettle();

      expect(find.text('回响模式已锁定'), findsOneWidget);

      // 弹窗得点掉：`runModeSwitch` 停在这一句上等用户看完，
      // 不点它的话，函数还没返回，下面那条断言测的就是空气。
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();

      expect(switched, isFalse, reason: '锁着的时候不该切成功');
      expect(
        container.read(modeControllerProvider),
        modeBefore,
        reason: '模式也不该变',
      );
    });

    testWidgets('门没开的时候照常走原来的二次确认', (tester) async {
      container.read(safetyControllerProvider.notifier);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => runModeSwitch(context, ref, AppMode.echo),
                  child: const Text('切过去'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('切过去'));
      await tester.pumpAndSettle();

      // 走的是旧的年龄门那条路，不是"已锁定"
      expect(find.text('切回响模式'), findsOneWidget);
      expect(find.text('回响模式已锁定'), findsNothing);
    });
  });
}
