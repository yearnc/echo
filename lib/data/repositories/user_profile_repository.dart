import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/user_profile.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 用户资料的读写（`user_profile` 单行）。
///
/// 这张表从阶段 A 建库那天就在，但一直没接进界面：所有页面都直接读常量
/// 「路人」，表里的昵称字段是空的。所以"改不了名字"不是没排期，
/// 是两头没接上——现在接上。
class UserProfileRepository {
  const UserProfileRepository(this._db);

  final AppDatabase _db;

  /// 单行的主键。目前只有"我"（规划书里也是单行）。
  static const String profileId = 'me';

  Stream<UserProfile?> watch() {
    final query = _db.select(_db.userProfile)
      ..where((t) => t.id.equals(profileId));
    return query.watchSingleOrNull().map(_toDomain);
  }

  Future<UserProfile?> load() async {
    final query = _db.select(_db.userProfile)
      ..where((t) => t.id.equals(profileId));
    return _toDomain(await query.getSingleOrNull());
  }

  /// 只改传进来的字段：昵称与头像可以分别更新。
  ///
  /// 传空字符串是**有意义的**——"把昵称清掉"意味着回落到默认名，
  /// "把头像清掉"意味着用文字头像。所以这里不能用"null 就是不传"的写法。
  Future<void> save({
    String? nickname,
    String? avatarRef,
    String? gender,
    String? ageRange,
    String? occupation,
    String? city,
    String? interests,
    String? preferredName,
    String? intro,
  }) async {
    final companion = UserProfileCompanion(
      nickname: nickname == null
          ? const Value.absent()
          : Value(nickname.trim()),
      avatar: avatarRef == null
          ? const Value.absent()
          : Value(avatarRef.trim()),
      gender: gender == null ? const Value.absent() : Value(gender.trim()),
      ageRange: ageRange == null
          ? const Value.absent()
          : Value(ageRange.trim()),
      occupation: occupation == null
          ? const Value.absent()
          : Value(occupation.trim()),
      city: city == null ? const Value.absent() : Value(city.trim()),
      interests: interests == null
          ? const Value.absent()
          : Value(interests.trim()),
      preferredName: preferredName == null
          ? const Value.absent()
          : Value(preferredName.trim()),
      intro: intro == null ? const Value.absent() : Value(intro.trim()),
    );

    final updated = await (_db.update(
      _db.userProfile,
    )..where((t) => t.id.equals(profileId))).write(companion);
    if (updated > 0) return;

    // 还没有那一行（比如从旧版本升上来、或被人清过库）就补一行
    await _db
        .into(_db.userProfile)
        .insert(
          UserProfileCompanion.insert(
            id: profileId,
            nickname: Value(nickname?.trim() ?? ''),
            avatar: Value(avatarRef?.trim() ?? ''),
            gender: Value(gender?.trim() ?? ''),
            ageRange: Value(ageRange?.trim() ?? ''),
            occupation: Value(occupation?.trim() ?? ''),
            city: Value(city?.trim() ?? ''),
            interests: Value(interests?.trim() ?? ''),
            preferredName: Value(preferredName?.trim() ?? ''),
            intro: Value(intro?.trim() ?? ''),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  UserProfile? _toDomain(UserProfileRow? row) => row == null
      ? null
      : UserProfile(
          nickname: row.nickname,
          avatarRef: row.avatar,
          gender: row.gender,
          ageRange: row.ageRange,
          occupation: row.occupation,
          city: row.city,
          interests: row.interests,
          preferredName: row.preferredName,
          intro: row.intro,
        );
}

final userProfileRepositoryProvider = Provider<UserProfileRepository>(
  (ref) => UserProfileRepository(ref.watch(databaseProvider)),
);

/// 我的资料：信息流、「我的」页、帖子详情都读它——改一处，处处都变。
final userProfileProvider = StreamProvider<UserProfile?>(
  (ref) => ref.watch(userProfileRepositoryProvider).watch(),
);
