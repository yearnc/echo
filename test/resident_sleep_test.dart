import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/custom_resident_repository.dart';
import 'package:echo/data/repositories/resident_sleep_repository.dart';
import 'package:echo/domain/models/custom_resident.dart';
import 'package:echo/domain/models/resident_sleep.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ResidentSleepRepository sleep;
  late CustomResidentRepository residents;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sleep = ResidentSleepRepository(db);
    residents = CustomResidentRepository(db);
  });

  tearDown(() async => db.close());

  test('开始睡眠、结束睡眠，并留下准确的时间', () async {
    final start = DateTime(2026, 11, 1, 22, 30);
    final end = DateTime(2026, 11, 3, 8, 0);
    final period = await sleep.start(
      residentId: 'r1',
      startedBy: 'auto',
      at: start,
    );
    expect(period.isSleeping, isTrue);
    expect(await sleep.isSleeping('r1'), isTrue);

    final woken = await sleep.wake('r1', endedBy: 'manual', at: end);
    expect(woken?.isSleeping, isFalse);
    expect(woken?.endedBy, 'manual');
    expect(woken?.duration, const Duration(hours: 33, minutes: 30));
    expect(await sleep.isSleeping('r1'), isFalse);
  });

  test('已经在睡时不会重复开一段', () async {
    final first = await sleep.start(
      residentId: 'r1',
      startedBy: 'manual',
      at: DateTime(2026, 11, 1),
    );
    final second = await sleep.start(
      residentId: 'r1',
      startedBy: 'auto',
      at: DateTime(2026, 11, 2),
    );
    expect(second.id, first.id);
    expect(await sleep.periodsFor('r1'), hasLength(1));
  });

  test('互动水位可以落库，并且默认按创建时间算', () async {
    final created = DateTime(2026, 10, 1, 9);
    await residents.upsert(
      CustomResident(
        id: 'r1',
        name: '阿鱼',
        createdAt: created,
      ),
    );
    final stored = await residents.findById('r1');
    expect(stored?.lastInteractionAt, isNotNull);
    expect(stored?.interactionAnchor, created);

    final touched = DateTime(2026, 10, 20, 12);
    await residents.touchInteraction('r1', at: touched);
    expect((await residents.findById('r1'))?.interactionAnchor, touched);
  });

  test('睡眠记录按开始时间倒序读取', () async {
    await sleep.start(
      residentId: 'r1',
      startedBy: 'manual',
      at: DateTime(2026, 10, 1),
    );
    await sleep.wake('r1', endedBy: 'manual', at: DateTime(2026, 10, 2));
    await sleep.start(
      residentId: 'r1',
      startedBy: 'auto',
      at: DateTime(2026, 10, 3),
    );
    final list = await sleep.periodsFor('r1');
    expect(list, hasLength(2));
    expect(list.first.startedAt, DateTime(2026, 10, 3));
  });

  test('唤醒提示区分手动唤醒和直接找 TA', () {
    final notice = SleepWakeNotice(
      sleptFrom: DateTime(2026, 10, 1, 9),
      wokeAt: DateTime(2026, 10, 3, 10),
      manual: true,
    );
    expect(notice.manualLine, contains('说点什么吧'));
    expect(notice.interactionLine, contains('被对方叫醒'));
    expect(notice.duration, const Duration(days: 2, hours: 1));
  });
}
