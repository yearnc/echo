import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/resident_wake_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ResidentWakeLogRepository logs;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logs = ResidentWakeLogRepository(db);
  });

  tearDown(() async => db.close());

  test('醒了就记一条，结束后能算出醒了多久', () async {
    final at = DateTime(2026, 10, 27, 9, 30);
    await logs.start(
      id: 'wake_1',
      residentId: 'r1',
      trigger: 'heartbeat',
      at: at,
    );
    await logs.finish('wake_1', at: at.add(const Duration(minutes: 2)));

    final today = await logs.today('r1', now: at);
    expect(today, hasLength(1));
    expect(today.single.triggerLabel, '自己醒来看看');
    expect(today.single.awakeFor, const Duration(minutes: 2));
  });

  test('今天的日志只算今天', () async {
    final now = DateTime(2026, 10, 27, 20);
    await logs.start(
      id: 'w1',
      residentId: 'r1',
      trigger: 'user_action',
      at: DateTime(2026, 10, 26, 23, 50),
    );
    await logs.start(
      id: 'w2',
      residentId: 'r1',
      trigger: 'heartbeat',
      at: DateTime(2026, 10, 27, 0, 10),
    );

    final today = await logs.today('r1', now: now);
    expect(today.map((log) => log.id), ['w2']);
  });

  test('留言留在这一轮，下一轮能读到并带着时间', () async {
    final at = DateTime(2026, 10, 27, 9);
    await logs.start(
      id: 'w1',
      residentId: 'r1',
      trigger: 'heartbeat',
      at: at,
    );
    expect(await logs.setNote('w1', '下次记得问她考完没有'), isTrue);

    final note = await logs.lastNote('r1', excludeId: 'w2');
    expect(note, isNotNull);
    expect(note!.note, '下次记得问她考完没有');
    expect(note.noteAt, isNotNull);

    // 当前这一轮自己不该再读到自己的留言。
    expect(await logs.lastNote('r1', excludeId: 'w1'), isNull);

    // 交给下一次醒来之后，就不再反复带上。
    await logs.markNoteDelivered(note.id);
    expect(await logs.lastNote('r1', excludeId: 'w2'), isNull);
  });

  test('工具调用按顺序记下来，连续同名只留一条', () async {
    final at = DateTime(2026, 10, 28, 12);
    await logs.start(
      id: 'w1',
      residentId: 'r1',
      trigger: 'user_action',
      at: at,
    );
    await logs.recordTool('w1', 'memory_list_recent');
    await logs.recordTool('w1', 'send_dm');
    await logs.recordTool('w1', 'send_dm');
    await logs.recordTool('w1', 'send_dm');
    await logs.finish('w1', at: at.add(const Duration(seconds: 30)));

    final today = await logs.today('r1', now: at);
    expect(today.single.tools, ['memory_list_recent', 'send_dm']);
  });

  test('十分钟内连续的 user_action 合并成一次', () async {
    final first = DateTime(2026, 10, 28, 12);
    await logs.start(
      id: 'w1',
      residentId: 'r1',
      trigger: 'user_action',
      at: first,
    );
    await logs.finish('w1', at: first.add(const Duration(seconds: 20)));

    final next = await logs.reusableUserWake(
      'r1',
      now: first.add(const Duration(minutes: 3)),
    );
    expect(next?.id, 'w1');

    // 超过窗口就是新的一次。
    final far = await logs.reusableUserWake(
      'r1',
      now: first.add(const Duration(minutes: 11)),
    );
    expect(far, isNull);
  });

  test('心跳和后台不参与合并', () async {
    final at = DateTime(2026, 10, 28, 12);
    await logs.start(
      id: 'w1',
      residentId: 'r1',
      trigger: 'heartbeat',
      at: at,
    );
    await logs.finish('w1', at: at.add(const Duration(minutes: 1)));

    expect(
      await logs.reusableUserWake('r1', now: at.add(const Duration(minutes: 2))),
      isNull,
    );
  });

  test('合并后重新打开，结束时长按最后一次算', () async {
    final at = DateTime(2026, 10, 28, 12);
    await logs.start(
      id: 'w1',
      residentId: 'r1',
      trigger: 'user_action',
      at: at,
    );
    await logs.finish('w1', at: at.add(const Duration(minutes: 1)));
    await logs.reopen('w1');
    await logs.finish('w1', at: at.add(const Duration(minutes: 4)));

    final list = await logs.today('r1', now: at);
    expect(list, hasLength(1));
    expect(list.single.awakeFor, const Duration(minutes: 4));
  });

  test('空留言不会覆盖已有记录', () async {
    await logs.start(
      id: 'w1',
      residentId: 'r1',
      trigger: 'setup',
      at: DateTime(2026, 10, 27, 9),
    );
    await logs.setNote('w1', '记住这句话');
    expect(await logs.setNote('w1', '   '), isFalse);

    final note = await logs.lastNote('r1', excludeId: 'other');
    expect(note!.note, '记住这句话');
  });
}
