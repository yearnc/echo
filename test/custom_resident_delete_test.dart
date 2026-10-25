import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/custom_resident_repository.dart';
import 'package:echo/data/repositories/private_message_repository.dart';
import 'package:echo/domain/models/custom_resident.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CustomResidentRepository residents;
  late PrivateMessageRepository messages;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    residents = CustomResidentRepository(db);
    messages = PrivateMessageRepository(db);
  });

  tearDown(() async => db.close());

  test('删掉固定住民后，私信历史仍然保留、会话还能回看', () async {
    const id = 'resident_to_delete';
    await residents.upsert(
      CustomResident(id: id, name: '要删的人', createdAt: DateTime(2026, 10, 25)),
    );
    await messages.send(personaId: id, content: '还在吗');
    await messages.scheduleIncoming(
      personaId: id,
      content: '在的',
      at: DateTime.now().subtract(const Duration(seconds: 1)),
    );

    expect(await messages.watchConversations().first, hasLength(1));
    expect(await messages.watchUnreadCount().first, 1);

    await residents.softDelete(id);

    // 人走了，话还在：会话列表照常出现，历史一条不少；页面负责只读。
    expect(await messages.watchConversations().first, hasLength(1));
    expect(await messages.watchUnreadCount().first, 1);
    expect(await messages.watchThread(id).first, hasLength(2));
    expect(await db.select(db.privateMessages).get(), hasLength(2));

    // 行为用的列表里没有他，显示用的列表里还在（名字和头像靠它）。
    expect(await residents.all(), isEmpty);
    final stored = await residents.watchAllIncludingDeleted().first;
    expect(stored.single.name, '要删的人');
  });

  test('删掉固定住民时清掉他的待办队列', () async {
    const id = 'resident_with_inbox';
    await residents.upsert(
      CustomResident(id: id, name: '有来信的人', createdAt: DateTime(2026, 10, 25)),
    );
    await db
        .into(db.residentInboxItems)
        .insert(
          ResidentInboxItemsCompanion.insert(
            id: 'inbox_1',
            residentId: id,
            kind: 'dm',
            refId: 'msg_1',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );

    await residents.softDelete(id);

    expect(await db.select(db.residentInboxItems).get(), isEmpty);
  });
}
