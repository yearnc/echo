import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/db/seed_service.dart';
import 'package:echo/data/repositories/custom_resident_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 播种要读 assets/personas
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late CustomResidentRepository residents;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    residents = CustomResidentRepository(db);
  });

  tearDown(() async => db.close());

  test('首次启动会内置一位叫大肥鱼的固定住民', () async {
    await SeedService(db).seedIfNeeded();

    final all = await residents.all();
    expect(all, hasLength(1));
    expect(all.single.id, CustomResidentRepository.builtinResidentId);
    expect(all.single.name, '大肥鱼');
    expect(all.single.avatarAsset, SeedService.builtinResidentAvatar);
    expect(all.single.extraInstructions, contains('我的身份'));
    expect(all.single.tags, contains('鲸鱼女孩'));
  });

  test('重复播种不会多出第二个内置住民', () async {
    await SeedService(db).seedIfNeeded();
    await SeedService(db).seedIfNeeded();

    expect(await residents.all(), hasLength(1));
  });

  test('用户改过的内置住民不会被播种覆盖', () async {
    await SeedService(db).seedIfNeeded();
    final original = (await residents.all()).single;
    await residents.upsert(original.copyWith(name: '我改的名字'));

    await SeedService(db).seedIfNeeded();

    expect((await residents.all()).single.name, '我改的名字');
  });

  test('删掉内置住民之后，下次启动不会又冒出来', () async {
    await SeedService(db).seedIfNeeded();
    await residents.softDelete(CustomResidentRepository.builtinResidentId);

    await SeedService(db).seedIfNeeded();

    expect(await residents.all(), isEmpty);
  });

  test('老库的旧内置头像会跟着升级', () async {
    await SeedService(db).seedIfNeeded();
    await db
        .update(db.customResidents)
        .write(
          const CustomResidentsCompanion(
            avatarAsset: Value('asset:assets/avatars/avatar_085.webp'),
          ),
        );

    await SeedService(db).seedIfNeeded();

    expect(
      (await residents.all()).single.avatarAsset,
      SeedService.builtinResidentAvatar,
    );
  });

  test('用户自己换过的头像不会被内置升级覆盖', () async {
    await SeedService(db).seedIfNeeded();
    await db
        .update(db.customResidents)
        .write(
          const CustomResidentsCompanion(
            avatarAsset: Value('file:private/my-avatar.png'),
          ),
        );

    await SeedService(db).seedIfNeeded();

    expect(
      (await residents.all()).single.avatarAsset,
      'file:private/my-avatar.png',
    );
  });
}
