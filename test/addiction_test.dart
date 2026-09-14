import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/addiction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// 防沉迷依据的读写测试（内存库）。
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

  group('查看反馈次数', () {
    test('记一次就多一次', () async {
      await addiction.recordFeedbackView(postId: 'p1');
      await addiction.recordFeedbackView(postId: 'p1');

      expect(await addiction.countFeedbackViews(), 2);
    });

    test('窗口外的旧记录不计入', () async {
      // 直接插一条两小时前的查看记录
      await db
          .into(db.feedbackViewLogs)
          .insert(
            FeedbackViewLogsCompanion.insert(
              id: 'view_old',
              viewedAt: DateTime.now()
                  .subtract(const Duration(hours: 2))
                  .millisecondsSinceEpoch,
            ),
          );
      await addiction.recordFeedbackView();

      expect(await addiction.countFeedbackViews(), 1);
      expect(
        await addiction.countFeedbackViews(
          windowMs: const Duration(hours: 3).inMilliseconds,
        ),
        2,
        reason: '窗口放大后旧记录应该回来',
      );
    });

    test('没有记录时是 0，不是报错', () async {
      expect(await addiction.countFeedbackViews(), 0);
    });
  });

  group('防沉迷事件', () {
    test('事件按时间倒序读出', () async {
      await addiction.logEvent(AddictionEventType.coolDownOn, value: 1);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await addiction.logEvent(AddictionEventType.feedbackThreshold, value: 8);

      final events = await addiction.recentEvents();

      expect(events.first.eventType, AddictionEventType.feedbackThreshold);
      expect(events.first.value, 8);
    });

    test('countEventsSince 按类型与时间过滤', () async {
      await addiction.logEvent(AddictionEventType.feedbackThreshold, value: 8);
      await addiction.logEvent(AddictionEventType.coolDownOn);

      final longAgo = DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;

      expect(
        await addiction.countEventsSince(
          AddictionEventType.feedbackThreshold,
          longAgo,
        ),
        1,
      );
      expect(
        await addiction.countEventsSince(AddictionEventType.sessionLong, 0),
        0,
      );
    });

    test('recentEvents 遵守 limit', () async {
      for (var i = 0; i < 5; i++) {
        await addiction.logEvent(AddictionEventType.sessionLong, value: i);
      }

      expect(await addiction.recentEvents(limit: 3), hasLength(3));
    });
  });
}
