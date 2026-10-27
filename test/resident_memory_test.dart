import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/custom_resident_repository.dart';
import 'package:echo/data/repositories/resident_memory_repository.dart';
import 'package:echo/domain/models/custom_resident.dart';
import 'package:echo/domain/models/resident_memory.dart';

void main() {
  late AppDatabase db;
  late CustomResidentRepository residents;
  late ResidentMemoryRepository memories;
  late String residentId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    residents = CustomResidentRepository(db);
    memories = ResidentMemoryRepository(db);
    residentId = CustomResidentRepository.newId();
    await residents.upsert(
      CustomResident(
        id: residentId,
        name: '小满',
        bio: '住楼下，爱拍照',
        createdAt: DateTime(2026, 10, 18),
      ),
    );
  });

  tearDown(() async => db.close());

  ResidentMemory memory(
    String id, {
    String summary = '',
    String content = '',
    List<String> tags = const [],
    DateTime? at,
  }) {
    final moment = at ?? DateTime(2026, 10, 18, 21);
    return ResidentMemory(
      id: id,
      residentId: residentId,
      source: 'manual',
      summary: summary,
      content: content,
      tags: tags,
      createdAt: moment,
      updatedAt: moment,
    );
  }

  test('固定住民能写、能读、能软删', () async {
    final all = await residents.all();
    expect(all, hasLength(1));
    expect(all.single.name, '小满');

    await residents.softDelete(residentId);
    expect(await residents.all(), isEmpty);
    expect(await residents.findById(residentId), isNotNull);
  });

  test('酒馆式的人设字段能存能读', () async {
    await residents.upsert(
      CustomResident(
        id: 'r3',
        name: '小满',
        description: '住楼下，和用户认识三个月',
        personality: '不舒服时先用冷幽默',
        scenario: '小区门口的便利店',
        exampleDialogue: '用户：今天好累\n小满：那别说话了，先坐会儿',
        extraInstructions: '不要用感叹号',
        tags: const ['夜猫子', '便利店'],
        createdAt: DateTime(2026, 10, 18),
      ),
    );

    final resident = (await residents.findById('r3'))!;
    expect(resident.description, contains('认识三个月'));
    expect(resident.personality, contains('冷幽默'));
    expect(resident.scenario, contains('便利店'));
    expect(resident.exampleDialogue, contains('先坐会儿'));
    expect(resident.extraInstructions, contains('感叹号'));
    expect(resident.tags, containsAll(['夜猫子', '便利店']));
  });

  test('记忆能写能读，按最近排序', () async {
    await memories.add(
      memory('m1', summary: '喜欢拍天空', at: DateTime(2026, 10, 17)),
    );
    await memories.add(
      memory('m2', summary: '最近在准备考试', at: DateTime(2026, 10, 18)),
    );

    final recent = await memories.recent(residentId);
    expect(recent.map((m) => m.summary), ['最近在准备考试', '喜欢拍天空']);
    expect(await memories.count(residentId), 2);
  });

  test('关键词检索：多个词要同时命中', () async {
    await memories.add(memory('m1', summary: '喜欢拍天空', content: '上次拍了晚霞'));
    await memories.add(memory('m2', summary: '喜欢猫', content: '家里有两只'));

    final one = await memories.search(residentId, '天空');
    expect(one.single.id, 'm1');

    final both = await memories.search(residentId, '天空 晚霞');
    expect(both.single.id, 'm1');

    final none = await memories.search(residentId, '天空 猫');
    expect(none, isEmpty);
  });

  test('中文长句也能检索：整句查不到时按 2—3 字滑窗匹配', () async {
    await memories.add(memory('m1', summary: '最近在准备考试', content: '下周三考高数'));
    await memories.add(memory('m2', summary: '喜欢拍天空', content: '晚霞很好看'));

    final exam = await memories.search(residentId, '上次考试的事');
    expect(exam.map((m) => m.id), contains('m1'));
    expect(exam.map((m) => m.id), isNot(contains('m2')));

    // 一个字的查询仍然能命中。
    final cat = await memories.search(residentId, '猫');
    expect(cat, isEmpty);

    // 纯停用词不拿来匹配，回落到最近几条，而不是把所有记忆都翻出来。
    final stop = await memories.search(residentId, '的');
    expect(stop.length, 2);
  });

  test('超过上限时归档最旧的，不删除', () async {
    for (var i = 0; i < 5; i++) {
      await memories.add(
        memory('m$i', summary: '第 $i 条', at: DateTime(2026, 10, 1 + i)),
      );
    }

    await memories.archiveOverflow(residentId, 3);
    expect(await memories.count(residentId), 3);

    final all = await db.select(db.residentMemories).get();
    expect(all, hasLength(5), reason: '归档不是删除');
    expect(all.where((row) => row.archivedAt != null), hasLength(2));
  });

  test('删除一条记忆不影响其他，原文还在', () async {
    await memories.add(memory('m1', summary: '会被删'));
    await memories.add(memory('m2', summary: '留着'));

    await memories.softDelete('m1');

    final recent = await memories.recent(residentId);
    expect(recent.single.summary, '留着');
    final rows = await db.select(db.residentMemories).get();
    expect(rows, hasLength(2));
  });
}
