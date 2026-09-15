import 'package:drift/native.dart';
import 'package:echo/core/constants/app_texts.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/user_profile_repository.dart';
import 'package:echo/domain/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用户资料的仓储层测试（内存库，不碰真实文件）。
void main() {
  late AppDatabase db;
  late UserProfileRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = UserProfileRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('用户资料', () {
    test('空库读出来是 null，保存之后能读回', () async {
      expect(await repo.load(), isNull);

      await repo.save(nickname: '阿程', avatarRef: 'file:/tmp/a.png');

      final profile = await repo.load();
      expect(profile, isNotNull);
      expect(profile!.nickname, '阿程');
      expect(profile.avatarRef, 'file:/tmp/a.png');
    });

    test('只传昵称不会动头像，只传头像不会动昵称', () async {
      await repo.save(nickname: '阿程', avatarRef: 'asset:assets/avatars/a.png');

      await repo.save(nickname: '小红');
      expect((await repo.load())!.avatarRef, 'asset:assets/avatars/a.png');

      await repo.save(avatarRef: '');
      final profile = await repo.load();
      expect(profile!.nickname, '小红');
      expect(profile.avatarOrNull, isNull, reason: '空引用 = 用文字头像');
    });

    test('两端空白会被去掉', () async {
      await repo.save(nickname: '  阿程  ', avatarRef: '  file:/tmp/a.png  ');

      final profile = await repo.load();
      expect(profile!.nickname, '阿程');
      expect(profile.avatarRef, 'file:/tmp/a.png');
    });

    test('watch 会把改动推出来', () async {
      final seen = <String>[];
      final sub = repo.watch().listen((profile) {
        seen.add(profile?.displayName ?? '(空)');
      });

      await repo.save(nickname: '阿程');
      await pumpEventQueue();

      await sub.cancel();
      expect(seen, contains('阿程'));
    });
  });

  group('UserProfile 展示规则', () {
    test('没设过昵称时回落到默认名，而不是显示空白', () {
      expect(const UserProfile().displayName, AppTexts.defaultNickname);
      expect(
        const UserProfile(nickname: '   ').displayName,
        AppTexts.defaultNickname,
      );
    });

    test('设过昵称就用它（去掉两端空白）', () {
      expect(const UserProfile(nickname: ' 阿程 ').displayName, '阿程');
    });

    test('头像引用为空时给 null，交给文字头像兜底', () {
      expect(const UserProfile().avatarOrNull, isNull);
      expect(const UserProfile(avatarRef: '  ').avatarOrNull, isNull);
      expect(
        const UserProfile(avatarRef: 'asset:x.png').avatarOrNull,
        'asset:x.png',
      );
    });
  });
}
