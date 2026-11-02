import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/game_plugin_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late GamePluginRepository plugins;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    plugins = GamePluginRepository(db);
  });

  tearDown(() async => db.close());

  test('只接受 https 的 GitHub 链接', () async {
    await expectLater(
      plugins.installFromUrl('not a url'),
      throwsFormatException,
    );
    await expectLater(
      plugins.installFromUrl('http://github.com/a/b'),
      throwsFormatException,
    );
    await expectLater(
      plugins.installFromUrl('https://example.com/a/b'),
      throwsFormatException,
    );
  });

  test('链接里缺少仓库名时直接拒绝', () async {
    await expectLater(
      plugins.installFromUrl('https://github.com/only-owner'),
      throwsFormatException,
    );
  });
}
