import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/pet_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// 实时观察的文字保底：进程被杀后，下次启动要能把最后那段交回给住民。
void main() {
  late AppDatabase db;
  late PetSettingsRepository settings;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = PetSettingsRepository(db);
  });

  tearDown(() async => db.close());

  test('每位的未收尾记录分开存，互不覆盖', () async {
    await settings.saveDigest('a', 'a 看到编辑器');
    await settings.saveDigest('b', 'b 看到浏览器');

    expect(await settings.digest('a'), 'a 看到编辑器');
    expect(await settings.digest('b'), 'b 看到浏览器');
    expect(await settings.digestResidentIds(), containsAll(['a', 'b']));
  });

  test('清掉一位不影响另一位；写空等于删除', () async {
    await settings.saveDigest('a', 'a');
    await settings.saveDigest('b', 'b');
    await settings.clearDigest('a');
    expect(await settings.digest('a'), isNull);
    expect(await settings.digest('b'), 'b');

    await settings.saveDigest('b', '  ');
    expect(await settings.digest('b'), isNull);
    expect(await settings.digestResidentIds(), isEmpty);
  });
}
