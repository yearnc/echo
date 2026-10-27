import 'package:echo/domain/services/resident_tool_session.dart';
import 'package:echo/domain/services/resident_wake_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('后台唤醒的优先级队列', () {
    final now = DateTime(2026, 10, 27, 22);

    test('有待办的先，最早没处理的更急', () {
      final order = ResidentWakeService.backgroundOrder(
        ids: ['a', 'b', 'c'],
        lastWakeAt: {
          'a': now.subtract(const Duration(hours: 4)),
          'b': now.subtract(const Duration(hours: 2)),
          'c': now.subtract(const Duration(hours: 3)),
        },
        oldestPendingAt: {
          'a': now.subtract(const Duration(minutes: 1)),
          'b': now.subtract(const Duration(minutes: 30)),
          'c': now.subtract(const Duration(hours: 1)),
        },
        idleGap: const Duration(minutes: 90),
        now: now,
      );

      expect(order, ['c', 'b', 'a'], reason: '待办越早越先');
    });

    test('没到空闲间隔、也没有待办的人不参与', () {
      final order = ResidentWakeService.backgroundOrder(
        ids: ['fresh', 'idle', 'waiting'],
        lastWakeAt: {
          'fresh': now.subtract(const Duration(minutes: 10)),
          'idle': now.subtract(const Duration(hours: 2)),
          'waiting': now.subtract(const Duration(hours: 5)),
        },
        oldestPendingAt: {
          'fresh': null,
          'idle': null,
          'waiting': now.subtract(const Duration(minutes: 5)),
        },
        idleGap: const Duration(minutes: 90),
        now: now,
      );

      expect(order, ['waiting', 'idle']);
      expect(order, isNot(contains('fresh')));
    });

    test('从没醒过的排在最前；待办仍然优先于空闲', () {
      final order = ResidentWakeService.backgroundOrder(
        ids: ['never', 'idleLongAgo', 'pending'],
        lastWakeAt: {
          'never': null,
          'idleLongAgo': now.subtract(const Duration(days: 3)),
          'pending': now.subtract(const Duration(hours: 1)),
        },
        oldestPendingAt: {
          'never': null,
          'idleLongAgo': null,
          'pending': now.subtract(const Duration(minutes: 2)),
        },
        idleGap: const Duration(minutes: 90),
        now: now,
      );

      expect(order, ['pending', 'never', 'idleLongAgo']);
    });

    test('时间完全一样时按 id 定序，结果稳定', () {
      final same = now.subtract(const Duration(hours: 3));
      final order = ResidentWakeService.backgroundOrder(
        ids: ['b', 'a'],
        lastWakeAt: {'a': same, 'b': same},
        oldestPendingAt: {'a': null, 'b': null},
        idleGap: const Duration(minutes: 90),
        now: now,
      );
      expect(order, ['a', 'b']);
    });
  });

  group('工具清单回归', () {
    test('基础工具没有被误删', () {
      final names = {
        for (final tool in ResidentToolSession.tools)
          (tool['function'] as Map)['name'] as String,
      };
      expect(
        names,
        containsAll([
          'memory_search',
          'memory_read',
          'memory_list_recent',
          'memory_write',
          'memory_update',
          'memory_delete',
          'create_post',
          'list_tools',
          'list_stickers',
          'send_sticker',
        ]),
      );
    });
  });
}
