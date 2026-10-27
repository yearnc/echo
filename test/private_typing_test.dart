import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/private_message_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PrivateMessageRepository messages;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    messages = PrivateMessageRepository(db);
  });

  tearDown(() async => db.close());

  test('未来还有待发段时，「正在打字」为真', () async {
    final values = <bool>[];
    final sub = messages.watchTyping('r1').listen(values.add);
    await pumpEventQueue();
    expect(values.last, isFalse);

    await messages.scheduleIncoming(
      personaId: 'r1',
      content: '等我一下，我分两段说完',
      at: DateTime.now().add(const Duration(minutes: 5)),
      deliveryGroup: 'wake_1',
    );
    await pumpEventQueue();

    expect(values.last, isTrue, reason: '还有一段没到点');
    await sub.cancel();
  });

  test('已经出现的历史消息不会让它一直显示', () async {
    await messages.scheduleIncoming(
      personaId: 'r1',
      content: '这条已经发出去了',
      at: DateTime.now().subtract(const Duration(minutes: 1)),
      deliveryGroup: 'wake_1',
    );

    final typing = await messages.watchTyping('r1').first;
    expect(typing, isFalse);
  });
}
