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

    test('定了闹钟的人不被后台的空闲唤醒抢在前面', () {
      final order = ResidentWakeService.backgroundOrder(
        ids: ['alarmed', 'idle', 'waiting'],
        lastWakeAt: {
          'alarmed': now.subtract(const Duration(hours: 5)),
          'idle': now.subtract(const Duration(hours: 3)),
          'waiting': now.subtract(const Duration(hours: 2)),
        },
        oldestPendingAt: {
          'alarmed': null,
          'idle': null,
          'waiting': now.subtract(const Duration(minutes: 3)),
        },
        upcomingAlarmIds: {'alarmed'},
        idleGap: const Duration(minutes: 90),
        now: now,
      );

      expect(order, ['waiting', 'idle']);
      expect(order, isNot(contains('alarmed')));
    });

    test('有闹钟但也有待办的人照常处理', () {
      final order = ResidentWakeService.backgroundOrder(
        ids: ['alarmed'],
        lastWakeAt: {'alarmed': now.subtract(const Duration(hours: 5))},
        oldestPendingAt: {
          'alarmed': now.subtract(const Duration(minutes: 1)),
        },
        upcomingAlarmIds: {'alarmed'},
        idleGap: const Duration(minutes: 90),
        now: now,
      );
      expect(order, ['alarmed']);
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
    test('唤醒专用工具里有 read_post，且基础工具没被误删', () {
      final names = {
        for (final tool in ResidentToolSession.wakeOnlyTools)
          (tool['function'] as Map)['name'] as String,
      };
      expect(
        names,
        containsAll([
          'browse_feed',
          'read_post',
          'like_post',
          'comment_post',
          'finish',
          'check_wake_log',
          'leave_note',
          'set_alarm',
          'cancel_alarm',
          'list_alarms',
          'pet_status',
          'pet_say',
          'pet_react',
          'pet_look',
          'pet_request_watch',
          'pet_sleep',
          'pet_note',
        ]),
      );

      final readPost = ResidentToolSession.wakeOnlyTools.firstWhere(
        (tool) => (tool['function'] as Map)['name'] == 'read_post',
      );
      final parameters = (readPost['function'] as Map)['parameters'] as Map;
      final properties = parameters['properties'] as Map;
      expect(
        properties.keys,
        containsAll([
          'post_id',
          'include_comments',
          'comments_limit',
          'include_replies',
        ]),
      );
      expect(parameters['required'], contains('post_id'));
    });

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
