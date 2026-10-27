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
