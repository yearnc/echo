// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('shared'),
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, scope];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSettingRow extends DataClass implements Insertable<AppSettingRow> {
  final String key;
  final String value;
  final String scope;
  const AppSettingRow({
    required this.key,
    required this.value,
    required this.scope,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['scope'] = Variable<String>(scope);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      key: Value(key),
      value: Value(value),
      scope: Value(scope),
    );
  }

  factory AppSettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      scope: serializer.fromJson<String>(json['scope']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'scope': serializer.toJson<String>(scope),
    };
  }

  AppSettingRow copyWith({String? key, String? value, String? scope}) =>
      AppSettingRow(
        key: key ?? this.key,
        value: value ?? this.value,
        scope: scope ?? this.scope,
      );
  AppSettingRow copyWithCompanion(AppSettingsCompanion data) {
    return AppSettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      scope: data.scope.present ? data.scope.value : this.scope,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingRow(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('scope: $scope')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, scope);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettingRow &&
          other.key == this.key &&
          other.value == this.value &&
          other.scope == this.scope);
}

class AppSettingsCompanion extends UpdateCompanion<AppSettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<String> scope;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<String>? scope,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (scope != null) 'scope': scope,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<String>? scope,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      scope: scope ?? this.scope,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('scope: $scope, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserProfileTable extends UserProfile
    with TableInfo<$UserProfileTable, UserProfileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserProfileTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nicknameMeta = const VerificationMeta(
    'nickname',
  );
  @override
  late final GeneratedColumn<String> nickname = GeneratedColumn<String>(
    'nickname',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<String> avatar = GeneratedColumn<String>(
    'avatar',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _signatureMeta = const VerificationMeta(
    'signature',
  );
  @override
  late final GeneratedColumn<String> signature = GeneratedColumn<String>(
    'signature',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<int> level = GeneratedColumn<int>(
    'level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _expMeta = const VerificationMeta('exp');
  @override
  late final GeneratedColumn<int> exp = GeneratedColumn<int>(
    'exp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _followersMeta = const VerificationMeta(
    'followers',
  );
  @override
  late final GeneratedColumn<int> followers = GeneratedColumn<int>(
    'followers',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _followingMeta = const VerificationMeta(
    'following',
  );
  @override
  late final GeneratedColumn<int> following = GeneratedColumn<int>(
    'following',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    nickname,
    avatar,
    signature,
    level,
    exp,
    followers,
    following,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_profile';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserProfileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('nickname')) {
      context.handle(
        _nicknameMeta,
        nickname.isAcceptableOrUnknown(data['nickname']!, _nicknameMeta),
      );
    }
    if (data.containsKey('avatar')) {
      context.handle(
        _avatarMeta,
        avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta),
      );
    }
    if (data.containsKey('signature')) {
      context.handle(
        _signatureMeta,
        signature.isAcceptableOrUnknown(data['signature']!, _signatureMeta),
      );
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    }
    if (data.containsKey('exp')) {
      context.handle(
        _expMeta,
        exp.isAcceptableOrUnknown(data['exp']!, _expMeta),
      );
    }
    if (data.containsKey('followers')) {
      context.handle(
        _followersMeta,
        followers.isAcceptableOrUnknown(data['followers']!, _followersMeta),
      );
    }
    if (data.containsKey('following')) {
      context.handle(
        _followingMeta,
        following.isAcceptableOrUnknown(data['following']!, _followingMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserProfileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserProfileRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      nickname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nickname'],
      )!,
      avatar: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar'],
      )!,
      signature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signature'],
      )!,
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}level'],
      )!,
      exp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}exp'],
      )!,
      followers: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}followers'],
      )!,
      following: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}following'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $UserProfileTable createAlias(String alias) {
    return $UserProfileTable(attachedDatabase, alias);
  }
}

class UserProfileRow extends DataClass implements Insertable<UserProfileRow> {
  final String id;
  final String nickname;
  final String avatar;
  final String signature;
  final int level;
  final int exp;
  final int followers;
  final int following;
  final int createdAt;
  const UserProfileRow({
    required this.id,
    required this.nickname,
    required this.avatar,
    required this.signature,
    required this.level,
    required this.exp,
    required this.followers,
    required this.following,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['nickname'] = Variable<String>(nickname);
    map['avatar'] = Variable<String>(avatar);
    map['signature'] = Variable<String>(signature);
    map['level'] = Variable<int>(level);
    map['exp'] = Variable<int>(exp);
    map['followers'] = Variable<int>(followers);
    map['following'] = Variable<int>(following);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  UserProfileCompanion toCompanion(bool nullToAbsent) {
    return UserProfileCompanion(
      id: Value(id),
      nickname: Value(nickname),
      avatar: Value(avatar),
      signature: Value(signature),
      level: Value(level),
      exp: Value(exp),
      followers: Value(followers),
      following: Value(following),
      createdAt: Value(createdAt),
    );
  }

  factory UserProfileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserProfileRow(
      id: serializer.fromJson<String>(json['id']),
      nickname: serializer.fromJson<String>(json['nickname']),
      avatar: serializer.fromJson<String>(json['avatar']),
      signature: serializer.fromJson<String>(json['signature']),
      level: serializer.fromJson<int>(json['level']),
      exp: serializer.fromJson<int>(json['exp']),
      followers: serializer.fromJson<int>(json['followers']),
      following: serializer.fromJson<int>(json['following']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'nickname': serializer.toJson<String>(nickname),
      'avatar': serializer.toJson<String>(avatar),
      'signature': serializer.toJson<String>(signature),
      'level': serializer.toJson<int>(level),
      'exp': serializer.toJson<int>(exp),
      'followers': serializer.toJson<int>(followers),
      'following': serializer.toJson<int>(following),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  UserProfileRow copyWith({
    String? id,
    String? nickname,
    String? avatar,
    String? signature,
    int? level,
    int? exp,
    int? followers,
    int? following,
    int? createdAt,
  }) => UserProfileRow(
    id: id ?? this.id,
    nickname: nickname ?? this.nickname,
    avatar: avatar ?? this.avatar,
    signature: signature ?? this.signature,
    level: level ?? this.level,
    exp: exp ?? this.exp,
    followers: followers ?? this.followers,
    following: following ?? this.following,
    createdAt: createdAt ?? this.createdAt,
  );
  UserProfileRow copyWithCompanion(UserProfileCompanion data) {
    return UserProfileRow(
      id: data.id.present ? data.id.value : this.id,
      nickname: data.nickname.present ? data.nickname.value : this.nickname,
      avatar: data.avatar.present ? data.avatar.value : this.avatar,
      signature: data.signature.present ? data.signature.value : this.signature,
      level: data.level.present ? data.level.value : this.level,
      exp: data.exp.present ? data.exp.value : this.exp,
      followers: data.followers.present ? data.followers.value : this.followers,
      following: data.following.present ? data.following.value : this.following,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserProfileRow(')
          ..write('id: $id, ')
          ..write('nickname: $nickname, ')
          ..write('avatar: $avatar, ')
          ..write('signature: $signature, ')
          ..write('level: $level, ')
          ..write('exp: $exp, ')
          ..write('followers: $followers, ')
          ..write('following: $following, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    nickname,
    avatar,
    signature,
    level,
    exp,
    followers,
    following,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserProfileRow &&
          other.id == this.id &&
          other.nickname == this.nickname &&
          other.avatar == this.avatar &&
          other.signature == this.signature &&
          other.level == this.level &&
          other.exp == this.exp &&
          other.followers == this.followers &&
          other.following == this.following &&
          other.createdAt == this.createdAt);
}

class UserProfileCompanion extends UpdateCompanion<UserProfileRow> {
  final Value<String> id;
  final Value<String> nickname;
  final Value<String> avatar;
  final Value<String> signature;
  final Value<int> level;
  final Value<int> exp;
  final Value<int> followers;
  final Value<int> following;
  final Value<int> createdAt;
  final Value<int> rowid;
  const UserProfileCompanion({
    this.id = const Value.absent(),
    this.nickname = const Value.absent(),
    this.avatar = const Value.absent(),
    this.signature = const Value.absent(),
    this.level = const Value.absent(),
    this.exp = const Value.absent(),
    this.followers = const Value.absent(),
    this.following = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserProfileCompanion.insert({
    required String id,
    this.nickname = const Value.absent(),
    this.avatar = const Value.absent(),
    this.signature = const Value.absent(),
    this.level = const Value.absent(),
    this.exp = const Value.absent(),
    this.followers = const Value.absent(),
    this.following = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt);
  static Insertable<UserProfileRow> custom({
    Expression<String>? id,
    Expression<String>? nickname,
    Expression<String>? avatar,
    Expression<String>? signature,
    Expression<int>? level,
    Expression<int>? exp,
    Expression<int>? followers,
    Expression<int>? following,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (nickname != null) 'nickname': nickname,
      if (avatar != null) 'avatar': avatar,
      if (signature != null) 'signature': signature,
      if (level != null) 'level': level,
      if (exp != null) 'exp': exp,
      if (followers != null) 'followers': followers,
      if (following != null) 'following': following,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserProfileCompanion copyWith({
    Value<String>? id,
    Value<String>? nickname,
    Value<String>? avatar,
    Value<String>? signature,
    Value<int>? level,
    Value<int>? exp,
    Value<int>? followers,
    Value<int>? following,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return UserProfileCompanion(
      id: id ?? this.id,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      signature: signature ?? this.signature,
      level: level ?? this.level,
      exp: exp ?? this.exp,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (nickname.present) {
      map['nickname'] = Variable<String>(nickname.value);
    }
    if (avatar.present) {
      map['avatar'] = Variable<String>(avatar.value);
    }
    if (signature.present) {
      map['signature'] = Variable<String>(signature.value);
    }
    if (level.present) {
      map['level'] = Variable<int>(level.value);
    }
    if (exp.present) {
      map['exp'] = Variable<int>(exp.value);
    }
    if (followers.present) {
      map['followers'] = Variable<int>(followers.value);
    }
    if (following.present) {
      map['following'] = Variable<int>(following.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserProfileCompanion(')
          ..write('id: $id, ')
          ..write('nickname: $nickname, ')
          ..write('avatar: $avatar, ')
          ..write('signature: $signature, ')
          ..write('level: $level, ')
          ..write('exp: $exp, ')
          ..write('followers: $followers, ')
          ..write('following: $following, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PostsTable extends Posts with TableInfo<$PostsTable, PostRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PostsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _imagesMeta = const VerificationMeta('images');
  @override
  late final GeneratedColumn<String> images = GeneratedColumn<String>(
    'images',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('shared'),
  );
  static const VerificationMeta _isAiGeneratedMeta = const VerificationMeta(
    'isAiGenerated',
  );
  @override
  late final GeneratedColumn<bool> isAiGenerated = GeneratedColumn<bool>(
    'is_ai_generated',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_ai_generated" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _topicIdMeta = const VerificationMeta(
    'topicId',
  );
  @override
  late final GeneratedColumn<String> topicId = GeneratedColumn<String>(
    'topic_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _topicNameMeta = const VerificationMeta(
    'topicName',
  );
  @override
  late final GeneratedColumn<String> topicName = GeneratedColumn<String>(
    'topic_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _allowAiReplyMeta = const VerificationMeta(
    'allowAiReply',
  );
  @override
  late final GeneratedColumn<bool> allowAiReply = GeneratedColumn<bool>(
    'allow_ai_reply',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("allow_ai_reply" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _replyDensityMeta = const VerificationMeta(
    'replyDensity',
  );
  @override
  late final GeneratedColumn<String> replyDensity = GeneratedColumn<String>(
    'reply_density',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _likeLevelMeta = const VerificationMeta(
    'likeLevel',
  );
  @override
  late final GeneratedColumn<String> likeLevel = GeneratedColumn<String>(
    'like_level',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _humanLevelMeta = const VerificationMeta(
    'humanLevel',
  );
  @override
  late final GeneratedColumn<int> humanLevel = GeneratedColumn<int>(
    'human_level',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isHotMeta = const VerificationMeta('isHot');
  @override
  late final GeneratedColumn<bool> isHot = GeneratedColumn<bool>(
    'is_hot',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_hot" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _likeCountMeta = const VerificationMeta(
    'likeCount',
  );
  @override
  late final GeneratedColumn<int> likeCount = GeneratedColumn<int>(
    'like_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _commentCountMeta = const VerificationMeta(
    'commentCount',
  );
  @override
  late final GeneratedColumn<int> commentCount = GeneratedColumn<int>(
    'comment_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    content,
    images,
    createdAt,
    updatedAt,
    scope,
    isAiGenerated,
    deletedAt,
    topicId,
    topicName,
    allowAiReply,
    replyDensity,
    likeLevel,
    humanLevel,
    isHot,
    likeCount,
    commentCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'posts';
  @override
  VerificationContext validateIntegrity(
    Insertable<PostRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('images')) {
      context.handle(
        _imagesMeta,
        images.isAcceptableOrUnknown(data['images']!, _imagesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    if (data.containsKey('is_ai_generated')) {
      context.handle(
        _isAiGeneratedMeta,
        isAiGenerated.isAcceptableOrUnknown(
          data['is_ai_generated']!,
          _isAiGeneratedMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('topic_id')) {
      context.handle(
        _topicIdMeta,
        topicId.isAcceptableOrUnknown(data['topic_id']!, _topicIdMeta),
      );
    }
    if (data.containsKey('topic_name')) {
      context.handle(
        _topicNameMeta,
        topicName.isAcceptableOrUnknown(data['topic_name']!, _topicNameMeta),
      );
    }
    if (data.containsKey('allow_ai_reply')) {
      context.handle(
        _allowAiReplyMeta,
        allowAiReply.isAcceptableOrUnknown(
          data['allow_ai_reply']!,
          _allowAiReplyMeta,
        ),
      );
    }
    if (data.containsKey('reply_density')) {
      context.handle(
        _replyDensityMeta,
        replyDensity.isAcceptableOrUnknown(
          data['reply_density']!,
          _replyDensityMeta,
        ),
      );
    }
    if (data.containsKey('like_level')) {
      context.handle(
        _likeLevelMeta,
        likeLevel.isAcceptableOrUnknown(data['like_level']!, _likeLevelMeta),
      );
    }
    if (data.containsKey('human_level')) {
      context.handle(
        _humanLevelMeta,
        humanLevel.isAcceptableOrUnknown(data['human_level']!, _humanLevelMeta),
      );
    }
    if (data.containsKey('is_hot')) {
      context.handle(
        _isHotMeta,
        isHot.isAcceptableOrUnknown(data['is_hot']!, _isHotMeta),
      );
    }
    if (data.containsKey('like_count')) {
      context.handle(
        _likeCountMeta,
        likeCount.isAcceptableOrUnknown(data['like_count']!, _likeCountMeta),
      );
    }
    if (data.containsKey('comment_count')) {
      context.handle(
        _commentCountMeta,
        commentCount.isAcceptableOrUnknown(
          data['comment_count']!,
          _commentCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PostRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PostRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      images: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}images'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      ),
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      isAiGenerated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_ai_generated'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      topicId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic_id'],
      ),
      topicName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic_name'],
      ),
      allowAiReply: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}allow_ai_reply'],
      )!,
      replyDensity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_density'],
      ),
      likeLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}like_level'],
      ),
      humanLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}human_level'],
      ),
      isHot: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_hot'],
      )!,
      likeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}like_count'],
      )!,
      commentCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}comment_count'],
      )!,
    );
  }

  @override
  $PostsTable createAlias(String alias) {
    return $PostsTable(attachedDatabase, alias);
  }
}

class PostRow extends DataClass implements Insertable<PostRow> {
  final String id;
  final String content;
  final String images;
  final int createdAt;
  final int? updatedAt;
  final String scope;
  final bool isAiGenerated;
  final int? deletedAt;
  final String? topicId;
  final String? topicName;
  final bool allowAiReply;
  final String? replyDensity;
  final String? likeLevel;
  final int? humanLevel;
  final bool isHot;
  final int likeCount;
  final int commentCount;
  const PostRow({
    required this.id,
    required this.content,
    required this.images,
    required this.createdAt,
    this.updatedAt,
    required this.scope,
    required this.isAiGenerated,
    this.deletedAt,
    this.topicId,
    this.topicName,
    required this.allowAiReply,
    this.replyDensity,
    this.likeLevel,
    this.humanLevel,
    required this.isHot,
    required this.likeCount,
    required this.commentCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['content'] = Variable<String>(content);
    map['images'] = Variable<String>(images);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    map['scope'] = Variable<String>(scope);
    map['is_ai_generated'] = Variable<bool>(isAiGenerated);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    if (!nullToAbsent || topicId != null) {
      map['topic_id'] = Variable<String>(topicId);
    }
    if (!nullToAbsent || topicName != null) {
      map['topic_name'] = Variable<String>(topicName);
    }
    map['allow_ai_reply'] = Variable<bool>(allowAiReply);
    if (!nullToAbsent || replyDensity != null) {
      map['reply_density'] = Variable<String>(replyDensity);
    }
    if (!nullToAbsent || likeLevel != null) {
      map['like_level'] = Variable<String>(likeLevel);
    }
    if (!nullToAbsent || humanLevel != null) {
      map['human_level'] = Variable<int>(humanLevel);
    }
    map['is_hot'] = Variable<bool>(isHot);
    map['like_count'] = Variable<int>(likeCount);
    map['comment_count'] = Variable<int>(commentCount);
    return map;
  }

  PostsCompanion toCompanion(bool nullToAbsent) {
    return PostsCompanion(
      id: Value(id),
      content: Value(content),
      images: Value(images),
      createdAt: Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      scope: Value(scope),
      isAiGenerated: Value(isAiGenerated),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      topicId: topicId == null && nullToAbsent
          ? const Value.absent()
          : Value(topicId),
      topicName: topicName == null && nullToAbsent
          ? const Value.absent()
          : Value(topicName),
      allowAiReply: Value(allowAiReply),
      replyDensity: replyDensity == null && nullToAbsent
          ? const Value.absent()
          : Value(replyDensity),
      likeLevel: likeLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(likeLevel),
      humanLevel: humanLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(humanLevel),
      isHot: Value(isHot),
      likeCount: Value(likeCount),
      commentCount: Value(commentCount),
    );
  }

  factory PostRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PostRow(
      id: serializer.fromJson<String>(json['id']),
      content: serializer.fromJson<String>(json['content']),
      images: serializer.fromJson<String>(json['images']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
      scope: serializer.fromJson<String>(json['scope']),
      isAiGenerated: serializer.fromJson<bool>(json['isAiGenerated']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      topicId: serializer.fromJson<String?>(json['topicId']),
      topicName: serializer.fromJson<String?>(json['topicName']),
      allowAiReply: serializer.fromJson<bool>(json['allowAiReply']),
      replyDensity: serializer.fromJson<String?>(json['replyDensity']),
      likeLevel: serializer.fromJson<String?>(json['likeLevel']),
      humanLevel: serializer.fromJson<int?>(json['humanLevel']),
      isHot: serializer.fromJson<bool>(json['isHot']),
      likeCount: serializer.fromJson<int>(json['likeCount']),
      commentCount: serializer.fromJson<int>(json['commentCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'content': serializer.toJson<String>(content),
      'images': serializer.toJson<String>(images),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int?>(updatedAt),
      'scope': serializer.toJson<String>(scope),
      'isAiGenerated': serializer.toJson<bool>(isAiGenerated),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'topicId': serializer.toJson<String?>(topicId),
      'topicName': serializer.toJson<String?>(topicName),
      'allowAiReply': serializer.toJson<bool>(allowAiReply),
      'replyDensity': serializer.toJson<String?>(replyDensity),
      'likeLevel': serializer.toJson<String?>(likeLevel),
      'humanLevel': serializer.toJson<int?>(humanLevel),
      'isHot': serializer.toJson<bool>(isHot),
      'likeCount': serializer.toJson<int>(likeCount),
      'commentCount': serializer.toJson<int>(commentCount),
    };
  }

  PostRow copyWith({
    String? id,
    String? content,
    String? images,
    int? createdAt,
    Value<int?> updatedAt = const Value.absent(),
    String? scope,
    bool? isAiGenerated,
    Value<int?> deletedAt = const Value.absent(),
    Value<String?> topicId = const Value.absent(),
    Value<String?> topicName = const Value.absent(),
    bool? allowAiReply,
    Value<String?> replyDensity = const Value.absent(),
    Value<String?> likeLevel = const Value.absent(),
    Value<int?> humanLevel = const Value.absent(),
    bool? isHot,
    int? likeCount,
    int? commentCount,
  }) => PostRow(
    id: id ?? this.id,
    content: content ?? this.content,
    images: images ?? this.images,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    scope: scope ?? this.scope,
    isAiGenerated: isAiGenerated ?? this.isAiGenerated,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    topicId: topicId.present ? topicId.value : this.topicId,
    topicName: topicName.present ? topicName.value : this.topicName,
    allowAiReply: allowAiReply ?? this.allowAiReply,
    replyDensity: replyDensity.present ? replyDensity.value : this.replyDensity,
    likeLevel: likeLevel.present ? likeLevel.value : this.likeLevel,
    humanLevel: humanLevel.present ? humanLevel.value : this.humanLevel,
    isHot: isHot ?? this.isHot,
    likeCount: likeCount ?? this.likeCount,
    commentCount: commentCount ?? this.commentCount,
  );
  PostRow copyWithCompanion(PostsCompanion data) {
    return PostRow(
      id: data.id.present ? data.id.value : this.id,
      content: data.content.present ? data.content.value : this.content,
      images: data.images.present ? data.images.value : this.images,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      scope: data.scope.present ? data.scope.value : this.scope,
      isAiGenerated: data.isAiGenerated.present
          ? data.isAiGenerated.value
          : this.isAiGenerated,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      topicId: data.topicId.present ? data.topicId.value : this.topicId,
      topicName: data.topicName.present ? data.topicName.value : this.topicName,
      allowAiReply: data.allowAiReply.present
          ? data.allowAiReply.value
          : this.allowAiReply,
      replyDensity: data.replyDensity.present
          ? data.replyDensity.value
          : this.replyDensity,
      likeLevel: data.likeLevel.present ? data.likeLevel.value : this.likeLevel,
      humanLevel: data.humanLevel.present
          ? data.humanLevel.value
          : this.humanLevel,
      isHot: data.isHot.present ? data.isHot.value : this.isHot,
      likeCount: data.likeCount.present ? data.likeCount.value : this.likeCount,
      commentCount: data.commentCount.present
          ? data.commentCount.value
          : this.commentCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PostRow(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('images: $images, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('scope: $scope, ')
          ..write('isAiGenerated: $isAiGenerated, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('topicId: $topicId, ')
          ..write('topicName: $topicName, ')
          ..write('allowAiReply: $allowAiReply, ')
          ..write('replyDensity: $replyDensity, ')
          ..write('likeLevel: $likeLevel, ')
          ..write('humanLevel: $humanLevel, ')
          ..write('isHot: $isHot, ')
          ..write('likeCount: $likeCount, ')
          ..write('commentCount: $commentCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    content,
    images,
    createdAt,
    updatedAt,
    scope,
    isAiGenerated,
    deletedAt,
    topicId,
    topicName,
    allowAiReply,
    replyDensity,
    likeLevel,
    humanLevel,
    isHot,
    likeCount,
    commentCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PostRow &&
          other.id == this.id &&
          other.content == this.content &&
          other.images == this.images &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.scope == this.scope &&
          other.isAiGenerated == this.isAiGenerated &&
          other.deletedAt == this.deletedAt &&
          other.topicId == this.topicId &&
          other.topicName == this.topicName &&
          other.allowAiReply == this.allowAiReply &&
          other.replyDensity == this.replyDensity &&
          other.likeLevel == this.likeLevel &&
          other.humanLevel == this.humanLevel &&
          other.isHot == this.isHot &&
          other.likeCount == this.likeCount &&
          other.commentCount == this.commentCount);
}

class PostsCompanion extends UpdateCompanion<PostRow> {
  final Value<String> id;
  final Value<String> content;
  final Value<String> images;
  final Value<int> createdAt;
  final Value<int?> updatedAt;
  final Value<String> scope;
  final Value<bool> isAiGenerated;
  final Value<int?> deletedAt;
  final Value<String?> topicId;
  final Value<String?> topicName;
  final Value<bool> allowAiReply;
  final Value<String?> replyDensity;
  final Value<String?> likeLevel;
  final Value<int?> humanLevel;
  final Value<bool> isHot;
  final Value<int> likeCount;
  final Value<int> commentCount;
  final Value<int> rowid;
  const PostsCompanion({
    this.id = const Value.absent(),
    this.content = const Value.absent(),
    this.images = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.scope = const Value.absent(),
    this.isAiGenerated = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.topicId = const Value.absent(),
    this.topicName = const Value.absent(),
    this.allowAiReply = const Value.absent(),
    this.replyDensity = const Value.absent(),
    this.likeLevel = const Value.absent(),
    this.humanLevel = const Value.absent(),
    this.isHot = const Value.absent(),
    this.likeCount = const Value.absent(),
    this.commentCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PostsCompanion.insert({
    required String id,
    this.content = const Value.absent(),
    this.images = const Value.absent(),
    required int createdAt,
    this.updatedAt = const Value.absent(),
    this.scope = const Value.absent(),
    this.isAiGenerated = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.topicId = const Value.absent(),
    this.topicName = const Value.absent(),
    this.allowAiReply = const Value.absent(),
    this.replyDensity = const Value.absent(),
    this.likeLevel = const Value.absent(),
    this.humanLevel = const Value.absent(),
    this.isHot = const Value.absent(),
    this.likeCount = const Value.absent(),
    this.commentCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt);
  static Insertable<PostRow> custom({
    Expression<String>? id,
    Expression<String>? content,
    Expression<String>? images,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<String>? scope,
    Expression<bool>? isAiGenerated,
    Expression<int>? deletedAt,
    Expression<String>? topicId,
    Expression<String>? topicName,
    Expression<bool>? allowAiReply,
    Expression<String>? replyDensity,
    Expression<String>? likeLevel,
    Expression<int>? humanLevel,
    Expression<bool>? isHot,
    Expression<int>? likeCount,
    Expression<int>? commentCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (content != null) 'content': content,
      if (images != null) 'images': images,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (scope != null) 'scope': scope,
      if (isAiGenerated != null) 'is_ai_generated': isAiGenerated,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (topicId != null) 'topic_id': topicId,
      if (topicName != null) 'topic_name': topicName,
      if (allowAiReply != null) 'allow_ai_reply': allowAiReply,
      if (replyDensity != null) 'reply_density': replyDensity,
      if (likeLevel != null) 'like_level': likeLevel,
      if (humanLevel != null) 'human_level': humanLevel,
      if (isHot != null) 'is_hot': isHot,
      if (likeCount != null) 'like_count': likeCount,
      if (commentCount != null) 'comment_count': commentCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PostsCompanion copyWith({
    Value<String>? id,
    Value<String>? content,
    Value<String>? images,
    Value<int>? createdAt,
    Value<int?>? updatedAt,
    Value<String>? scope,
    Value<bool>? isAiGenerated,
    Value<int?>? deletedAt,
    Value<String?>? topicId,
    Value<String?>? topicName,
    Value<bool>? allowAiReply,
    Value<String?>? replyDensity,
    Value<String?>? likeLevel,
    Value<int?>? humanLevel,
    Value<bool>? isHot,
    Value<int>? likeCount,
    Value<int>? commentCount,
    Value<int>? rowid,
  }) {
    return PostsCompanion(
      id: id ?? this.id,
      content: content ?? this.content,
      images: images ?? this.images,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      scope: scope ?? this.scope,
      isAiGenerated: isAiGenerated ?? this.isAiGenerated,
      deletedAt: deletedAt ?? this.deletedAt,
      topicId: topicId ?? this.topicId,
      topicName: topicName ?? this.topicName,
      allowAiReply: allowAiReply ?? this.allowAiReply,
      replyDensity: replyDensity ?? this.replyDensity,
      likeLevel: likeLevel ?? this.likeLevel,
      humanLevel: humanLevel ?? this.humanLevel,
      isHot: isHot ?? this.isHot,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (images.present) {
      map['images'] = Variable<String>(images.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (isAiGenerated.present) {
      map['is_ai_generated'] = Variable<bool>(isAiGenerated.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (topicId.present) {
      map['topic_id'] = Variable<String>(topicId.value);
    }
    if (topicName.present) {
      map['topic_name'] = Variable<String>(topicName.value);
    }
    if (allowAiReply.present) {
      map['allow_ai_reply'] = Variable<bool>(allowAiReply.value);
    }
    if (replyDensity.present) {
      map['reply_density'] = Variable<String>(replyDensity.value);
    }
    if (likeLevel.present) {
      map['like_level'] = Variable<String>(likeLevel.value);
    }
    if (humanLevel.present) {
      map['human_level'] = Variable<int>(humanLevel.value);
    }
    if (isHot.present) {
      map['is_hot'] = Variable<bool>(isHot.value);
    }
    if (likeCount.present) {
      map['like_count'] = Variable<int>(likeCount.value);
    }
    if (commentCount.present) {
      map['comment_count'] = Variable<int>(commentCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PostsCompanion(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('images: $images, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('scope: $scope, ')
          ..write('isAiGenerated: $isAiGenerated, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('topicId: $topicId, ')
          ..write('topicName: $topicName, ')
          ..write('allowAiReply: $allowAiReply, ')
          ..write('replyDensity: $replyDensity, ')
          ..write('likeLevel: $likeLevel, ')
          ..write('humanLevel: $humanLevel, ')
          ..write('isHot: $isHot, ')
          ..write('likeCount: $likeCount, ')
          ..write('commentCount: $commentCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiPersonasTable extends AiPersonas
    with TableInfo<$AiPersonasTable, AiPersonaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiPersonasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<String> avatar = GeneratedColumn<String>(
    'avatar',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bioMeta = const VerificationMeta('bio');
  @override
  late final GeneratedColumn<String> bio = GeneratedColumn<String>(
    'bio',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _languageStyleMeta = const VerificationMeta(
    'languageStyle',
  );
  @override
  late final GeneratedColumn<String> languageStyle = GeneratedColumn<String>(
    'language_style',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _toneMeta = const VerificationMeta('tone');
  @override
  late final GeneratedColumn<String> tone = GeneratedColumn<String>(
    'tone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _activeHoursMeta = const VerificationMeta(
    'activeHours',
  );
  @override
  late final GeneratedColumn<String> activeHours = GeneratedColumn<String>(
    'active_hours',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _likeProbabilityMeta = const VerificationMeta(
    'likeProbability',
  );
  @override
  late final GeneratedColumn<double> likeProbability = GeneratedColumn<double>(
    'like_probability',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.5),
  );
  static const VerificationMeta _commentProbabilityMeta =
      const VerificationMeta('commentProbability');
  @override
  late final GeneratedColumn<double> commentProbability =
      GeneratedColumn<double>(
        'comment_probability',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(0.4),
      );
  static const VerificationMeta _replyLengthMeta = const VerificationMeta(
    'replyLength',
  );
  @override
  late final GeneratedColumn<String> replyLength = GeneratedColumn<String>(
    'reply_length',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('medium'),
  );
  static const VerificationMeta _voiceModelMeta = const VerificationMeta(
    'voiceModel',
  );
  @override
  late final GeneratedColumn<String> voiceModel = GeneratedColumn<String>(
    'voice_model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('echo'),
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<int> level = GeneratedColumn<int>(
    'level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _badgesMeta = const VerificationMeta('badges');
  @override
  late final GeneratedColumn<String> badges = GeneratedColumn<String>(
    'badges',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _followersMeta = const VerificationMeta(
    'followers',
  );
  @override
  late final GeneratedColumn<int> followers = GeneratedColumn<int>(
    'followers',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _followingMeta = const VerificationMeta(
    'following',
  );
  @override
  late final GeneratedColumn<int> following = GeneratedColumn<int>(
    'following',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _personalityTypeMeta = const VerificationMeta(
    'personalityType',
  );
  @override
  late final GeneratedColumn<String> personalityType = GeneratedColumn<String>(
    'personality_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _memoryEnabledMeta = const VerificationMeta(
    'memoryEnabled',
  );
  @override
  late final GeneratedColumn<bool> memoryEnabled = GeneratedColumn<bool>(
    'memory_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("memory_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _relationshipLevelMeta = const VerificationMeta(
    'relationshipLevel',
  );
  @override
  late final GeneratedColumn<int> relationshipLevel = GeneratedColumn<int>(
    'relationship_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    avatar,
    bio,
    languageStyle,
    tone,
    activeHours,
    likeProbability,
    commentProbability,
    replyLength,
    voiceModel,
    isActive,
    scope,
    level,
    badges,
    followers,
    following,
    personalityType,
    memoryEnabled,
    relationshipLevel,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_personas';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiPersonaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('avatar')) {
      context.handle(
        _avatarMeta,
        avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta),
      );
    }
    if (data.containsKey('bio')) {
      context.handle(
        _bioMeta,
        bio.isAcceptableOrUnknown(data['bio']!, _bioMeta),
      );
    }
    if (data.containsKey('language_style')) {
      context.handle(
        _languageStyleMeta,
        languageStyle.isAcceptableOrUnknown(
          data['language_style']!,
          _languageStyleMeta,
        ),
      );
    }
    if (data.containsKey('tone')) {
      context.handle(
        _toneMeta,
        tone.isAcceptableOrUnknown(data['tone']!, _toneMeta),
      );
    }
    if (data.containsKey('active_hours')) {
      context.handle(
        _activeHoursMeta,
        activeHours.isAcceptableOrUnknown(
          data['active_hours']!,
          _activeHoursMeta,
        ),
      );
    }
    if (data.containsKey('like_probability')) {
      context.handle(
        _likeProbabilityMeta,
        likeProbability.isAcceptableOrUnknown(
          data['like_probability']!,
          _likeProbabilityMeta,
        ),
      );
    }
    if (data.containsKey('comment_probability')) {
      context.handle(
        _commentProbabilityMeta,
        commentProbability.isAcceptableOrUnknown(
          data['comment_probability']!,
          _commentProbabilityMeta,
        ),
      );
    }
    if (data.containsKey('reply_length')) {
      context.handle(
        _replyLengthMeta,
        replyLength.isAcceptableOrUnknown(
          data['reply_length']!,
          _replyLengthMeta,
        ),
      );
    }
    if (data.containsKey('voice_model')) {
      context.handle(
        _voiceModelMeta,
        voiceModel.isAcceptableOrUnknown(data['voice_model']!, _voiceModelMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    }
    if (data.containsKey('badges')) {
      context.handle(
        _badgesMeta,
        badges.isAcceptableOrUnknown(data['badges']!, _badgesMeta),
      );
    }
    if (data.containsKey('followers')) {
      context.handle(
        _followersMeta,
        followers.isAcceptableOrUnknown(data['followers']!, _followersMeta),
      );
    }
    if (data.containsKey('following')) {
      context.handle(
        _followingMeta,
        following.isAcceptableOrUnknown(data['following']!, _followingMeta),
      );
    }
    if (data.containsKey('personality_type')) {
      context.handle(
        _personalityTypeMeta,
        personalityType.isAcceptableOrUnknown(
          data['personality_type']!,
          _personalityTypeMeta,
        ),
      );
    }
    if (data.containsKey('memory_enabled')) {
      context.handle(
        _memoryEnabledMeta,
        memoryEnabled.isAcceptableOrUnknown(
          data['memory_enabled']!,
          _memoryEnabledMeta,
        ),
      );
    }
    if (data.containsKey('relationship_level')) {
      context.handle(
        _relationshipLevelMeta,
        relationshipLevel.isAcceptableOrUnknown(
          data['relationship_level']!,
          _relationshipLevelMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiPersonaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiPersonaRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      avatar: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar'],
      )!,
      bio: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bio'],
      )!,
      languageStyle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language_style'],
      )!,
      tone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tone'],
      )!,
      activeHours: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}active_hours'],
      )!,
      likeProbability: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}like_probability'],
      )!,
      commentProbability: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}comment_probability'],
      )!,
      replyLength: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_length'],
      )!,
      voiceModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}voice_model'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}level'],
      )!,
      badges: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}badges'],
      )!,
      followers: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}followers'],
      )!,
      following: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}following'],
      )!,
      personalityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}personality_type'],
      )!,
      memoryEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}memory_enabled'],
      )!,
      relationshipLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}relationship_level'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $AiPersonasTable createAlias(String alias) {
    return $AiPersonasTable(attachedDatabase, alias);
  }
}

class AiPersonaRow extends DataClass implements Insertable<AiPersonaRow> {
  final String id;
  final String name;
  final String avatar;
  final String bio;
  final String languageStyle;
  final String tone;
  final String activeHours;
  final double likeProbability;
  final double commentProbability;
  final String replyLength;
  final String voiceModel;
  final bool isActive;
  final String scope;
  final int level;
  final String badges;
  final int followers;
  final int following;
  final String personalityType;
  final bool memoryEnabled;
  final int relationshipLevel;
  final int? deletedAt;
  const AiPersonaRow({
    required this.id,
    required this.name,
    required this.avatar,
    required this.bio,
    required this.languageStyle,
    required this.tone,
    required this.activeHours,
    required this.likeProbability,
    required this.commentProbability,
    required this.replyLength,
    required this.voiceModel,
    required this.isActive,
    required this.scope,
    required this.level,
    required this.badges,
    required this.followers,
    required this.following,
    required this.personalityType,
    required this.memoryEnabled,
    required this.relationshipLevel,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['avatar'] = Variable<String>(avatar);
    map['bio'] = Variable<String>(bio);
    map['language_style'] = Variable<String>(languageStyle);
    map['tone'] = Variable<String>(tone);
    map['active_hours'] = Variable<String>(activeHours);
    map['like_probability'] = Variable<double>(likeProbability);
    map['comment_probability'] = Variable<double>(commentProbability);
    map['reply_length'] = Variable<String>(replyLength);
    map['voice_model'] = Variable<String>(voiceModel);
    map['is_active'] = Variable<bool>(isActive);
    map['scope'] = Variable<String>(scope);
    map['level'] = Variable<int>(level);
    map['badges'] = Variable<String>(badges);
    map['followers'] = Variable<int>(followers);
    map['following'] = Variable<int>(following);
    map['personality_type'] = Variable<String>(personalityType);
    map['memory_enabled'] = Variable<bool>(memoryEnabled);
    map['relationship_level'] = Variable<int>(relationshipLevel);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    return map;
  }

  AiPersonasCompanion toCompanion(bool nullToAbsent) {
    return AiPersonasCompanion(
      id: Value(id),
      name: Value(name),
      avatar: Value(avatar),
      bio: Value(bio),
      languageStyle: Value(languageStyle),
      tone: Value(tone),
      activeHours: Value(activeHours),
      likeProbability: Value(likeProbability),
      commentProbability: Value(commentProbability),
      replyLength: Value(replyLength),
      voiceModel: Value(voiceModel),
      isActive: Value(isActive),
      scope: Value(scope),
      level: Value(level),
      badges: Value(badges),
      followers: Value(followers),
      following: Value(following),
      personalityType: Value(personalityType),
      memoryEnabled: Value(memoryEnabled),
      relationshipLevel: Value(relationshipLevel),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory AiPersonaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiPersonaRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      avatar: serializer.fromJson<String>(json['avatar']),
      bio: serializer.fromJson<String>(json['bio']),
      languageStyle: serializer.fromJson<String>(json['languageStyle']),
      tone: serializer.fromJson<String>(json['tone']),
      activeHours: serializer.fromJson<String>(json['activeHours']),
      likeProbability: serializer.fromJson<double>(json['likeProbability']),
      commentProbability: serializer.fromJson<double>(
        json['commentProbability'],
      ),
      replyLength: serializer.fromJson<String>(json['replyLength']),
      voiceModel: serializer.fromJson<String>(json['voiceModel']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      scope: serializer.fromJson<String>(json['scope']),
      level: serializer.fromJson<int>(json['level']),
      badges: serializer.fromJson<String>(json['badges']),
      followers: serializer.fromJson<int>(json['followers']),
      following: serializer.fromJson<int>(json['following']),
      personalityType: serializer.fromJson<String>(json['personalityType']),
      memoryEnabled: serializer.fromJson<bool>(json['memoryEnabled']),
      relationshipLevel: serializer.fromJson<int>(json['relationshipLevel']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'avatar': serializer.toJson<String>(avatar),
      'bio': serializer.toJson<String>(bio),
      'languageStyle': serializer.toJson<String>(languageStyle),
      'tone': serializer.toJson<String>(tone),
      'activeHours': serializer.toJson<String>(activeHours),
      'likeProbability': serializer.toJson<double>(likeProbability),
      'commentProbability': serializer.toJson<double>(commentProbability),
      'replyLength': serializer.toJson<String>(replyLength),
      'voiceModel': serializer.toJson<String>(voiceModel),
      'isActive': serializer.toJson<bool>(isActive),
      'scope': serializer.toJson<String>(scope),
      'level': serializer.toJson<int>(level),
      'badges': serializer.toJson<String>(badges),
      'followers': serializer.toJson<int>(followers),
      'following': serializer.toJson<int>(following),
      'personalityType': serializer.toJson<String>(personalityType),
      'memoryEnabled': serializer.toJson<bool>(memoryEnabled),
      'relationshipLevel': serializer.toJson<int>(relationshipLevel),
      'deletedAt': serializer.toJson<int?>(deletedAt),
    };
  }

  AiPersonaRow copyWith({
    String? id,
    String? name,
    String? avatar,
    String? bio,
    String? languageStyle,
    String? tone,
    String? activeHours,
    double? likeProbability,
    double? commentProbability,
    String? replyLength,
    String? voiceModel,
    bool? isActive,
    String? scope,
    int? level,
    String? badges,
    int? followers,
    int? following,
    String? personalityType,
    bool? memoryEnabled,
    int? relationshipLevel,
    Value<int?> deletedAt = const Value.absent(),
  }) => AiPersonaRow(
    id: id ?? this.id,
    name: name ?? this.name,
    avatar: avatar ?? this.avatar,
    bio: bio ?? this.bio,
    languageStyle: languageStyle ?? this.languageStyle,
    tone: tone ?? this.tone,
    activeHours: activeHours ?? this.activeHours,
    likeProbability: likeProbability ?? this.likeProbability,
    commentProbability: commentProbability ?? this.commentProbability,
    replyLength: replyLength ?? this.replyLength,
    voiceModel: voiceModel ?? this.voiceModel,
    isActive: isActive ?? this.isActive,
    scope: scope ?? this.scope,
    level: level ?? this.level,
    badges: badges ?? this.badges,
    followers: followers ?? this.followers,
    following: following ?? this.following,
    personalityType: personalityType ?? this.personalityType,
    memoryEnabled: memoryEnabled ?? this.memoryEnabled,
    relationshipLevel: relationshipLevel ?? this.relationshipLevel,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  AiPersonaRow copyWithCompanion(AiPersonasCompanion data) {
    return AiPersonaRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      avatar: data.avatar.present ? data.avatar.value : this.avatar,
      bio: data.bio.present ? data.bio.value : this.bio,
      languageStyle: data.languageStyle.present
          ? data.languageStyle.value
          : this.languageStyle,
      tone: data.tone.present ? data.tone.value : this.tone,
      activeHours: data.activeHours.present
          ? data.activeHours.value
          : this.activeHours,
      likeProbability: data.likeProbability.present
          ? data.likeProbability.value
          : this.likeProbability,
      commentProbability: data.commentProbability.present
          ? data.commentProbability.value
          : this.commentProbability,
      replyLength: data.replyLength.present
          ? data.replyLength.value
          : this.replyLength,
      voiceModel: data.voiceModel.present
          ? data.voiceModel.value
          : this.voiceModel,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      scope: data.scope.present ? data.scope.value : this.scope,
      level: data.level.present ? data.level.value : this.level,
      badges: data.badges.present ? data.badges.value : this.badges,
      followers: data.followers.present ? data.followers.value : this.followers,
      following: data.following.present ? data.following.value : this.following,
      personalityType: data.personalityType.present
          ? data.personalityType.value
          : this.personalityType,
      memoryEnabled: data.memoryEnabled.present
          ? data.memoryEnabled.value
          : this.memoryEnabled,
      relationshipLevel: data.relationshipLevel.present
          ? data.relationshipLevel.value
          : this.relationshipLevel,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiPersonaRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatar: $avatar, ')
          ..write('bio: $bio, ')
          ..write('languageStyle: $languageStyle, ')
          ..write('tone: $tone, ')
          ..write('activeHours: $activeHours, ')
          ..write('likeProbability: $likeProbability, ')
          ..write('commentProbability: $commentProbability, ')
          ..write('replyLength: $replyLength, ')
          ..write('voiceModel: $voiceModel, ')
          ..write('isActive: $isActive, ')
          ..write('scope: $scope, ')
          ..write('level: $level, ')
          ..write('badges: $badges, ')
          ..write('followers: $followers, ')
          ..write('following: $following, ')
          ..write('personalityType: $personalityType, ')
          ..write('memoryEnabled: $memoryEnabled, ')
          ..write('relationshipLevel: $relationshipLevel, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    avatar,
    bio,
    languageStyle,
    tone,
    activeHours,
    likeProbability,
    commentProbability,
    replyLength,
    voiceModel,
    isActive,
    scope,
    level,
    badges,
    followers,
    following,
    personalityType,
    memoryEnabled,
    relationshipLevel,
    deletedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiPersonaRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.avatar == this.avatar &&
          other.bio == this.bio &&
          other.languageStyle == this.languageStyle &&
          other.tone == this.tone &&
          other.activeHours == this.activeHours &&
          other.likeProbability == this.likeProbability &&
          other.commentProbability == this.commentProbability &&
          other.replyLength == this.replyLength &&
          other.voiceModel == this.voiceModel &&
          other.isActive == this.isActive &&
          other.scope == this.scope &&
          other.level == this.level &&
          other.badges == this.badges &&
          other.followers == this.followers &&
          other.following == this.following &&
          other.personalityType == this.personalityType &&
          other.memoryEnabled == this.memoryEnabled &&
          other.relationshipLevel == this.relationshipLevel &&
          other.deletedAt == this.deletedAt);
}

class AiPersonasCompanion extends UpdateCompanion<AiPersonaRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> avatar;
  final Value<String> bio;
  final Value<String> languageStyle;
  final Value<String> tone;
  final Value<String> activeHours;
  final Value<double> likeProbability;
  final Value<double> commentProbability;
  final Value<String> replyLength;
  final Value<String> voiceModel;
  final Value<bool> isActive;
  final Value<String> scope;
  final Value<int> level;
  final Value<String> badges;
  final Value<int> followers;
  final Value<int> following;
  final Value<String> personalityType;
  final Value<bool> memoryEnabled;
  final Value<int> relationshipLevel;
  final Value<int?> deletedAt;
  final Value<int> rowid;
  const AiPersonasCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.avatar = const Value.absent(),
    this.bio = const Value.absent(),
    this.languageStyle = const Value.absent(),
    this.tone = const Value.absent(),
    this.activeHours = const Value.absent(),
    this.likeProbability = const Value.absent(),
    this.commentProbability = const Value.absent(),
    this.replyLength = const Value.absent(),
    this.voiceModel = const Value.absent(),
    this.isActive = const Value.absent(),
    this.scope = const Value.absent(),
    this.level = const Value.absent(),
    this.badges = const Value.absent(),
    this.followers = const Value.absent(),
    this.following = const Value.absent(),
    this.personalityType = const Value.absent(),
    this.memoryEnabled = const Value.absent(),
    this.relationshipLevel = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiPersonasCompanion.insert({
    required String id,
    required String name,
    this.avatar = const Value.absent(),
    this.bio = const Value.absent(),
    this.languageStyle = const Value.absent(),
    this.tone = const Value.absent(),
    this.activeHours = const Value.absent(),
    this.likeProbability = const Value.absent(),
    this.commentProbability = const Value.absent(),
    this.replyLength = const Value.absent(),
    this.voiceModel = const Value.absent(),
    this.isActive = const Value.absent(),
    this.scope = const Value.absent(),
    this.level = const Value.absent(),
    this.badges = const Value.absent(),
    this.followers = const Value.absent(),
    this.following = const Value.absent(),
    this.personalityType = const Value.absent(),
    this.memoryEnabled = const Value.absent(),
    this.relationshipLevel = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<AiPersonaRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? avatar,
    Expression<String>? bio,
    Expression<String>? languageStyle,
    Expression<String>? tone,
    Expression<String>? activeHours,
    Expression<double>? likeProbability,
    Expression<double>? commentProbability,
    Expression<String>? replyLength,
    Expression<String>? voiceModel,
    Expression<bool>? isActive,
    Expression<String>? scope,
    Expression<int>? level,
    Expression<String>? badges,
    Expression<int>? followers,
    Expression<int>? following,
    Expression<String>? personalityType,
    Expression<bool>? memoryEnabled,
    Expression<int>? relationshipLevel,
    Expression<int>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (avatar != null) 'avatar': avatar,
      if (bio != null) 'bio': bio,
      if (languageStyle != null) 'language_style': languageStyle,
      if (tone != null) 'tone': tone,
      if (activeHours != null) 'active_hours': activeHours,
      if (likeProbability != null) 'like_probability': likeProbability,
      if (commentProbability != null) 'comment_probability': commentProbability,
      if (replyLength != null) 'reply_length': replyLength,
      if (voiceModel != null) 'voice_model': voiceModel,
      if (isActive != null) 'is_active': isActive,
      if (scope != null) 'scope': scope,
      if (level != null) 'level': level,
      if (badges != null) 'badges': badges,
      if (followers != null) 'followers': followers,
      if (following != null) 'following': following,
      if (personalityType != null) 'personality_type': personalityType,
      if (memoryEnabled != null) 'memory_enabled': memoryEnabled,
      if (relationshipLevel != null) 'relationship_level': relationshipLevel,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiPersonasCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? avatar,
    Value<String>? bio,
    Value<String>? languageStyle,
    Value<String>? tone,
    Value<String>? activeHours,
    Value<double>? likeProbability,
    Value<double>? commentProbability,
    Value<String>? replyLength,
    Value<String>? voiceModel,
    Value<bool>? isActive,
    Value<String>? scope,
    Value<int>? level,
    Value<String>? badges,
    Value<int>? followers,
    Value<int>? following,
    Value<String>? personalityType,
    Value<bool>? memoryEnabled,
    Value<int>? relationshipLevel,
    Value<int?>? deletedAt,
    Value<int>? rowid,
  }) {
    return AiPersonasCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      bio: bio ?? this.bio,
      languageStyle: languageStyle ?? this.languageStyle,
      tone: tone ?? this.tone,
      activeHours: activeHours ?? this.activeHours,
      likeProbability: likeProbability ?? this.likeProbability,
      commentProbability: commentProbability ?? this.commentProbability,
      replyLength: replyLength ?? this.replyLength,
      voiceModel: voiceModel ?? this.voiceModel,
      isActive: isActive ?? this.isActive,
      scope: scope ?? this.scope,
      level: level ?? this.level,
      badges: badges ?? this.badges,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      personalityType: personalityType ?? this.personalityType,
      memoryEnabled: memoryEnabled ?? this.memoryEnabled,
      relationshipLevel: relationshipLevel ?? this.relationshipLevel,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (avatar.present) {
      map['avatar'] = Variable<String>(avatar.value);
    }
    if (bio.present) {
      map['bio'] = Variable<String>(bio.value);
    }
    if (languageStyle.present) {
      map['language_style'] = Variable<String>(languageStyle.value);
    }
    if (tone.present) {
      map['tone'] = Variable<String>(tone.value);
    }
    if (activeHours.present) {
      map['active_hours'] = Variable<String>(activeHours.value);
    }
    if (likeProbability.present) {
      map['like_probability'] = Variable<double>(likeProbability.value);
    }
    if (commentProbability.present) {
      map['comment_probability'] = Variable<double>(commentProbability.value);
    }
    if (replyLength.present) {
      map['reply_length'] = Variable<String>(replyLength.value);
    }
    if (voiceModel.present) {
      map['voice_model'] = Variable<String>(voiceModel.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (level.present) {
      map['level'] = Variable<int>(level.value);
    }
    if (badges.present) {
      map['badges'] = Variable<String>(badges.value);
    }
    if (followers.present) {
      map['followers'] = Variable<int>(followers.value);
    }
    if (following.present) {
      map['following'] = Variable<int>(following.value);
    }
    if (personalityType.present) {
      map['personality_type'] = Variable<String>(personalityType.value);
    }
    if (memoryEnabled.present) {
      map['memory_enabled'] = Variable<bool>(memoryEnabled.value);
    }
    if (relationshipLevel.present) {
      map['relationship_level'] = Variable<int>(relationshipLevel.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiPersonasCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatar: $avatar, ')
          ..write('bio: $bio, ')
          ..write('languageStyle: $languageStyle, ')
          ..write('tone: $tone, ')
          ..write('activeHours: $activeHours, ')
          ..write('likeProbability: $likeProbability, ')
          ..write('commentProbability: $commentProbability, ')
          ..write('replyLength: $replyLength, ')
          ..write('voiceModel: $voiceModel, ')
          ..write('isActive: $isActive, ')
          ..write('scope: $scope, ')
          ..write('level: $level, ')
          ..write('badges: $badges, ')
          ..write('followers: $followers, ')
          ..write('following: $following, ')
          ..write('personalityType: $personalityType, ')
          ..write('memoryEnabled: $memoryEnabled, ')
          ..write('relationshipLevel: $relationshipLevel, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiInteractionsTable extends AiInteractions
    with TableInfo<$AiInteractionsTable, AiInteractionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiInteractionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _postIdMeta = const VerificationMeta('postId');
  @override
  late final GeneratedColumn<String> postId = GeneratedColumn<String>(
    'post_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES posts (id)',
    ),
  );
  static const VerificationMeta _personaIdMeta = const VerificationMeta(
    'personaId',
  );
  @override
  late final GeneratedColumn<String> personaId = GeneratedColumn<String>(
    'persona_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES ai_personas (id)',
    ),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
    'media_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _voicePathMeta = const VerificationMeta(
    'voicePath',
  );
  @override
  late final GeneratedColumn<String> voicePath = GeneratedColumn<String>(
    'voice_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _transcriptMeta = const VerificationMeta(
    'transcript',
  );
  @override
  late final GeneratedColumn<String> transcript = GeneratedColumn<String>(
    'transcript',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _voiceDurationMsMeta = const VerificationMeta(
    'voiceDurationMs',
  );
  @override
  late final GeneratedColumn<int> voiceDurationMs = GeneratedColumn<int>(
    'voice_duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scheduledAtMeta = const VerificationMeta(
    'scheduledAt',
  );
  @override
  late final GeneratedColumn<int> scheduledAt = GeneratedColumn<int>(
    'scheduled_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _executedAtMeta = const VerificationMeta(
    'executedAt',
  );
  @override
  late final GeneratedColumn<int> executedAt = GeneratedColumn<int>(
    'executed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _isAiMeta = const VerificationMeta('isAi');
  @override
  late final GeneratedColumn<bool> isAi = GeneratedColumn<bool>(
    'is_ai',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_ai" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('echo'),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _likeCountMeta = const VerificationMeta(
    'likeCount',
  );
  @override
  late final GeneratedColumn<int> likeCount = GeneratedColumn<int>(
    'like_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    postId,
    personaId,
    type,
    mediaType,
    content,
    voicePath,
    transcript,
    voiceDurationMs,
    scheduledAt,
    executedAt,
    status,
    isAi,
    scope,
    parentId,
    likeCount,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_interactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiInteractionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('post_id')) {
      context.handle(
        _postIdMeta,
        postId.isAcceptableOrUnknown(data['post_id']!, _postIdMeta),
      );
    } else if (isInserting) {
      context.missing(_postIdMeta);
    }
    if (data.containsKey('persona_id')) {
      context.handle(
        _personaIdMeta,
        personaId.isAcceptableOrUnknown(data['persona_id']!, _personaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personaIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('voice_path')) {
      context.handle(
        _voicePathMeta,
        voicePath.isAcceptableOrUnknown(data['voice_path']!, _voicePathMeta),
      );
    }
    if (data.containsKey('transcript')) {
      context.handle(
        _transcriptMeta,
        transcript.isAcceptableOrUnknown(data['transcript']!, _transcriptMeta),
      );
    }
    if (data.containsKey('voice_duration_ms')) {
      context.handle(
        _voiceDurationMsMeta,
        voiceDurationMs.isAcceptableOrUnknown(
          data['voice_duration_ms']!,
          _voiceDurationMsMeta,
        ),
      );
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
        _scheduledAtMeta,
        scheduledAt.isAcceptableOrUnknown(
          data['scheduled_at']!,
          _scheduledAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledAtMeta);
    }
    if (data.containsKey('executed_at')) {
      context.handle(
        _executedAtMeta,
        executedAt.isAcceptableOrUnknown(data['executed_at']!, _executedAtMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('is_ai')) {
      context.handle(
        _isAiMeta,
        isAi.isAcceptableOrUnknown(data['is_ai']!, _isAiMeta),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('like_count')) {
      context.handle(
        _likeCountMeta,
        likeCount.isAcceptableOrUnknown(data['like_count']!, _likeCountMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiInteractionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiInteractionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      postId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}post_id'],
      )!,
      personaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}persona_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      mediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_type'],
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      ),
      voicePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}voice_path'],
      ),
      transcript: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transcript'],
      ),
      voiceDurationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}voice_duration_ms'],
      ),
      scheduledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scheduled_at'],
      )!,
      executedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}executed_at'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      isAi: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_ai'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      likeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}like_count'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $AiInteractionsTable createAlias(String alias) {
    return $AiInteractionsTable(attachedDatabase, alias);
  }
}

class AiInteractionRow extends DataClass
    implements Insertable<AiInteractionRow> {
  final String id;
  final String postId;
  final String personaId;

  /// like / comment / follow / message / repost
  final String type;

  /// text / voice / image / emoji
  final String? mediaType;
  final String? content;
  final String? voicePath;
  final String? transcript;
  final int? voiceDurationMs;
  final int scheduledAt;
  final int? executedAt;

  /// pending / done / cancelled
  final String status;
  final bool isAi;
  final String scope;
  final String? parentId;
  final int likeCount;
  final int? deletedAt;
  const AiInteractionRow({
    required this.id,
    required this.postId,
    required this.personaId,
    required this.type,
    this.mediaType,
    this.content,
    this.voicePath,
    this.transcript,
    this.voiceDurationMs,
    required this.scheduledAt,
    this.executedAt,
    required this.status,
    required this.isAi,
    required this.scope,
    this.parentId,
    required this.likeCount,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['post_id'] = Variable<String>(postId);
    map['persona_id'] = Variable<String>(personaId);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || mediaType != null) {
      map['media_type'] = Variable<String>(mediaType);
    }
    if (!nullToAbsent || content != null) {
      map['content'] = Variable<String>(content);
    }
    if (!nullToAbsent || voicePath != null) {
      map['voice_path'] = Variable<String>(voicePath);
    }
    if (!nullToAbsent || transcript != null) {
      map['transcript'] = Variable<String>(transcript);
    }
    if (!nullToAbsent || voiceDurationMs != null) {
      map['voice_duration_ms'] = Variable<int>(voiceDurationMs);
    }
    map['scheduled_at'] = Variable<int>(scheduledAt);
    if (!nullToAbsent || executedAt != null) {
      map['executed_at'] = Variable<int>(executedAt);
    }
    map['status'] = Variable<String>(status);
    map['is_ai'] = Variable<bool>(isAi);
    map['scope'] = Variable<String>(scope);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['like_count'] = Variable<int>(likeCount);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    return map;
  }

  AiInteractionsCompanion toCompanion(bool nullToAbsent) {
    return AiInteractionsCompanion(
      id: Value(id),
      postId: Value(postId),
      personaId: Value(personaId),
      type: Value(type),
      mediaType: mediaType == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaType),
      content: content == null && nullToAbsent
          ? const Value.absent()
          : Value(content),
      voicePath: voicePath == null && nullToAbsent
          ? const Value.absent()
          : Value(voicePath),
      transcript: transcript == null && nullToAbsent
          ? const Value.absent()
          : Value(transcript),
      voiceDurationMs: voiceDurationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(voiceDurationMs),
      scheduledAt: Value(scheduledAt),
      executedAt: executedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(executedAt),
      status: Value(status),
      isAi: Value(isAi),
      scope: Value(scope),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      likeCount: Value(likeCount),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory AiInteractionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiInteractionRow(
      id: serializer.fromJson<String>(json['id']),
      postId: serializer.fromJson<String>(json['postId']),
      personaId: serializer.fromJson<String>(json['personaId']),
      type: serializer.fromJson<String>(json['type']),
      mediaType: serializer.fromJson<String?>(json['mediaType']),
      content: serializer.fromJson<String?>(json['content']),
      voicePath: serializer.fromJson<String?>(json['voicePath']),
      transcript: serializer.fromJson<String?>(json['transcript']),
      voiceDurationMs: serializer.fromJson<int?>(json['voiceDurationMs']),
      scheduledAt: serializer.fromJson<int>(json['scheduledAt']),
      executedAt: serializer.fromJson<int?>(json['executedAt']),
      status: serializer.fromJson<String>(json['status']),
      isAi: serializer.fromJson<bool>(json['isAi']),
      scope: serializer.fromJson<String>(json['scope']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      likeCount: serializer.fromJson<int>(json['likeCount']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'postId': serializer.toJson<String>(postId),
      'personaId': serializer.toJson<String>(personaId),
      'type': serializer.toJson<String>(type),
      'mediaType': serializer.toJson<String?>(mediaType),
      'content': serializer.toJson<String?>(content),
      'voicePath': serializer.toJson<String?>(voicePath),
      'transcript': serializer.toJson<String?>(transcript),
      'voiceDurationMs': serializer.toJson<int?>(voiceDurationMs),
      'scheduledAt': serializer.toJson<int>(scheduledAt),
      'executedAt': serializer.toJson<int?>(executedAt),
      'status': serializer.toJson<String>(status),
      'isAi': serializer.toJson<bool>(isAi),
      'scope': serializer.toJson<String>(scope),
      'parentId': serializer.toJson<String?>(parentId),
      'likeCount': serializer.toJson<int>(likeCount),
      'deletedAt': serializer.toJson<int?>(deletedAt),
    };
  }

  AiInteractionRow copyWith({
    String? id,
    String? postId,
    String? personaId,
    String? type,
    Value<String?> mediaType = const Value.absent(),
    Value<String?> content = const Value.absent(),
    Value<String?> voicePath = const Value.absent(),
    Value<String?> transcript = const Value.absent(),
    Value<int?> voiceDurationMs = const Value.absent(),
    int? scheduledAt,
    Value<int?> executedAt = const Value.absent(),
    String? status,
    bool? isAi,
    String? scope,
    Value<String?> parentId = const Value.absent(),
    int? likeCount,
    Value<int?> deletedAt = const Value.absent(),
  }) => AiInteractionRow(
    id: id ?? this.id,
    postId: postId ?? this.postId,
    personaId: personaId ?? this.personaId,
    type: type ?? this.type,
    mediaType: mediaType.present ? mediaType.value : this.mediaType,
    content: content.present ? content.value : this.content,
    voicePath: voicePath.present ? voicePath.value : this.voicePath,
    transcript: transcript.present ? transcript.value : this.transcript,
    voiceDurationMs: voiceDurationMs.present
        ? voiceDurationMs.value
        : this.voiceDurationMs,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    executedAt: executedAt.present ? executedAt.value : this.executedAt,
    status: status ?? this.status,
    isAi: isAi ?? this.isAi,
    scope: scope ?? this.scope,
    parentId: parentId.present ? parentId.value : this.parentId,
    likeCount: likeCount ?? this.likeCount,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  AiInteractionRow copyWithCompanion(AiInteractionsCompanion data) {
    return AiInteractionRow(
      id: data.id.present ? data.id.value : this.id,
      postId: data.postId.present ? data.postId.value : this.postId,
      personaId: data.personaId.present ? data.personaId.value : this.personaId,
      type: data.type.present ? data.type.value : this.type,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      content: data.content.present ? data.content.value : this.content,
      voicePath: data.voicePath.present ? data.voicePath.value : this.voicePath,
      transcript: data.transcript.present
          ? data.transcript.value
          : this.transcript,
      voiceDurationMs: data.voiceDurationMs.present
          ? data.voiceDurationMs.value
          : this.voiceDurationMs,
      scheduledAt: data.scheduledAt.present
          ? data.scheduledAt.value
          : this.scheduledAt,
      executedAt: data.executedAt.present
          ? data.executedAt.value
          : this.executedAt,
      status: data.status.present ? data.status.value : this.status,
      isAi: data.isAi.present ? data.isAi.value : this.isAi,
      scope: data.scope.present ? data.scope.value : this.scope,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      likeCount: data.likeCount.present ? data.likeCount.value : this.likeCount,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiInteractionRow(')
          ..write('id: $id, ')
          ..write('postId: $postId, ')
          ..write('personaId: $personaId, ')
          ..write('type: $type, ')
          ..write('mediaType: $mediaType, ')
          ..write('content: $content, ')
          ..write('voicePath: $voicePath, ')
          ..write('transcript: $transcript, ')
          ..write('voiceDurationMs: $voiceDurationMs, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('executedAt: $executedAt, ')
          ..write('status: $status, ')
          ..write('isAi: $isAi, ')
          ..write('scope: $scope, ')
          ..write('parentId: $parentId, ')
          ..write('likeCount: $likeCount, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    postId,
    personaId,
    type,
    mediaType,
    content,
    voicePath,
    transcript,
    voiceDurationMs,
    scheduledAt,
    executedAt,
    status,
    isAi,
    scope,
    parentId,
    likeCount,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiInteractionRow &&
          other.id == this.id &&
          other.postId == this.postId &&
          other.personaId == this.personaId &&
          other.type == this.type &&
          other.mediaType == this.mediaType &&
          other.content == this.content &&
          other.voicePath == this.voicePath &&
          other.transcript == this.transcript &&
          other.voiceDurationMs == this.voiceDurationMs &&
          other.scheduledAt == this.scheduledAt &&
          other.executedAt == this.executedAt &&
          other.status == this.status &&
          other.isAi == this.isAi &&
          other.scope == this.scope &&
          other.parentId == this.parentId &&
          other.likeCount == this.likeCount &&
          other.deletedAt == this.deletedAt);
}

class AiInteractionsCompanion extends UpdateCompanion<AiInteractionRow> {
  final Value<String> id;
  final Value<String> postId;
  final Value<String> personaId;
  final Value<String> type;
  final Value<String?> mediaType;
  final Value<String?> content;
  final Value<String?> voicePath;
  final Value<String?> transcript;
  final Value<int?> voiceDurationMs;
  final Value<int> scheduledAt;
  final Value<int?> executedAt;
  final Value<String> status;
  final Value<bool> isAi;
  final Value<String> scope;
  final Value<String?> parentId;
  final Value<int> likeCount;
  final Value<int?> deletedAt;
  final Value<int> rowid;
  const AiInteractionsCompanion({
    this.id = const Value.absent(),
    this.postId = const Value.absent(),
    this.personaId = const Value.absent(),
    this.type = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.content = const Value.absent(),
    this.voicePath = const Value.absent(),
    this.transcript = const Value.absent(),
    this.voiceDurationMs = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.executedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.isAi = const Value.absent(),
    this.scope = const Value.absent(),
    this.parentId = const Value.absent(),
    this.likeCount = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiInteractionsCompanion.insert({
    required String id,
    required String postId,
    required String personaId,
    required String type,
    this.mediaType = const Value.absent(),
    this.content = const Value.absent(),
    this.voicePath = const Value.absent(),
    this.transcript = const Value.absent(),
    this.voiceDurationMs = const Value.absent(),
    required int scheduledAt,
    this.executedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.isAi = const Value.absent(),
    this.scope = const Value.absent(),
    this.parentId = const Value.absent(),
    this.likeCount = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       postId = Value(postId),
       personaId = Value(personaId),
       type = Value(type),
       scheduledAt = Value(scheduledAt);
  static Insertable<AiInteractionRow> custom({
    Expression<String>? id,
    Expression<String>? postId,
    Expression<String>? personaId,
    Expression<String>? type,
    Expression<String>? mediaType,
    Expression<String>? content,
    Expression<String>? voicePath,
    Expression<String>? transcript,
    Expression<int>? voiceDurationMs,
    Expression<int>? scheduledAt,
    Expression<int>? executedAt,
    Expression<String>? status,
    Expression<bool>? isAi,
    Expression<String>? scope,
    Expression<String>? parentId,
    Expression<int>? likeCount,
    Expression<int>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (postId != null) 'post_id': postId,
      if (personaId != null) 'persona_id': personaId,
      if (type != null) 'type': type,
      if (mediaType != null) 'media_type': mediaType,
      if (content != null) 'content': content,
      if (voicePath != null) 'voice_path': voicePath,
      if (transcript != null) 'transcript': transcript,
      if (voiceDurationMs != null) 'voice_duration_ms': voiceDurationMs,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (executedAt != null) 'executed_at': executedAt,
      if (status != null) 'status': status,
      if (isAi != null) 'is_ai': isAi,
      if (scope != null) 'scope': scope,
      if (parentId != null) 'parent_id': parentId,
      if (likeCount != null) 'like_count': likeCount,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiInteractionsCompanion copyWith({
    Value<String>? id,
    Value<String>? postId,
    Value<String>? personaId,
    Value<String>? type,
    Value<String?>? mediaType,
    Value<String?>? content,
    Value<String?>? voicePath,
    Value<String?>? transcript,
    Value<int?>? voiceDurationMs,
    Value<int>? scheduledAt,
    Value<int?>? executedAt,
    Value<String>? status,
    Value<bool>? isAi,
    Value<String>? scope,
    Value<String?>? parentId,
    Value<int>? likeCount,
    Value<int?>? deletedAt,
    Value<int>? rowid,
  }) {
    return AiInteractionsCompanion(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      personaId: personaId ?? this.personaId,
      type: type ?? this.type,
      mediaType: mediaType ?? this.mediaType,
      content: content ?? this.content,
      voicePath: voicePath ?? this.voicePath,
      transcript: transcript ?? this.transcript,
      voiceDurationMs: voiceDurationMs ?? this.voiceDurationMs,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      executedAt: executedAt ?? this.executedAt,
      status: status ?? this.status,
      isAi: isAi ?? this.isAi,
      scope: scope ?? this.scope,
      parentId: parentId ?? this.parentId,
      likeCount: likeCount ?? this.likeCount,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (postId.present) {
      map['post_id'] = Variable<String>(postId.value);
    }
    if (personaId.present) {
      map['persona_id'] = Variable<String>(personaId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (voicePath.present) {
      map['voice_path'] = Variable<String>(voicePath.value);
    }
    if (transcript.present) {
      map['transcript'] = Variable<String>(transcript.value);
    }
    if (voiceDurationMs.present) {
      map['voice_duration_ms'] = Variable<int>(voiceDurationMs.value);
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<int>(scheduledAt.value);
    }
    if (executedAt.present) {
      map['executed_at'] = Variable<int>(executedAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (isAi.present) {
      map['is_ai'] = Variable<bool>(isAi.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (likeCount.present) {
      map['like_count'] = Variable<int>(likeCount.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiInteractionsCompanion(')
          ..write('id: $id, ')
          ..write('postId: $postId, ')
          ..write('personaId: $personaId, ')
          ..write('type: $type, ')
          ..write('mediaType: $mediaType, ')
          ..write('content: $content, ')
          ..write('voicePath: $voicePath, ')
          ..write('transcript: $transcript, ')
          ..write('voiceDurationMs: $voiceDurationMs, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('executedAt: $executedAt, ')
          ..write('status: $status, ')
          ..write('isAi: $isAi, ')
          ..write('scope: $scope, ')
          ..write('parentId: $parentId, ')
          ..write('likeCount: $likeCount, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AnalysisResultsTable extends AnalysisResults
    with TableInfo<$AnalysisResultsTable, AnalysisResultRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnalysisResultsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _postIdMeta = const VerificationMeta('postId');
  @override
  late final GeneratedColumn<String> postId = GeneratedColumn<String>(
    'post_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES posts (id)',
    ),
  );
  static const VerificationMeta _imageDescriptionMeta = const VerificationMeta(
    'imageDescription',
  );
  @override
  late final GeneratedColumn<String> imageDescription = GeneratedColumn<String>(
    'image_description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _emotionAnalysisMeta = const VerificationMeta(
    'emotionAnalysis',
  );
  @override
  late final GeneratedColumn<String> emotionAnalysis = GeneratedColumn<String>(
    'emotion_analysis',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _logicAnalysisMeta = const VerificationMeta(
    'logicAnalysis',
  );
  @override
  late final GeneratedColumn<String> logicAnalysis = GeneratedColumn<String>(
    'logic_analysis',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _factCheckMeta = const VerificationMeta(
    'factCheck',
  );
  @override
  late final GeneratedColumn<String> factCheck = GeneratedColumn<String>(
    'fact_check',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _suggestionsMeta = const VerificationMeta(
    'suggestions',
  );
  @override
  late final GeneratedColumn<String> suggestions = GeneratedColumn<String>(
    'suggestions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('clear'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    postId,
    imageDescription,
    emotionAnalysis,
    logicAnalysis,
    factCheck,
    suggestions,
    createdAt,
    scope,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'analysis_results';
  @override
  VerificationContext validateIntegrity(
    Insertable<AnalysisResultRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('post_id')) {
      context.handle(
        _postIdMeta,
        postId.isAcceptableOrUnknown(data['post_id']!, _postIdMeta),
      );
    } else if (isInserting) {
      context.missing(_postIdMeta);
    }
    if (data.containsKey('image_description')) {
      context.handle(
        _imageDescriptionMeta,
        imageDescription.isAcceptableOrUnknown(
          data['image_description']!,
          _imageDescriptionMeta,
        ),
      );
    }
    if (data.containsKey('emotion_analysis')) {
      context.handle(
        _emotionAnalysisMeta,
        emotionAnalysis.isAcceptableOrUnknown(
          data['emotion_analysis']!,
          _emotionAnalysisMeta,
        ),
      );
    }
    if (data.containsKey('logic_analysis')) {
      context.handle(
        _logicAnalysisMeta,
        logicAnalysis.isAcceptableOrUnknown(
          data['logic_analysis']!,
          _logicAnalysisMeta,
        ),
      );
    }
    if (data.containsKey('fact_check')) {
      context.handle(
        _factCheckMeta,
        factCheck.isAcceptableOrUnknown(data['fact_check']!, _factCheckMeta),
      );
    }
    if (data.containsKey('suggestions')) {
      context.handle(
        _suggestionsMeta,
        suggestions.isAcceptableOrUnknown(
          data['suggestions']!,
          _suggestionsMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AnalysisResultRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnalysisResultRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      postId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}post_id'],
      )!,
      imageDescription: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_description'],
      ),
      emotionAnalysis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emotion_analysis'],
      ),
      logicAnalysis: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}logic_analysis'],
      ),
      factCheck: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fact_check'],
      ),
      suggestions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}suggestions'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
    );
  }

  @override
  $AnalysisResultsTable createAlias(String alias) {
    return $AnalysisResultsTable(attachedDatabase, alias);
  }
}

class AnalysisResultRow extends DataClass
    implements Insertable<AnalysisResultRow> {
  final String id;
  final String postId;
  final String? imageDescription;
  final String? emotionAnalysis;
  final String? logicAnalysis;
  final String? factCheck;
  final String? suggestions;
  final int createdAt;
  final String scope;
  const AnalysisResultRow({
    required this.id,
    required this.postId,
    this.imageDescription,
    this.emotionAnalysis,
    this.logicAnalysis,
    this.factCheck,
    this.suggestions,
    required this.createdAt,
    required this.scope,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['post_id'] = Variable<String>(postId);
    if (!nullToAbsent || imageDescription != null) {
      map['image_description'] = Variable<String>(imageDescription);
    }
    if (!nullToAbsent || emotionAnalysis != null) {
      map['emotion_analysis'] = Variable<String>(emotionAnalysis);
    }
    if (!nullToAbsent || logicAnalysis != null) {
      map['logic_analysis'] = Variable<String>(logicAnalysis);
    }
    if (!nullToAbsent || factCheck != null) {
      map['fact_check'] = Variable<String>(factCheck);
    }
    if (!nullToAbsent || suggestions != null) {
      map['suggestions'] = Variable<String>(suggestions);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['scope'] = Variable<String>(scope);
    return map;
  }

  AnalysisResultsCompanion toCompanion(bool nullToAbsent) {
    return AnalysisResultsCompanion(
      id: Value(id),
      postId: Value(postId),
      imageDescription: imageDescription == null && nullToAbsent
          ? const Value.absent()
          : Value(imageDescription),
      emotionAnalysis: emotionAnalysis == null && nullToAbsent
          ? const Value.absent()
          : Value(emotionAnalysis),
      logicAnalysis: logicAnalysis == null && nullToAbsent
          ? const Value.absent()
          : Value(logicAnalysis),
      factCheck: factCheck == null && nullToAbsent
          ? const Value.absent()
          : Value(factCheck),
      suggestions: suggestions == null && nullToAbsent
          ? const Value.absent()
          : Value(suggestions),
      createdAt: Value(createdAt),
      scope: Value(scope),
    );
  }

  factory AnalysisResultRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnalysisResultRow(
      id: serializer.fromJson<String>(json['id']),
      postId: serializer.fromJson<String>(json['postId']),
      imageDescription: serializer.fromJson<String?>(json['imageDescription']),
      emotionAnalysis: serializer.fromJson<String?>(json['emotionAnalysis']),
      logicAnalysis: serializer.fromJson<String?>(json['logicAnalysis']),
      factCheck: serializer.fromJson<String?>(json['factCheck']),
      suggestions: serializer.fromJson<String?>(json['suggestions']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      scope: serializer.fromJson<String>(json['scope']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'postId': serializer.toJson<String>(postId),
      'imageDescription': serializer.toJson<String?>(imageDescription),
      'emotionAnalysis': serializer.toJson<String?>(emotionAnalysis),
      'logicAnalysis': serializer.toJson<String?>(logicAnalysis),
      'factCheck': serializer.toJson<String?>(factCheck),
      'suggestions': serializer.toJson<String?>(suggestions),
      'createdAt': serializer.toJson<int>(createdAt),
      'scope': serializer.toJson<String>(scope),
    };
  }

  AnalysisResultRow copyWith({
    String? id,
    String? postId,
    Value<String?> imageDescription = const Value.absent(),
    Value<String?> emotionAnalysis = const Value.absent(),
    Value<String?> logicAnalysis = const Value.absent(),
    Value<String?> factCheck = const Value.absent(),
    Value<String?> suggestions = const Value.absent(),
    int? createdAt,
    String? scope,
  }) => AnalysisResultRow(
    id: id ?? this.id,
    postId: postId ?? this.postId,
    imageDescription: imageDescription.present
        ? imageDescription.value
        : this.imageDescription,
    emotionAnalysis: emotionAnalysis.present
        ? emotionAnalysis.value
        : this.emotionAnalysis,
    logicAnalysis: logicAnalysis.present
        ? logicAnalysis.value
        : this.logicAnalysis,
    factCheck: factCheck.present ? factCheck.value : this.factCheck,
    suggestions: suggestions.present ? suggestions.value : this.suggestions,
    createdAt: createdAt ?? this.createdAt,
    scope: scope ?? this.scope,
  );
  AnalysisResultRow copyWithCompanion(AnalysisResultsCompanion data) {
    return AnalysisResultRow(
      id: data.id.present ? data.id.value : this.id,
      postId: data.postId.present ? data.postId.value : this.postId,
      imageDescription: data.imageDescription.present
          ? data.imageDescription.value
          : this.imageDescription,
      emotionAnalysis: data.emotionAnalysis.present
          ? data.emotionAnalysis.value
          : this.emotionAnalysis,
      logicAnalysis: data.logicAnalysis.present
          ? data.logicAnalysis.value
          : this.logicAnalysis,
      factCheck: data.factCheck.present ? data.factCheck.value : this.factCheck,
      suggestions: data.suggestions.present
          ? data.suggestions.value
          : this.suggestions,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      scope: data.scope.present ? data.scope.value : this.scope,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AnalysisResultRow(')
          ..write('id: $id, ')
          ..write('postId: $postId, ')
          ..write('imageDescription: $imageDescription, ')
          ..write('emotionAnalysis: $emotionAnalysis, ')
          ..write('logicAnalysis: $logicAnalysis, ')
          ..write('factCheck: $factCheck, ')
          ..write('suggestions: $suggestions, ')
          ..write('createdAt: $createdAt, ')
          ..write('scope: $scope')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    postId,
    imageDescription,
    emotionAnalysis,
    logicAnalysis,
    factCheck,
    suggestions,
    createdAt,
    scope,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnalysisResultRow &&
          other.id == this.id &&
          other.postId == this.postId &&
          other.imageDescription == this.imageDescription &&
          other.emotionAnalysis == this.emotionAnalysis &&
          other.logicAnalysis == this.logicAnalysis &&
          other.factCheck == this.factCheck &&
          other.suggestions == this.suggestions &&
          other.createdAt == this.createdAt &&
          other.scope == this.scope);
}

class AnalysisResultsCompanion extends UpdateCompanion<AnalysisResultRow> {
  final Value<String> id;
  final Value<String> postId;
  final Value<String?> imageDescription;
  final Value<String?> emotionAnalysis;
  final Value<String?> logicAnalysis;
  final Value<String?> factCheck;
  final Value<String?> suggestions;
  final Value<int> createdAt;
  final Value<String> scope;
  final Value<int> rowid;
  const AnalysisResultsCompanion({
    this.id = const Value.absent(),
    this.postId = const Value.absent(),
    this.imageDescription = const Value.absent(),
    this.emotionAnalysis = const Value.absent(),
    this.logicAnalysis = const Value.absent(),
    this.factCheck = const Value.absent(),
    this.suggestions = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnalysisResultsCompanion.insert({
    required String id,
    required String postId,
    this.imageDescription = const Value.absent(),
    this.emotionAnalysis = const Value.absent(),
    this.logicAnalysis = const Value.absent(),
    this.factCheck = const Value.absent(),
    this.suggestions = const Value.absent(),
    required int createdAt,
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       postId = Value(postId),
       createdAt = Value(createdAt);
  static Insertable<AnalysisResultRow> custom({
    Expression<String>? id,
    Expression<String>? postId,
    Expression<String>? imageDescription,
    Expression<String>? emotionAnalysis,
    Expression<String>? logicAnalysis,
    Expression<String>? factCheck,
    Expression<String>? suggestions,
    Expression<int>? createdAt,
    Expression<String>? scope,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (postId != null) 'post_id': postId,
      if (imageDescription != null) 'image_description': imageDescription,
      if (emotionAnalysis != null) 'emotion_analysis': emotionAnalysis,
      if (logicAnalysis != null) 'logic_analysis': logicAnalysis,
      if (factCheck != null) 'fact_check': factCheck,
      if (suggestions != null) 'suggestions': suggestions,
      if (createdAt != null) 'created_at': createdAt,
      if (scope != null) 'scope': scope,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AnalysisResultsCompanion copyWith({
    Value<String>? id,
    Value<String>? postId,
    Value<String?>? imageDescription,
    Value<String?>? emotionAnalysis,
    Value<String?>? logicAnalysis,
    Value<String?>? factCheck,
    Value<String?>? suggestions,
    Value<int>? createdAt,
    Value<String>? scope,
    Value<int>? rowid,
  }) {
    return AnalysisResultsCompanion(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      imageDescription: imageDescription ?? this.imageDescription,
      emotionAnalysis: emotionAnalysis ?? this.emotionAnalysis,
      logicAnalysis: logicAnalysis ?? this.logicAnalysis,
      factCheck: factCheck ?? this.factCheck,
      suggestions: suggestions ?? this.suggestions,
      createdAt: createdAt ?? this.createdAt,
      scope: scope ?? this.scope,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (postId.present) {
      map['post_id'] = Variable<String>(postId.value);
    }
    if (imageDescription.present) {
      map['image_description'] = Variable<String>(imageDescription.value);
    }
    if (emotionAnalysis.present) {
      map['emotion_analysis'] = Variable<String>(emotionAnalysis.value);
    }
    if (logicAnalysis.present) {
      map['logic_analysis'] = Variable<String>(logicAnalysis.value);
    }
    if (factCheck.present) {
      map['fact_check'] = Variable<String>(factCheck.value);
    }
    if (suggestions.present) {
      map['suggestions'] = Variable<String>(suggestions.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnalysisResultsCompanion(')
          ..write('id: $id, ')
          ..write('postId: $postId, ')
          ..write('imageDescription: $imageDescription, ')
          ..write('emotionAnalysis: $emotionAnalysis, ')
          ..write('logicAnalysis: $logicAnalysis, ')
          ..write('factCheck: $factCheck, ')
          ..write('suggestions: $suggestions, ')
          ..write('createdAt: $createdAt, ')
          ..write('scope: $scope, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ModeSwitchLogsTable extends ModeSwitchLogs
    with TableInfo<$ModeSwitchLogsTable, ModeSwitchLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ModeSwitchLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromModeMeta = const VerificationMeta(
    'fromMode',
  );
  @override
  late final GeneratedColumn<String> fromMode = GeneratedColumn<String>(
    'from_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toModeMeta = const VerificationMeta('toMode');
  @override
  late final GeneratedColumn<String> toMode = GeneratedColumn<String>(
    'to_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _switchedAtMeta = const VerificationMeta(
    'switchedAt',
  );
  @override
  late final GeneratedColumn<int> switchedAt = GeneratedColumn<int>(
    'switched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _archiveActionMeta = const VerificationMeta(
    'archiveAction',
  );
  @override
  late final GeneratedColumn<String> archiveAction = GeneratedColumn<String>(
    'archive_action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('kept'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fromMode,
    toMode,
    switchedAt,
    archiveAction,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mode_switch_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ModeSwitchLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('from_mode')) {
      context.handle(
        _fromModeMeta,
        fromMode.isAcceptableOrUnknown(data['from_mode']!, _fromModeMeta),
      );
    } else if (isInserting) {
      context.missing(_fromModeMeta);
    }
    if (data.containsKey('to_mode')) {
      context.handle(
        _toModeMeta,
        toMode.isAcceptableOrUnknown(data['to_mode']!, _toModeMeta),
      );
    } else if (isInserting) {
      context.missing(_toModeMeta);
    }
    if (data.containsKey('switched_at')) {
      context.handle(
        _switchedAtMeta,
        switchedAt.isAcceptableOrUnknown(data['switched_at']!, _switchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_switchedAtMeta);
    }
    if (data.containsKey('archive_action')) {
      context.handle(
        _archiveActionMeta,
        archiveAction.isAcceptableOrUnknown(
          data['archive_action']!,
          _archiveActionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ModeSwitchLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ModeSwitchLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      fromMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_mode'],
      )!,
      toMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_mode'],
      )!,
      switchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}switched_at'],
      )!,
      archiveAction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}archive_action'],
      )!,
    );
  }

  @override
  $ModeSwitchLogsTable createAlias(String alias) {
    return $ModeSwitchLogsTable(attachedDatabase, alias);
  }
}

class ModeSwitchLogRow extends DataClass
    implements Insertable<ModeSwitchLogRow> {
  final String id;
  final String fromMode;
  final String toMode;
  final int switchedAt;

  /// archived / purged / kept
  final String archiveAction;
  const ModeSwitchLogRow({
    required this.id,
    required this.fromMode,
    required this.toMode,
    required this.switchedAt,
    required this.archiveAction,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['from_mode'] = Variable<String>(fromMode);
    map['to_mode'] = Variable<String>(toMode);
    map['switched_at'] = Variable<int>(switchedAt);
    map['archive_action'] = Variable<String>(archiveAction);
    return map;
  }

  ModeSwitchLogsCompanion toCompanion(bool nullToAbsent) {
    return ModeSwitchLogsCompanion(
      id: Value(id),
      fromMode: Value(fromMode),
      toMode: Value(toMode),
      switchedAt: Value(switchedAt),
      archiveAction: Value(archiveAction),
    );
  }

  factory ModeSwitchLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ModeSwitchLogRow(
      id: serializer.fromJson<String>(json['id']),
      fromMode: serializer.fromJson<String>(json['fromMode']),
      toMode: serializer.fromJson<String>(json['toMode']),
      switchedAt: serializer.fromJson<int>(json['switchedAt']),
      archiveAction: serializer.fromJson<String>(json['archiveAction']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fromMode': serializer.toJson<String>(fromMode),
      'toMode': serializer.toJson<String>(toMode),
      'switchedAt': serializer.toJson<int>(switchedAt),
      'archiveAction': serializer.toJson<String>(archiveAction),
    };
  }

  ModeSwitchLogRow copyWith({
    String? id,
    String? fromMode,
    String? toMode,
    int? switchedAt,
    String? archiveAction,
  }) => ModeSwitchLogRow(
    id: id ?? this.id,
    fromMode: fromMode ?? this.fromMode,
    toMode: toMode ?? this.toMode,
    switchedAt: switchedAt ?? this.switchedAt,
    archiveAction: archiveAction ?? this.archiveAction,
  );
  ModeSwitchLogRow copyWithCompanion(ModeSwitchLogsCompanion data) {
    return ModeSwitchLogRow(
      id: data.id.present ? data.id.value : this.id,
      fromMode: data.fromMode.present ? data.fromMode.value : this.fromMode,
      toMode: data.toMode.present ? data.toMode.value : this.toMode,
      switchedAt: data.switchedAt.present
          ? data.switchedAt.value
          : this.switchedAt,
      archiveAction: data.archiveAction.present
          ? data.archiveAction.value
          : this.archiveAction,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ModeSwitchLogRow(')
          ..write('id: $id, ')
          ..write('fromMode: $fromMode, ')
          ..write('toMode: $toMode, ')
          ..write('switchedAt: $switchedAt, ')
          ..write('archiveAction: $archiveAction')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, fromMode, toMode, switchedAt, archiveAction);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ModeSwitchLogRow &&
          other.id == this.id &&
          other.fromMode == this.fromMode &&
          other.toMode == this.toMode &&
          other.switchedAt == this.switchedAt &&
          other.archiveAction == this.archiveAction);
}

class ModeSwitchLogsCompanion extends UpdateCompanion<ModeSwitchLogRow> {
  final Value<String> id;
  final Value<String> fromMode;
  final Value<String> toMode;
  final Value<int> switchedAt;
  final Value<String> archiveAction;
  final Value<int> rowid;
  const ModeSwitchLogsCompanion({
    this.id = const Value.absent(),
    this.fromMode = const Value.absent(),
    this.toMode = const Value.absent(),
    this.switchedAt = const Value.absent(),
    this.archiveAction = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ModeSwitchLogsCompanion.insert({
    required String id,
    required String fromMode,
    required String toMode,
    required int switchedAt,
    this.archiveAction = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       fromMode = Value(fromMode),
       toMode = Value(toMode),
       switchedAt = Value(switchedAt);
  static Insertable<ModeSwitchLogRow> custom({
    Expression<String>? id,
    Expression<String>? fromMode,
    Expression<String>? toMode,
    Expression<int>? switchedAt,
    Expression<String>? archiveAction,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fromMode != null) 'from_mode': fromMode,
      if (toMode != null) 'to_mode': toMode,
      if (switchedAt != null) 'switched_at': switchedAt,
      if (archiveAction != null) 'archive_action': archiveAction,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ModeSwitchLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? fromMode,
    Value<String>? toMode,
    Value<int>? switchedAt,
    Value<String>? archiveAction,
    Value<int>? rowid,
  }) {
    return ModeSwitchLogsCompanion(
      id: id ?? this.id,
      fromMode: fromMode ?? this.fromMode,
      toMode: toMode ?? this.toMode,
      switchedAt: switchedAt ?? this.switchedAt,
      archiveAction: archiveAction ?? this.archiveAction,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fromMode.present) {
      map['from_mode'] = Variable<String>(fromMode.value);
    }
    if (toMode.present) {
      map['to_mode'] = Variable<String>(toMode.value);
    }
    if (switchedAt.present) {
      map['switched_at'] = Variable<int>(switchedAt.value);
    }
    if (archiveAction.present) {
      map['archive_action'] = Variable<String>(archiveAction.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ModeSwitchLogsCompanion(')
          ..write('id: $id, ')
          ..write('fromMode: $fromMode, ')
          ..write('toMode: $toMode, ')
          ..write('switchedAt: $switchedAt, ')
          ..write('archiveAction: $archiveAction, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NotificationLogsTable extends NotificationLogs
    with TableInfo<$NotificationLogsTable, NotificationLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotificationLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _postIdMeta = const VerificationMeta('postId');
  @override
  late final GeneratedColumn<String> postId = GeneratedColumn<String>(
    'post_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scheduledAtMeta = const VerificationMeta(
    'scheduledAt',
  );
  @override
  late final GeneratedColumn<int> scheduledAt = GeneratedColumn<int>(
    'scheduled_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deliveredAtMeta = const VerificationMeta(
    'deliveredAt',
  );
  @override
  late final GeneratedColumn<int> deliveredAt = GeneratedColumn<int>(
    'delivered_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
    'is_read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_read" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('echo'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    title,
    body,
    postId,
    scheduledAt,
    deliveredAt,
    isRead,
    scope,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notification_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<NotificationLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('post_id')) {
      context.handle(
        _postIdMeta,
        postId.isAcceptableOrUnknown(data['post_id']!, _postIdMeta),
      );
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
        _scheduledAtMeta,
        scheduledAt.isAcceptableOrUnknown(
          data['scheduled_at']!,
          _scheduledAtMeta,
        ),
      );
    }
    if (data.containsKey('delivered_at')) {
      context.handle(
        _deliveredAtMeta,
        deliveredAt.isAcceptableOrUnknown(
          data['delivered_at']!,
          _deliveredAtMeta,
        ),
      );
    }
    if (data.containsKey('is_read')) {
      context.handle(
        _isReadMeta,
        isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NotificationLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NotificationLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      postId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}post_id'],
      ),
      scheduledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scheduled_at'],
      ),
      deliveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delivered_at'],
      ),
      isRead: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_read'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
    );
  }

  @override
  $NotificationLogsTable createAlias(String alias) {
    return $NotificationLogsTable(attachedDatabase, alias);
  }
}

class NotificationLogRow extends DataClass
    implements Insertable<NotificationLogRow> {
  final String id;
  final String type;
  final String title;
  final String body;

  /// 这条通知指向的帖子（点击通知跳转用）。系统通知可以为空。
  final String? postId;
  final int? scheduledAt;
  final int? deliveredAt;
  final bool isRead;
  final String scope;
  const NotificationLogRow({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.postId,
    this.scheduledAt,
    this.deliveredAt,
    required this.isRead,
    required this.scope,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || postId != null) {
      map['post_id'] = Variable<String>(postId);
    }
    if (!nullToAbsent || scheduledAt != null) {
      map['scheduled_at'] = Variable<int>(scheduledAt);
    }
    if (!nullToAbsent || deliveredAt != null) {
      map['delivered_at'] = Variable<int>(deliveredAt);
    }
    map['is_read'] = Variable<bool>(isRead);
    map['scope'] = Variable<String>(scope);
    return map;
  }

  NotificationLogsCompanion toCompanion(bool nullToAbsent) {
    return NotificationLogsCompanion(
      id: Value(id),
      type: Value(type),
      title: Value(title),
      body: Value(body),
      postId: postId == null && nullToAbsent
          ? const Value.absent()
          : Value(postId),
      scheduledAt: scheduledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledAt),
      deliveredAt: deliveredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveredAt),
      isRead: Value(isRead),
      scope: Value(scope),
    );
  }

  factory NotificationLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NotificationLogRow(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      postId: serializer.fromJson<String?>(json['postId']),
      scheduledAt: serializer.fromJson<int?>(json['scheduledAt']),
      deliveredAt: serializer.fromJson<int?>(json['deliveredAt']),
      isRead: serializer.fromJson<bool>(json['isRead']),
      scope: serializer.fromJson<String>(json['scope']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'postId': serializer.toJson<String?>(postId),
      'scheduledAt': serializer.toJson<int?>(scheduledAt),
      'deliveredAt': serializer.toJson<int?>(deliveredAt),
      'isRead': serializer.toJson<bool>(isRead),
      'scope': serializer.toJson<String>(scope),
    };
  }

  NotificationLogRow copyWith({
    String? id,
    String? type,
    String? title,
    String? body,
    Value<String?> postId = const Value.absent(),
    Value<int?> scheduledAt = const Value.absent(),
    Value<int?> deliveredAt = const Value.absent(),
    bool? isRead,
    String? scope,
  }) => NotificationLogRow(
    id: id ?? this.id,
    type: type ?? this.type,
    title: title ?? this.title,
    body: body ?? this.body,
    postId: postId.present ? postId.value : this.postId,
    scheduledAt: scheduledAt.present ? scheduledAt.value : this.scheduledAt,
    deliveredAt: deliveredAt.present ? deliveredAt.value : this.deliveredAt,
    isRead: isRead ?? this.isRead,
    scope: scope ?? this.scope,
  );
  NotificationLogRow copyWithCompanion(NotificationLogsCompanion data) {
    return NotificationLogRow(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      postId: data.postId.present ? data.postId.value : this.postId,
      scheduledAt: data.scheduledAt.present
          ? data.scheduledAt.value
          : this.scheduledAt,
      deliveredAt: data.deliveredAt.present
          ? data.deliveredAt.value
          : this.deliveredAt,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
      scope: data.scope.present ? data.scope.value : this.scope,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NotificationLogRow(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('postId: $postId, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('isRead: $isRead, ')
          ..write('scope: $scope')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    title,
    body,
    postId,
    scheduledAt,
    deliveredAt,
    isRead,
    scope,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotificationLogRow &&
          other.id == this.id &&
          other.type == this.type &&
          other.title == this.title &&
          other.body == this.body &&
          other.postId == this.postId &&
          other.scheduledAt == this.scheduledAt &&
          other.deliveredAt == this.deliveredAt &&
          other.isRead == this.isRead &&
          other.scope == this.scope);
}

class NotificationLogsCompanion extends UpdateCompanion<NotificationLogRow> {
  final Value<String> id;
  final Value<String> type;
  final Value<String> title;
  final Value<String> body;
  final Value<String?> postId;
  final Value<int?> scheduledAt;
  final Value<int?> deliveredAt;
  final Value<bool> isRead;
  final Value<String> scope;
  final Value<int> rowid;
  const NotificationLogsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.postId = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.isRead = const Value.absent(),
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotificationLogsCompanion.insert({
    required String id,
    required String type,
    required String title,
    this.body = const Value.absent(),
    this.postId = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.isRead = const Value.absent(),
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type),
       title = Value(title);
  static Insertable<NotificationLogRow> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? title,
    Expression<String>? body,
    Expression<String>? postId,
    Expression<int>? scheduledAt,
    Expression<int>? deliveredAt,
    Expression<bool>? isRead,
    Expression<String>? scope,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (postId != null) 'post_id': postId,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (deliveredAt != null) 'delivered_at': deliveredAt,
      if (isRead != null) 'is_read': isRead,
      if (scope != null) 'scope': scope,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotificationLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? type,
    Value<String>? title,
    Value<String>? body,
    Value<String?>? postId,
    Value<int?>? scheduledAt,
    Value<int?>? deliveredAt,
    Value<bool>? isRead,
    Value<String>? scope,
    Value<int>? rowid,
  }) {
    return NotificationLogsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      postId: postId ?? this.postId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      isRead: isRead ?? this.isRead,
      scope: scope ?? this.scope,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (postId.present) {
      map['post_id'] = Variable<String>(postId.value);
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<int>(scheduledAt.value);
    }
    if (deliveredAt.present) {
      map['delivered_at'] = Variable<int>(deliveredAt.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotificationLogsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('postId: $postId, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('isRead: $isRead, ')
          ..write('scope: $scope, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FeedbackViewLogsTable extends FeedbackViewLogs
    with TableInfo<$FeedbackViewLogsTable, FeedbackViewLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FeedbackViewLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _postIdMeta = const VerificationMeta('postId');
  @override
  late final GeneratedColumn<String> postId = GeneratedColumn<String>(
    'post_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _viewedAtMeta = const VerificationMeta(
    'viewedAt',
  );
  @override
  late final GeneratedColumn<int> viewedAt = GeneratedColumn<int>(
    'viewed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('echo'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    postId,
    viewedAt,
    durationMs,
    scope,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'feedback_view_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<FeedbackViewLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('post_id')) {
      context.handle(
        _postIdMeta,
        postId.isAcceptableOrUnknown(data['post_id']!, _postIdMeta),
      );
    }
    if (data.containsKey('viewed_at')) {
      context.handle(
        _viewedAtMeta,
        viewedAt.isAcceptableOrUnknown(data['viewed_at']!, _viewedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_viewedAtMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FeedbackViewLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FeedbackViewLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      postId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}post_id'],
      ),
      viewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}viewed_at'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
    );
  }

  @override
  $FeedbackViewLogsTable createAlias(String alias) {
    return $FeedbackViewLogsTable(attachedDatabase, alias);
  }
}

class FeedbackViewLogRow extends DataClass
    implements Insertable<FeedbackViewLogRow> {
  final String id;
  final String? postId;
  final int viewedAt;
  final int durationMs;
  final String scope;
  const FeedbackViewLogRow({
    required this.id,
    this.postId,
    required this.viewedAt,
    required this.durationMs,
    required this.scope,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || postId != null) {
      map['post_id'] = Variable<String>(postId);
    }
    map['viewed_at'] = Variable<int>(viewedAt);
    map['duration_ms'] = Variable<int>(durationMs);
    map['scope'] = Variable<String>(scope);
    return map;
  }

  FeedbackViewLogsCompanion toCompanion(bool nullToAbsent) {
    return FeedbackViewLogsCompanion(
      id: Value(id),
      postId: postId == null && nullToAbsent
          ? const Value.absent()
          : Value(postId),
      viewedAt: Value(viewedAt),
      durationMs: Value(durationMs),
      scope: Value(scope),
    );
  }

  factory FeedbackViewLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FeedbackViewLogRow(
      id: serializer.fromJson<String>(json['id']),
      postId: serializer.fromJson<String?>(json['postId']),
      viewedAt: serializer.fromJson<int>(json['viewedAt']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      scope: serializer.fromJson<String>(json['scope']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'postId': serializer.toJson<String?>(postId),
      'viewedAt': serializer.toJson<int>(viewedAt),
      'durationMs': serializer.toJson<int>(durationMs),
      'scope': serializer.toJson<String>(scope),
    };
  }

  FeedbackViewLogRow copyWith({
    String? id,
    Value<String?> postId = const Value.absent(),
    int? viewedAt,
    int? durationMs,
    String? scope,
  }) => FeedbackViewLogRow(
    id: id ?? this.id,
    postId: postId.present ? postId.value : this.postId,
    viewedAt: viewedAt ?? this.viewedAt,
    durationMs: durationMs ?? this.durationMs,
    scope: scope ?? this.scope,
  );
  FeedbackViewLogRow copyWithCompanion(FeedbackViewLogsCompanion data) {
    return FeedbackViewLogRow(
      id: data.id.present ? data.id.value : this.id,
      postId: data.postId.present ? data.postId.value : this.postId,
      viewedAt: data.viewedAt.present ? data.viewedAt.value : this.viewedAt,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      scope: data.scope.present ? data.scope.value : this.scope,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FeedbackViewLogRow(')
          ..write('id: $id, ')
          ..write('postId: $postId, ')
          ..write('viewedAt: $viewedAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('scope: $scope')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, postId, viewedAt, durationMs, scope);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FeedbackViewLogRow &&
          other.id == this.id &&
          other.postId == this.postId &&
          other.viewedAt == this.viewedAt &&
          other.durationMs == this.durationMs &&
          other.scope == this.scope);
}

class FeedbackViewLogsCompanion extends UpdateCompanion<FeedbackViewLogRow> {
  final Value<String> id;
  final Value<String?> postId;
  final Value<int> viewedAt;
  final Value<int> durationMs;
  final Value<String> scope;
  final Value<int> rowid;
  const FeedbackViewLogsCompanion({
    this.id = const Value.absent(),
    this.postId = const Value.absent(),
    this.viewedAt = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FeedbackViewLogsCompanion.insert({
    required String id,
    this.postId = const Value.absent(),
    required int viewedAt,
    this.durationMs = const Value.absent(),
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       viewedAt = Value(viewedAt);
  static Insertable<FeedbackViewLogRow> custom({
    Expression<String>? id,
    Expression<String>? postId,
    Expression<int>? viewedAt,
    Expression<int>? durationMs,
    Expression<String>? scope,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (postId != null) 'post_id': postId,
      if (viewedAt != null) 'viewed_at': viewedAt,
      if (durationMs != null) 'duration_ms': durationMs,
      if (scope != null) 'scope': scope,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FeedbackViewLogsCompanion copyWith({
    Value<String>? id,
    Value<String?>? postId,
    Value<int>? viewedAt,
    Value<int>? durationMs,
    Value<String>? scope,
    Value<int>? rowid,
  }) {
    return FeedbackViewLogsCompanion(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      viewedAt: viewedAt ?? this.viewedAt,
      durationMs: durationMs ?? this.durationMs,
      scope: scope ?? this.scope,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (postId.present) {
      map['post_id'] = Variable<String>(postId.value);
    }
    if (viewedAt.present) {
      map['viewed_at'] = Variable<int>(viewedAt.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FeedbackViewLogsCompanion(')
          ..write('id: $id, ')
          ..write('postId: $postId, ')
          ..write('viewedAt: $viewedAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('scope: $scope, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StickersTable extends Stickers
    with TableInfo<$StickersTable, StickerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StickersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('asset'),
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isUserMeta = const VerificationMeta('isUser');
  @override
  late final GeneratedColumn<bool> isUser = GeneratedColumn<bool>(
    'is_user',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_user" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isBuiltinMeta = const VerificationMeta(
    'isBuiltin',
  );
  @override
  late final GeneratedColumn<bool> isBuiltin = GeneratedColumn<bool>(
    'is_builtin',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_builtin" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('shared'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    category,
    source,
    path,
    isUser,
    isBuiltin,
    createdAt,
    deletedAt,
    scope,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stickers';
  @override
  VerificationContext validateIntegrity(
    Insertable<StickerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('is_user')) {
      context.handle(
        _isUserMeta,
        isUser.isAcceptableOrUnknown(data['is_user']!, _isUserMeta),
      );
    }
    if (data.containsKey('is_builtin')) {
      context.handle(
        _isBuiltinMeta,
        isBuiltin.isAcceptableOrUnknown(data['is_builtin']!, _isBuiltinMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StickerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StickerRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      isUser: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_user'],
      )!,
      isBuiltin: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_builtin'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
    );
  }

  @override
  $StickersTable createAlias(String alias) {
    return $StickersTable(attachedDatabase, alias);
  }
}

class StickerRow extends DataClass implements Insertable<StickerRow> {
  final String id;

  /// 展示名，也是图片缺失时的文字兜底内容。
  final String name;
  final String category;

  /// asset / file
  final String source;
  final String path;
  final bool isUser;
  final bool isBuiltin;
  final int? createdAt;
  final int? deletedAt;
  final String scope;
  const StickerRow({
    required this.id,
    required this.name,
    required this.category,
    required this.source,
    required this.path,
    required this.isUser,
    required this.isBuiltin,
    this.createdAt,
    this.deletedAt,
    required this.scope,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['category'] = Variable<String>(category);
    map['source'] = Variable<String>(source);
    map['path'] = Variable<String>(path);
    map['is_user'] = Variable<bool>(isUser);
    map['is_builtin'] = Variable<bool>(isBuiltin);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<int>(createdAt);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['scope'] = Variable<String>(scope);
    return map;
  }

  StickersCompanion toCompanion(bool nullToAbsent) {
    return StickersCompanion(
      id: Value(id),
      name: Value(name),
      category: Value(category),
      source: Value(source),
      path: Value(path),
      isUser: Value(isUser),
      isBuiltin: Value(isBuiltin),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      scope: Value(scope),
    );
  }

  factory StickerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StickerRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      category: serializer.fromJson<String>(json['category']),
      source: serializer.fromJson<String>(json['source']),
      path: serializer.fromJson<String>(json['path']),
      isUser: serializer.fromJson<bool>(json['isUser']),
      isBuiltin: serializer.fromJson<bool>(json['isBuiltin']),
      createdAt: serializer.fromJson<int?>(json['createdAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      scope: serializer.fromJson<String>(json['scope']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'category': serializer.toJson<String>(category),
      'source': serializer.toJson<String>(source),
      'path': serializer.toJson<String>(path),
      'isUser': serializer.toJson<bool>(isUser),
      'isBuiltin': serializer.toJson<bool>(isBuiltin),
      'createdAt': serializer.toJson<int?>(createdAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'scope': serializer.toJson<String>(scope),
    };
  }

  StickerRow copyWith({
    String? id,
    String? name,
    String? category,
    String? source,
    String? path,
    bool? isUser,
    bool? isBuiltin,
    Value<int?> createdAt = const Value.absent(),
    Value<int?> deletedAt = const Value.absent(),
    String? scope,
  }) => StickerRow(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    source: source ?? this.source,
    path: path ?? this.path,
    isUser: isUser ?? this.isUser,
    isBuiltin: isBuiltin ?? this.isBuiltin,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    scope: scope ?? this.scope,
  );
  StickerRow copyWithCompanion(StickersCompanion data) {
    return StickerRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      category: data.category.present ? data.category.value : this.category,
      source: data.source.present ? data.source.value : this.source,
      path: data.path.present ? data.path.value : this.path,
      isUser: data.isUser.present ? data.isUser.value : this.isUser,
      isBuiltin: data.isBuiltin.present ? data.isBuiltin.value : this.isBuiltin,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      scope: data.scope.present ? data.scope.value : this.scope,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StickerRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('category: $category, ')
          ..write('source: $source, ')
          ..write('path: $path, ')
          ..write('isUser: $isUser, ')
          ..write('isBuiltin: $isBuiltin, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('scope: $scope')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    category,
    source,
    path,
    isUser,
    isBuiltin,
    createdAt,
    deletedAt,
    scope,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StickerRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.category == this.category &&
          other.source == this.source &&
          other.path == this.path &&
          other.isUser == this.isUser &&
          other.isBuiltin == this.isBuiltin &&
          other.createdAt == this.createdAt &&
          other.deletedAt == this.deletedAt &&
          other.scope == this.scope);
}

class StickersCompanion extends UpdateCompanion<StickerRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> category;
  final Value<String> source;
  final Value<String> path;
  final Value<bool> isUser;
  final Value<bool> isBuiltin;
  final Value<int?> createdAt;
  final Value<int?> deletedAt;
  final Value<String> scope;
  final Value<int> rowid;
  const StickersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.category = const Value.absent(),
    this.source = const Value.absent(),
    this.path = const Value.absent(),
    this.isUser = const Value.absent(),
    this.isBuiltin = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StickersCompanion.insert({
    required String id,
    required String name,
    required String category,
    this.source = const Value.absent(),
    required String path,
    this.isUser = const Value.absent(),
    this.isBuiltin = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       category = Value(category),
       path = Value(path);
  static Insertable<StickerRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? category,
    Expression<String>? source,
    Expression<String>? path,
    Expression<bool>? isUser,
    Expression<bool>? isBuiltin,
    Expression<int>? createdAt,
    Expression<int>? deletedAt,
    Expression<String>? scope,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (category != null) 'category': category,
      if (source != null) 'source': source,
      if (path != null) 'path': path,
      if (isUser != null) 'is_user': isUser,
      if (isBuiltin != null) 'is_builtin': isBuiltin,
      if (createdAt != null) 'created_at': createdAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (scope != null) 'scope': scope,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StickersCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? category,
    Value<String>? source,
    Value<String>? path,
    Value<bool>? isUser,
    Value<bool>? isBuiltin,
    Value<int?>? createdAt,
    Value<int?>? deletedAt,
    Value<String>? scope,
    Value<int>? rowid,
  }) {
    return StickersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      source: source ?? this.source,
      path: path ?? this.path,
      isUser: isUser ?? this.isUser,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
      scope: scope ?? this.scope,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (isUser.present) {
      map['is_user'] = Variable<bool>(isUser.value);
    }
    if (isBuiltin.present) {
      map['is_builtin'] = Variable<bool>(isBuiltin.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StickersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('category: $category, ')
          ..write('source: $source, ')
          ..write('path: $path, ')
          ..write('isUser: $isUser, ')
          ..write('isBuiltin: $isBuiltin, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('scope: $scope, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlanScriptsTable extends PlanScripts
    with TableInfo<$PlanScriptsTable, PlanScriptRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlanScriptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isBuiltInMeta = const VerificationMeta(
    'isBuiltIn',
  );
  @override
  late final GeneratedColumn<bool> isBuiltIn = GeneratedColumn<bool>(
    'is_built_in',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_built_in" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _postContentMeta = const VerificationMeta(
    'postContent',
  );
  @override
  late final GeneratedColumn<String> postContent = GeneratedColumn<String>(
    'post_content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _postImagesMeta = const VerificationMeta(
    'postImages',
  );
  @override
  late final GeneratedColumn<String> postImages = GeneratedColumn<String>(
    'post_images',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _topicNameMeta = const VerificationMeta(
    'topicName',
  );
  @override
  late final GeneratedColumn<String> topicName = GeneratedColumn<String>(
    'topic_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stepsJsonMeta = const VerificationMeta(
    'stepsJson',
  );
  @override
  late final GeneratedColumn<String> stepsJson = GeneratedColumn<String>(
    'steps_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    isBuiltIn,
    postContent,
    postImages,
    topicName,
    stepsJson,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plan_scripts';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlanScriptRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_built_in')) {
      context.handle(
        _isBuiltInMeta,
        isBuiltIn.isAcceptableOrUnknown(data['is_built_in']!, _isBuiltInMeta),
      );
    }
    if (data.containsKey('post_content')) {
      context.handle(
        _postContentMeta,
        postContent.isAcceptableOrUnknown(
          data['post_content']!,
          _postContentMeta,
        ),
      );
    }
    if (data.containsKey('post_images')) {
      context.handle(
        _postImagesMeta,
        postImages.isAcceptableOrUnknown(data['post_images']!, _postImagesMeta),
      );
    }
    if (data.containsKey('topic_name')) {
      context.handle(
        _topicNameMeta,
        topicName.isAcceptableOrUnknown(data['topic_name']!, _topicNameMeta),
      );
    }
    if (data.containsKey('steps_json')) {
      context.handle(
        _stepsJsonMeta,
        stepsJson.isAcceptableOrUnknown(data['steps_json']!, _stepsJsonMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlanScriptRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlanScriptRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isBuiltIn: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_built_in'],
      )!,
      postContent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}post_content'],
      )!,
      postImages: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}post_images'],
      )!,
      topicName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic_name'],
      ),
      stepsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}steps_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PlanScriptsTable createAlias(String alias) {
    return $PlanScriptsTable(attachedDatabase, alias);
  }
}

class PlanScriptRow extends DataClass implements Insertable<PlanScriptRow> {
  final String id;
  final String name;
  final bool isBuiltIn;

  /// 开局内容：勾选脚本时填进发布页，用户仍可修改。
  final String postContent;
  final String postImages;
  final String? topicName;

  /// 事件表（JSON 数组），结构见 `domain/models/plan_script.dart`。
  final String stepsJson;
  final int createdAt;
  final int updatedAt;
  const PlanScriptRow({
    required this.id,
    required this.name,
    required this.isBuiltIn,
    required this.postContent,
    required this.postImages,
    this.topicName,
    required this.stepsJson,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['is_built_in'] = Variable<bool>(isBuiltIn);
    map['post_content'] = Variable<String>(postContent);
    map['post_images'] = Variable<String>(postImages);
    if (!nullToAbsent || topicName != null) {
      map['topic_name'] = Variable<String>(topicName);
    }
    map['steps_json'] = Variable<String>(stepsJson);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  PlanScriptsCompanion toCompanion(bool nullToAbsent) {
    return PlanScriptsCompanion(
      id: Value(id),
      name: Value(name),
      isBuiltIn: Value(isBuiltIn),
      postContent: Value(postContent),
      postImages: Value(postImages),
      topicName: topicName == null && nullToAbsent
          ? const Value.absent()
          : Value(topicName),
      stepsJson: Value(stepsJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlanScriptRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlanScriptRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      isBuiltIn: serializer.fromJson<bool>(json['isBuiltIn']),
      postContent: serializer.fromJson<String>(json['postContent']),
      postImages: serializer.fromJson<String>(json['postImages']),
      topicName: serializer.fromJson<String?>(json['topicName']),
      stepsJson: serializer.fromJson<String>(json['stepsJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'isBuiltIn': serializer.toJson<bool>(isBuiltIn),
      'postContent': serializer.toJson<String>(postContent),
      'postImages': serializer.toJson<String>(postImages),
      'topicName': serializer.toJson<String?>(topicName),
      'stepsJson': serializer.toJson<String>(stepsJson),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  PlanScriptRow copyWith({
    String? id,
    String? name,
    bool? isBuiltIn,
    String? postContent,
    String? postImages,
    Value<String?> topicName = const Value.absent(),
    String? stepsJson,
    int? createdAt,
    int? updatedAt,
  }) => PlanScriptRow(
    id: id ?? this.id,
    name: name ?? this.name,
    isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    postContent: postContent ?? this.postContent,
    postImages: postImages ?? this.postImages,
    topicName: topicName.present ? topicName.value : this.topicName,
    stepsJson: stepsJson ?? this.stepsJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PlanScriptRow copyWithCompanion(PlanScriptsCompanion data) {
    return PlanScriptRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      isBuiltIn: data.isBuiltIn.present ? data.isBuiltIn.value : this.isBuiltIn,
      postContent: data.postContent.present
          ? data.postContent.value
          : this.postContent,
      postImages: data.postImages.present
          ? data.postImages.value
          : this.postImages,
      topicName: data.topicName.present ? data.topicName.value : this.topicName,
      stepsJson: data.stepsJson.present ? data.stepsJson.value : this.stepsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlanScriptRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isBuiltIn: $isBuiltIn, ')
          ..write('postContent: $postContent, ')
          ..write('postImages: $postImages, ')
          ..write('topicName: $topicName, ')
          ..write('stepsJson: $stepsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    isBuiltIn,
    postContent,
    postImages,
    topicName,
    stepsJson,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlanScriptRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.isBuiltIn == this.isBuiltIn &&
          other.postContent == this.postContent &&
          other.postImages == this.postImages &&
          other.topicName == this.topicName &&
          other.stepsJson == this.stepsJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PlanScriptsCompanion extends UpdateCompanion<PlanScriptRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<bool> isBuiltIn;
  final Value<String> postContent;
  final Value<String> postImages;
  final Value<String?> topicName;
  final Value<String> stepsJson;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const PlanScriptsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.isBuiltIn = const Value.absent(),
    this.postContent = const Value.absent(),
    this.postImages = const Value.absent(),
    this.topicName = const Value.absent(),
    this.stepsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlanScriptsCompanion.insert({
    required String id,
    required String name,
    this.isBuiltIn = const Value.absent(),
    this.postContent = const Value.absent(),
    this.postImages = const Value.absent(),
    this.topicName = const Value.absent(),
    this.stepsJson = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PlanScriptRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<bool>? isBuiltIn,
    Expression<String>? postContent,
    Expression<String>? postImages,
    Expression<String>? topicName,
    Expression<String>? stepsJson,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (isBuiltIn != null) 'is_built_in': isBuiltIn,
      if (postContent != null) 'post_content': postContent,
      if (postImages != null) 'post_images': postImages,
      if (topicName != null) 'topic_name': topicName,
      if (stepsJson != null) 'steps_json': stepsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlanScriptsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<bool>? isBuiltIn,
    Value<String>? postContent,
    Value<String>? postImages,
    Value<String?>? topicName,
    Value<String>? stepsJson,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return PlanScriptsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      postContent: postContent ?? this.postContent,
      postImages: postImages ?? this.postImages,
      topicName: topicName ?? this.topicName,
      stepsJson: stepsJson ?? this.stepsJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isBuiltIn.present) {
      map['is_built_in'] = Variable<bool>(isBuiltIn.value);
    }
    if (postContent.present) {
      map['post_content'] = Variable<String>(postContent.value);
    }
    if (postImages.present) {
      map['post_images'] = Variable<String>(postImages.value);
    }
    if (topicName.present) {
      map['topic_name'] = Variable<String>(topicName.value);
    }
    if (stepsJson.present) {
      map['steps_json'] = Variable<String>(stepsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlanScriptsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isBuiltIn: $isBuiltIn, ')
          ..write('postContent: $postContent, ')
          ..write('postImages: $postImages, ')
          ..write('topicName: $topicName, ')
          ..write('stepsJson: $stepsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlanEventsTable extends PlanEvents
    with TableInfo<$PlanEventsTable, PlanEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlanEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _postIdMeta = const VerificationMeta('postId');
  @override
  late final GeneratedColumn<String> postId = GeneratedColumn<String>(
    'post_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES posts (id)',
    ),
  );
  static const VerificationMeta _scriptIdMeta = const VerificationMeta(
    'scriptId',
  );
  @override
  late final GeneratedColumn<String> scriptId = GeneratedColumn<String>(
    'script_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _personaIdMeta = const VerificationMeta(
    'personaId',
  );
  @override
  late final GeneratedColumn<String> personaId = GeneratedColumn<String>(
    'persona_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
    'media_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _voiceAssetMeta = const VerificationMeta(
    'voiceAsset',
  );
  @override
  late final GeneratedColumn<String> voiceAsset = GeneratedColumn<String>(
    'voice_asset',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _voiceDurationMsMeta = const VerificationMeta(
    'voiceDurationMs',
  );
  @override
  late final GeneratedColumn<int> voiceDurationMs = GeneratedColumn<int>(
    'voice_duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _transcriptMeta = const VerificationMeta(
    'transcript',
  );
  @override
  late final GeneratedColumn<String> transcript = GeneratedColumn<String>(
    'transcript',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deltaMeta = const VerificationMeta('delta');
  @override
  late final GeneratedColumn<int> delta = GeneratedColumn<int>(
    'delta',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _likesMeta = const VerificationMeta('likes');
  @override
  late final GeneratedColumn<int> likes = GeneratedColumn<int>(
    'likes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _commentsMeta = const VerificationMeta(
    'comments',
  );
  @override
  late final GeneratedColumn<int> comments = GeneratedColumn<int>(
    'comments',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toModeMeta = const VerificationMeta('toMode');
  @override
  late final GeneratedColumn<String> toMode = GeneratedColumn<String>(
    'to_mode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _analysisJsonMeta = const VerificationMeta(
    'analysisJson',
  );
  @override
  late final GeneratedColumn<String> analysisJson = GeneratedColumn<String>(
    'analysis_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scheduledAtMeta = const VerificationMeta(
    'scheduledAt',
  );
  @override
  late final GeneratedColumn<int> scheduledAt = GeneratedColumn<int>(
    'scheduled_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _executedAtMeta = const VerificationMeta(
    'executedAt',
  );
  @override
  late final GeneratedColumn<int> executedAt = GeneratedColumn<int>(
    'executed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    postId,
    scriptId,
    type,
    personaId,
    mediaType,
    content,
    voiceAsset,
    voiceDurationMs,
    transcript,
    delta,
    likes,
    comments,
    toMode,
    analysisJson,
    scheduledAt,
    executedAt,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plan_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlanEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('post_id')) {
      context.handle(
        _postIdMeta,
        postId.isAcceptableOrUnknown(data['post_id']!, _postIdMeta),
      );
    } else if (isInserting) {
      context.missing(_postIdMeta);
    }
    if (data.containsKey('script_id')) {
      context.handle(
        _scriptIdMeta,
        scriptId.isAcceptableOrUnknown(data['script_id']!, _scriptIdMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('persona_id')) {
      context.handle(
        _personaIdMeta,
        personaId.isAcceptableOrUnknown(data['persona_id']!, _personaIdMeta),
      );
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('voice_asset')) {
      context.handle(
        _voiceAssetMeta,
        voiceAsset.isAcceptableOrUnknown(data['voice_asset']!, _voiceAssetMeta),
      );
    }
    if (data.containsKey('voice_duration_ms')) {
      context.handle(
        _voiceDurationMsMeta,
        voiceDurationMs.isAcceptableOrUnknown(
          data['voice_duration_ms']!,
          _voiceDurationMsMeta,
        ),
      );
    }
    if (data.containsKey('transcript')) {
      context.handle(
        _transcriptMeta,
        transcript.isAcceptableOrUnknown(data['transcript']!, _transcriptMeta),
      );
    }
    if (data.containsKey('delta')) {
      context.handle(
        _deltaMeta,
        delta.isAcceptableOrUnknown(data['delta']!, _deltaMeta),
      );
    }
    if (data.containsKey('likes')) {
      context.handle(
        _likesMeta,
        likes.isAcceptableOrUnknown(data['likes']!, _likesMeta),
      );
    }
    if (data.containsKey('comments')) {
      context.handle(
        _commentsMeta,
        comments.isAcceptableOrUnknown(data['comments']!, _commentsMeta),
      );
    }
    if (data.containsKey('to_mode')) {
      context.handle(
        _toModeMeta,
        toMode.isAcceptableOrUnknown(data['to_mode']!, _toModeMeta),
      );
    }
    if (data.containsKey('analysis_json')) {
      context.handle(
        _analysisJsonMeta,
        analysisJson.isAcceptableOrUnknown(
          data['analysis_json']!,
          _analysisJsonMeta,
        ),
      );
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
        _scheduledAtMeta,
        scheduledAt.isAcceptableOrUnknown(
          data['scheduled_at']!,
          _scheduledAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledAtMeta);
    }
    if (data.containsKey('executed_at')) {
      context.handle(
        _executedAtMeta,
        executedAt.isAcceptableOrUnknown(data['executed_at']!, _executedAtMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlanEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlanEventRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      postId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}post_id'],
      )!,
      scriptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}script_id'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      personaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}persona_id'],
      ),
      mediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_type'],
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      ),
      voiceAsset: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}voice_asset'],
      ),
      voiceDurationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}voice_duration_ms'],
      ),
      transcript: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transcript'],
      ),
      delta: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delta'],
      ),
      likes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}likes'],
      ),
      comments: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}comments'],
      ),
      toMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_mode'],
      ),
      analysisJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}analysis_json'],
      ),
      scheduledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scheduled_at'],
      )!,
      executedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}executed_at'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $PlanEventsTable createAlias(String alias) {
    return $PlanEventsTable(attachedDatabase, alias);
  }
}

class PlanEventRow extends DataClass implements Insertable<PlanEventRow> {
  final String id;
  final String postId;
  final String? scriptId;

  /// like_burst / comment / stats / mode / analysis
  final String type;
  final String? personaId;
  final String? mediaType;
  final String? content;
  final String? voiceAsset;

  /// 语音条时长（毫秒）。脚本里带过来的，评论区靠它显示 "6"" 而不是 "0""。
  final int? voiceDurationMs;
  final String? transcript;

  /// like_burst：这一批多少个赞
  final int? delta;

  /// stats：直接设定的赞数 / 评论数
  final int? likes;
  final int? comments;

  /// mode：目标模式
  final String? toMode;

  /// analysis：五项分析（JSON）
  final String? analysisJson;
  final int scheduledAt;
  final int? executedAt;

  /// pending / done / cancelled
  final String status;
  const PlanEventRow({
    required this.id,
    required this.postId,
    this.scriptId,
    required this.type,
    this.personaId,
    this.mediaType,
    this.content,
    this.voiceAsset,
    this.voiceDurationMs,
    this.transcript,
    this.delta,
    this.likes,
    this.comments,
    this.toMode,
    this.analysisJson,
    required this.scheduledAt,
    this.executedAt,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['post_id'] = Variable<String>(postId);
    if (!nullToAbsent || scriptId != null) {
      map['script_id'] = Variable<String>(scriptId);
    }
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || personaId != null) {
      map['persona_id'] = Variable<String>(personaId);
    }
    if (!nullToAbsent || mediaType != null) {
      map['media_type'] = Variable<String>(mediaType);
    }
    if (!nullToAbsent || content != null) {
      map['content'] = Variable<String>(content);
    }
    if (!nullToAbsent || voiceAsset != null) {
      map['voice_asset'] = Variable<String>(voiceAsset);
    }
    if (!nullToAbsent || voiceDurationMs != null) {
      map['voice_duration_ms'] = Variable<int>(voiceDurationMs);
    }
    if (!nullToAbsent || transcript != null) {
      map['transcript'] = Variable<String>(transcript);
    }
    if (!nullToAbsent || delta != null) {
      map['delta'] = Variable<int>(delta);
    }
    if (!nullToAbsent || likes != null) {
      map['likes'] = Variable<int>(likes);
    }
    if (!nullToAbsent || comments != null) {
      map['comments'] = Variable<int>(comments);
    }
    if (!nullToAbsent || toMode != null) {
      map['to_mode'] = Variable<String>(toMode);
    }
    if (!nullToAbsent || analysisJson != null) {
      map['analysis_json'] = Variable<String>(analysisJson);
    }
    map['scheduled_at'] = Variable<int>(scheduledAt);
    if (!nullToAbsent || executedAt != null) {
      map['executed_at'] = Variable<int>(executedAt);
    }
    map['status'] = Variable<String>(status);
    return map;
  }

  PlanEventsCompanion toCompanion(bool nullToAbsent) {
    return PlanEventsCompanion(
      id: Value(id),
      postId: Value(postId),
      scriptId: scriptId == null && nullToAbsent
          ? const Value.absent()
          : Value(scriptId),
      type: Value(type),
      personaId: personaId == null && nullToAbsent
          ? const Value.absent()
          : Value(personaId),
      mediaType: mediaType == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaType),
      content: content == null && nullToAbsent
          ? const Value.absent()
          : Value(content),
      voiceAsset: voiceAsset == null && nullToAbsent
          ? const Value.absent()
          : Value(voiceAsset),
      voiceDurationMs: voiceDurationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(voiceDurationMs),
      transcript: transcript == null && nullToAbsent
          ? const Value.absent()
          : Value(transcript),
      delta: delta == null && nullToAbsent
          ? const Value.absent()
          : Value(delta),
      likes: likes == null && nullToAbsent
          ? const Value.absent()
          : Value(likes),
      comments: comments == null && nullToAbsent
          ? const Value.absent()
          : Value(comments),
      toMode: toMode == null && nullToAbsent
          ? const Value.absent()
          : Value(toMode),
      analysisJson: analysisJson == null && nullToAbsent
          ? const Value.absent()
          : Value(analysisJson),
      scheduledAt: Value(scheduledAt),
      executedAt: executedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(executedAt),
      status: Value(status),
    );
  }

  factory PlanEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlanEventRow(
      id: serializer.fromJson<String>(json['id']),
      postId: serializer.fromJson<String>(json['postId']),
      scriptId: serializer.fromJson<String?>(json['scriptId']),
      type: serializer.fromJson<String>(json['type']),
      personaId: serializer.fromJson<String?>(json['personaId']),
      mediaType: serializer.fromJson<String?>(json['mediaType']),
      content: serializer.fromJson<String?>(json['content']),
      voiceAsset: serializer.fromJson<String?>(json['voiceAsset']),
      voiceDurationMs: serializer.fromJson<int?>(json['voiceDurationMs']),
      transcript: serializer.fromJson<String?>(json['transcript']),
      delta: serializer.fromJson<int?>(json['delta']),
      likes: serializer.fromJson<int?>(json['likes']),
      comments: serializer.fromJson<int?>(json['comments']),
      toMode: serializer.fromJson<String?>(json['toMode']),
      analysisJson: serializer.fromJson<String?>(json['analysisJson']),
      scheduledAt: serializer.fromJson<int>(json['scheduledAt']),
      executedAt: serializer.fromJson<int?>(json['executedAt']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'postId': serializer.toJson<String>(postId),
      'scriptId': serializer.toJson<String?>(scriptId),
      'type': serializer.toJson<String>(type),
      'personaId': serializer.toJson<String?>(personaId),
      'mediaType': serializer.toJson<String?>(mediaType),
      'content': serializer.toJson<String?>(content),
      'voiceAsset': serializer.toJson<String?>(voiceAsset),
      'voiceDurationMs': serializer.toJson<int?>(voiceDurationMs),
      'transcript': serializer.toJson<String?>(transcript),
      'delta': serializer.toJson<int?>(delta),
      'likes': serializer.toJson<int?>(likes),
      'comments': serializer.toJson<int?>(comments),
      'toMode': serializer.toJson<String?>(toMode),
      'analysisJson': serializer.toJson<String?>(analysisJson),
      'scheduledAt': serializer.toJson<int>(scheduledAt),
      'executedAt': serializer.toJson<int?>(executedAt),
      'status': serializer.toJson<String>(status),
    };
  }

  PlanEventRow copyWith({
    String? id,
    String? postId,
    Value<String?> scriptId = const Value.absent(),
    String? type,
    Value<String?> personaId = const Value.absent(),
    Value<String?> mediaType = const Value.absent(),
    Value<String?> content = const Value.absent(),
    Value<String?> voiceAsset = const Value.absent(),
    Value<int?> voiceDurationMs = const Value.absent(),
    Value<String?> transcript = const Value.absent(),
    Value<int?> delta = const Value.absent(),
    Value<int?> likes = const Value.absent(),
    Value<int?> comments = const Value.absent(),
    Value<String?> toMode = const Value.absent(),
    Value<String?> analysisJson = const Value.absent(),
    int? scheduledAt,
    Value<int?> executedAt = const Value.absent(),
    String? status,
  }) => PlanEventRow(
    id: id ?? this.id,
    postId: postId ?? this.postId,
    scriptId: scriptId.present ? scriptId.value : this.scriptId,
    type: type ?? this.type,
    personaId: personaId.present ? personaId.value : this.personaId,
    mediaType: mediaType.present ? mediaType.value : this.mediaType,
    content: content.present ? content.value : this.content,
    voiceAsset: voiceAsset.present ? voiceAsset.value : this.voiceAsset,
    voiceDurationMs: voiceDurationMs.present
        ? voiceDurationMs.value
        : this.voiceDurationMs,
    transcript: transcript.present ? transcript.value : this.transcript,
    delta: delta.present ? delta.value : this.delta,
    likes: likes.present ? likes.value : this.likes,
    comments: comments.present ? comments.value : this.comments,
    toMode: toMode.present ? toMode.value : this.toMode,
    analysisJson: analysisJson.present ? analysisJson.value : this.analysisJson,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    executedAt: executedAt.present ? executedAt.value : this.executedAt,
    status: status ?? this.status,
  );
  PlanEventRow copyWithCompanion(PlanEventsCompanion data) {
    return PlanEventRow(
      id: data.id.present ? data.id.value : this.id,
      postId: data.postId.present ? data.postId.value : this.postId,
      scriptId: data.scriptId.present ? data.scriptId.value : this.scriptId,
      type: data.type.present ? data.type.value : this.type,
      personaId: data.personaId.present ? data.personaId.value : this.personaId,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      content: data.content.present ? data.content.value : this.content,
      voiceAsset: data.voiceAsset.present
          ? data.voiceAsset.value
          : this.voiceAsset,
      voiceDurationMs: data.voiceDurationMs.present
          ? data.voiceDurationMs.value
          : this.voiceDurationMs,
      transcript: data.transcript.present
          ? data.transcript.value
          : this.transcript,
      delta: data.delta.present ? data.delta.value : this.delta,
      likes: data.likes.present ? data.likes.value : this.likes,
      comments: data.comments.present ? data.comments.value : this.comments,
      toMode: data.toMode.present ? data.toMode.value : this.toMode,
      analysisJson: data.analysisJson.present
          ? data.analysisJson.value
          : this.analysisJson,
      scheduledAt: data.scheduledAt.present
          ? data.scheduledAt.value
          : this.scheduledAt,
      executedAt: data.executedAt.present
          ? data.executedAt.value
          : this.executedAt,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlanEventRow(')
          ..write('id: $id, ')
          ..write('postId: $postId, ')
          ..write('scriptId: $scriptId, ')
          ..write('type: $type, ')
          ..write('personaId: $personaId, ')
          ..write('mediaType: $mediaType, ')
          ..write('content: $content, ')
          ..write('voiceAsset: $voiceAsset, ')
          ..write('voiceDurationMs: $voiceDurationMs, ')
          ..write('transcript: $transcript, ')
          ..write('delta: $delta, ')
          ..write('likes: $likes, ')
          ..write('comments: $comments, ')
          ..write('toMode: $toMode, ')
          ..write('analysisJson: $analysisJson, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('executedAt: $executedAt, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    postId,
    scriptId,
    type,
    personaId,
    mediaType,
    content,
    voiceAsset,
    voiceDurationMs,
    transcript,
    delta,
    likes,
    comments,
    toMode,
    analysisJson,
    scheduledAt,
    executedAt,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlanEventRow &&
          other.id == this.id &&
          other.postId == this.postId &&
          other.scriptId == this.scriptId &&
          other.type == this.type &&
          other.personaId == this.personaId &&
          other.mediaType == this.mediaType &&
          other.content == this.content &&
          other.voiceAsset == this.voiceAsset &&
          other.voiceDurationMs == this.voiceDurationMs &&
          other.transcript == this.transcript &&
          other.delta == this.delta &&
          other.likes == this.likes &&
          other.comments == this.comments &&
          other.toMode == this.toMode &&
          other.analysisJson == this.analysisJson &&
          other.scheduledAt == this.scheduledAt &&
          other.executedAt == this.executedAt &&
          other.status == this.status);
}

class PlanEventsCompanion extends UpdateCompanion<PlanEventRow> {
  final Value<String> id;
  final Value<String> postId;
  final Value<String?> scriptId;
  final Value<String> type;
  final Value<String?> personaId;
  final Value<String?> mediaType;
  final Value<String?> content;
  final Value<String?> voiceAsset;
  final Value<int?> voiceDurationMs;
  final Value<String?> transcript;
  final Value<int?> delta;
  final Value<int?> likes;
  final Value<int?> comments;
  final Value<String?> toMode;
  final Value<String?> analysisJson;
  final Value<int> scheduledAt;
  final Value<int?> executedAt;
  final Value<String> status;
  final Value<int> rowid;
  const PlanEventsCompanion({
    this.id = const Value.absent(),
    this.postId = const Value.absent(),
    this.scriptId = const Value.absent(),
    this.type = const Value.absent(),
    this.personaId = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.content = const Value.absent(),
    this.voiceAsset = const Value.absent(),
    this.voiceDurationMs = const Value.absent(),
    this.transcript = const Value.absent(),
    this.delta = const Value.absent(),
    this.likes = const Value.absent(),
    this.comments = const Value.absent(),
    this.toMode = const Value.absent(),
    this.analysisJson = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.executedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlanEventsCompanion.insert({
    required String id,
    required String postId,
    this.scriptId = const Value.absent(),
    required String type,
    this.personaId = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.content = const Value.absent(),
    this.voiceAsset = const Value.absent(),
    this.voiceDurationMs = const Value.absent(),
    this.transcript = const Value.absent(),
    this.delta = const Value.absent(),
    this.likes = const Value.absent(),
    this.comments = const Value.absent(),
    this.toMode = const Value.absent(),
    this.analysisJson = const Value.absent(),
    required int scheduledAt,
    this.executedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       postId = Value(postId),
       type = Value(type),
       scheduledAt = Value(scheduledAt);
  static Insertable<PlanEventRow> custom({
    Expression<String>? id,
    Expression<String>? postId,
    Expression<String>? scriptId,
    Expression<String>? type,
    Expression<String>? personaId,
    Expression<String>? mediaType,
    Expression<String>? content,
    Expression<String>? voiceAsset,
    Expression<int>? voiceDurationMs,
    Expression<String>? transcript,
    Expression<int>? delta,
    Expression<int>? likes,
    Expression<int>? comments,
    Expression<String>? toMode,
    Expression<String>? analysisJson,
    Expression<int>? scheduledAt,
    Expression<int>? executedAt,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (postId != null) 'post_id': postId,
      if (scriptId != null) 'script_id': scriptId,
      if (type != null) 'type': type,
      if (personaId != null) 'persona_id': personaId,
      if (mediaType != null) 'media_type': mediaType,
      if (content != null) 'content': content,
      if (voiceAsset != null) 'voice_asset': voiceAsset,
      if (voiceDurationMs != null) 'voice_duration_ms': voiceDurationMs,
      if (transcript != null) 'transcript': transcript,
      if (delta != null) 'delta': delta,
      if (likes != null) 'likes': likes,
      if (comments != null) 'comments': comments,
      if (toMode != null) 'to_mode': toMode,
      if (analysisJson != null) 'analysis_json': analysisJson,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (executedAt != null) 'executed_at': executedAt,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlanEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? postId,
    Value<String?>? scriptId,
    Value<String>? type,
    Value<String?>? personaId,
    Value<String?>? mediaType,
    Value<String?>? content,
    Value<String?>? voiceAsset,
    Value<int?>? voiceDurationMs,
    Value<String?>? transcript,
    Value<int?>? delta,
    Value<int?>? likes,
    Value<int?>? comments,
    Value<String?>? toMode,
    Value<String?>? analysisJson,
    Value<int>? scheduledAt,
    Value<int?>? executedAt,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return PlanEventsCompanion(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      scriptId: scriptId ?? this.scriptId,
      type: type ?? this.type,
      personaId: personaId ?? this.personaId,
      mediaType: mediaType ?? this.mediaType,
      content: content ?? this.content,
      voiceAsset: voiceAsset ?? this.voiceAsset,
      voiceDurationMs: voiceDurationMs ?? this.voiceDurationMs,
      transcript: transcript ?? this.transcript,
      delta: delta ?? this.delta,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      toMode: toMode ?? this.toMode,
      analysisJson: analysisJson ?? this.analysisJson,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      executedAt: executedAt ?? this.executedAt,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (postId.present) {
      map['post_id'] = Variable<String>(postId.value);
    }
    if (scriptId.present) {
      map['script_id'] = Variable<String>(scriptId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (personaId.present) {
      map['persona_id'] = Variable<String>(personaId.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (voiceAsset.present) {
      map['voice_asset'] = Variable<String>(voiceAsset.value);
    }
    if (voiceDurationMs.present) {
      map['voice_duration_ms'] = Variable<int>(voiceDurationMs.value);
    }
    if (transcript.present) {
      map['transcript'] = Variable<String>(transcript.value);
    }
    if (delta.present) {
      map['delta'] = Variable<int>(delta.value);
    }
    if (likes.present) {
      map['likes'] = Variable<int>(likes.value);
    }
    if (comments.present) {
      map['comments'] = Variable<int>(comments.value);
    }
    if (toMode.present) {
      map['to_mode'] = Variable<String>(toMode.value);
    }
    if (analysisJson.present) {
      map['analysis_json'] = Variable<String>(analysisJson.value);
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<int>(scheduledAt.value);
    }
    if (executedAt.present) {
      map['executed_at'] = Variable<int>(executedAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlanEventsCompanion(')
          ..write('id: $id, ')
          ..write('postId: $postId, ')
          ..write('scriptId: $scriptId, ')
          ..write('type: $type, ')
          ..write('personaId: $personaId, ')
          ..write('mediaType: $mediaType, ')
          ..write('content: $content, ')
          ..write('voiceAsset: $voiceAsset, ')
          ..write('voiceDurationMs: $voiceDurationMs, ')
          ..write('transcript: $transcript, ')
          ..write('delta: $delta, ')
          ..write('likes: $likes, ')
          ..write('comments: $comments, ')
          ..write('toMode: $toMode, ')
          ..write('analysisJson: $analysisJson, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('executedAt: $executedAt, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ModelConfigsTable extends ModelConfigs
    with TableInfo<$ModelConfigsTable, ModelConfigRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ModelConfigsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseUrlMeta = const VerificationMeta(
    'baseUrl',
  );
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
    'base_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    provider,
    label,
    baseUrl,
    model,
    enabled,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'model_configs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ModelConfigRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('base_url')) {
      context.handle(
        _baseUrlMeta,
        baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ModelConfigRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ModelConfigRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      baseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_url'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ModelConfigsTable createAlias(String alias) {
    return $ModelConfigsTable(attachedDatabase, alias);
  }
}

class ModelConfigRow extends DataClass implements Insertable<ModelConfigRow> {
  final String id;

  /// 预设服务商标识：openai / deepseek / qwen / zhipu / custom
  final String provider;

  /// 展示名，用户可改
  final String label;

  /// OpenAI 兼容的 base url（不带 /chat/completions）
  final String baseUrl;
  final String model;

  /// 当前启用中的那一条为 true（同一时间只允许一条）
  final bool enabled;
  final int createdAt;
  final int updatedAt;
  const ModelConfigRow({
    required this.id,
    required this.provider,
    required this.label,
    required this.baseUrl,
    required this.model,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['provider'] = Variable<String>(provider);
    map['label'] = Variable<String>(label);
    map['base_url'] = Variable<String>(baseUrl);
    map['model'] = Variable<String>(model);
    map['enabled'] = Variable<bool>(enabled);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ModelConfigsCompanion toCompanion(bool nullToAbsent) {
    return ModelConfigsCompanion(
      id: Value(id),
      provider: Value(provider),
      label: Value(label),
      baseUrl: Value(baseUrl),
      model: Value(model),
      enabled: Value(enabled),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ModelConfigRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ModelConfigRow(
      id: serializer.fromJson<String>(json['id']),
      provider: serializer.fromJson<String>(json['provider']),
      label: serializer.fromJson<String>(json['label']),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      model: serializer.fromJson<String>(json['model']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'provider': serializer.toJson<String>(provider),
      'label': serializer.toJson<String>(label),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'model': serializer.toJson<String>(model),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  ModelConfigRow copyWith({
    String? id,
    String? provider,
    String? label,
    String? baseUrl,
    String? model,
    bool? enabled,
    int? createdAt,
    int? updatedAt,
  }) => ModelConfigRow(
    id: id ?? this.id,
    provider: provider ?? this.provider,
    label: label ?? this.label,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ModelConfigRow copyWithCompanion(ModelConfigsCompanion data) {
    return ModelConfigRow(
      id: data.id.present ? data.id.value : this.id,
      provider: data.provider.present ? data.provider.value : this.provider,
      label: data.label.present ? data.label.value : this.label,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      model: data.model.present ? data.model.value : this.model,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ModelConfigRow(')
          ..write('id: $id, ')
          ..write('provider: $provider, ')
          ..write('label: $label, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('model: $model, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    provider,
    label,
    baseUrl,
    model,
    enabled,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ModelConfigRow &&
          other.id == this.id &&
          other.provider == this.provider &&
          other.label == this.label &&
          other.baseUrl == this.baseUrl &&
          other.model == this.model &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ModelConfigsCompanion extends UpdateCompanion<ModelConfigRow> {
  final Value<String> id;
  final Value<String> provider;
  final Value<String> label;
  final Value<String> baseUrl;
  final Value<String> model;
  final Value<bool> enabled;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const ModelConfigsCompanion({
    this.id = const Value.absent(),
    this.provider = const Value.absent(),
    this.label = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.model = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ModelConfigsCompanion.insert({
    required String id,
    required String provider,
    required String label,
    required String baseUrl,
    required String model,
    this.enabled = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       provider = Value(provider),
       label = Value(label),
       baseUrl = Value(baseUrl),
       model = Value(model),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ModelConfigRow> custom({
    Expression<String>? id,
    Expression<String>? provider,
    Expression<String>? label,
    Expression<String>? baseUrl,
    Expression<String>? model,
    Expression<bool>? enabled,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (provider != null) 'provider': provider,
      if (label != null) 'label': label,
      if (baseUrl != null) 'base_url': baseUrl,
      if (model != null) 'model': model,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ModelConfigsCompanion copyWith({
    Value<String>? id,
    Value<String>? provider,
    Value<String>? label,
    Value<String>? baseUrl,
    Value<String>? model,
    Value<bool>? enabled,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return ModelConfigsCompanion(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      label: label ?? this.label,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ModelConfigsCompanion(')
          ..write('id: $id, ')
          ..write('provider: $provider, ')
          ..write('label: $label, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('model: $model, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ValueClarificationsTable extends ValueClarifications
    with TableInfo<$ValueClarificationsTable, ValueClarificationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ValueClarificationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('clear'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    content,
    sortOrder,
    createdAt,
    deletedAt,
    scope,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'value_clarifications';
  @override
  VerificationContext validateIntegrity(
    Insertable<ValueClarificationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ValueClarificationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ValueClarificationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
    );
  }

  @override
  $ValueClarificationsTable createAlias(String alias) {
    return $ValueClarificationsTable(attachedDatabase, alias);
  }
}

class ValueClarificationRow extends DataClass
    implements Insertable<ValueClarificationRow> {
  final String id;
  final String content;
  final int sortOrder;
  final int createdAt;
  final int? deletedAt;
  final String scope;
  const ValueClarificationRow({
    required this.id,
    required this.content,
    required this.sortOrder,
    required this.createdAt,
    this.deletedAt,
    required this.scope,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['content'] = Variable<String>(content);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['scope'] = Variable<String>(scope);
    return map;
  }

  ValueClarificationsCompanion toCompanion(bool nullToAbsent) {
    return ValueClarificationsCompanion(
      id: Value(id),
      content: Value(content),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      scope: Value(scope),
    );
  }

  factory ValueClarificationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ValueClarificationRow(
      id: serializer.fromJson<String>(json['id']),
      content: serializer.fromJson<String>(json['content']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      scope: serializer.fromJson<String>(json['scope']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'content': serializer.toJson<String>(content),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<int>(createdAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'scope': serializer.toJson<String>(scope),
    };
  }

  ValueClarificationRow copyWith({
    String? id,
    String? content,
    int? sortOrder,
    int? createdAt,
    Value<int?> deletedAt = const Value.absent(),
    String? scope,
  }) => ValueClarificationRow(
    id: id ?? this.id,
    content: content ?? this.content,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    scope: scope ?? this.scope,
  );
  ValueClarificationRow copyWithCompanion(ValueClarificationsCompanion data) {
    return ValueClarificationRow(
      id: data.id.present ? data.id.value : this.id,
      content: data.content.present ? data.content.value : this.content,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      scope: data.scope.present ? data.scope.value : this.scope,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ValueClarificationRow(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('scope: $scope')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, content, sortOrder, createdAt, deletedAt, scope);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ValueClarificationRow &&
          other.id == this.id &&
          other.content == this.content &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.deletedAt == this.deletedAt &&
          other.scope == this.scope);
}

class ValueClarificationsCompanion
    extends UpdateCompanion<ValueClarificationRow> {
  final Value<String> id;
  final Value<String> content;
  final Value<int> sortOrder;
  final Value<int> createdAt;
  final Value<int?> deletedAt;
  final Value<String> scope;
  final Value<int> rowid;
  const ValueClarificationsCompanion({
    this.id = const Value.absent(),
    this.content = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ValueClarificationsCompanion.insert({
    required String id,
    required String content,
    this.sortOrder = const Value.absent(),
    required int createdAt,
    this.deletedAt = const Value.absent(),
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       content = Value(content),
       createdAt = Value(createdAt);
  static Insertable<ValueClarificationRow> custom({
    Expression<String>? id,
    Expression<String>? content,
    Expression<int>? sortOrder,
    Expression<int>? createdAt,
    Expression<int>? deletedAt,
    Expression<String>? scope,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (content != null) 'content': content,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (scope != null) 'scope': scope,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ValueClarificationsCompanion copyWith({
    Value<String>? id,
    Value<String>? content,
    Value<int>? sortOrder,
    Value<int>? createdAt,
    Value<int?>? deletedAt,
    Value<String>? scope,
    Value<int>? rowid,
  }) {
    return ValueClarificationsCompanion(
      id: id ?? this.id,
      content: content ?? this.content,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
      scope: scope ?? this.scope,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ValueClarificationsCompanion(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('scope: $scope, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RealActionsTable extends RealActions
    with TableInfo<$RealActionsTable, RealActionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RealActionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('clear'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    description,
    category,
    createdAt,
    deletedAt,
    scope,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'real_actions';
  @override
  VerificationContext validateIntegrity(
    Insertable<RealActionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RealActionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RealActionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
    );
  }

  @override
  $RealActionsTable createAlias(String alias) {
    return $RealActionsTable(attachedDatabase, alias);
  }
}

class RealActionRow extends DataClass implements Insertable<RealActionRow> {
  final String id;
  final String title;
  final String description;

  /// sport / reading / social / creation / other，见 `RealActionCategory`。
  final String category;
  final int createdAt;
  final int? deletedAt;
  final String scope;
  const RealActionRow({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.createdAt,
    this.deletedAt,
    required this.scope,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['category'] = Variable<String>(category);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['scope'] = Variable<String>(scope);
    return map;
  }

  RealActionsCompanion toCompanion(bool nullToAbsent) {
    return RealActionsCompanion(
      id: Value(id),
      title: Value(title),
      description: Value(description),
      category: Value(category),
      createdAt: Value(createdAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      scope: Value(scope),
    );
  }

  factory RealActionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RealActionRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      category: serializer.fromJson<String>(json['category']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      scope: serializer.fromJson<String>(json['scope']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'category': serializer.toJson<String>(category),
      'createdAt': serializer.toJson<int>(createdAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'scope': serializer.toJson<String>(scope),
    };
  }

  RealActionRow copyWith({
    String? id,
    String? title,
    String? description,
    String? category,
    int? createdAt,
    Value<int?> deletedAt = const Value.absent(),
    String? scope,
  }) => RealActionRow(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    category: category ?? this.category,
    createdAt: createdAt ?? this.createdAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    scope: scope ?? this.scope,
  );
  RealActionRow copyWithCompanion(RealActionsCompanion data) {
    return RealActionRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      category: data.category.present ? data.category.value : this.category,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      scope: data.scope.present ? data.scope.value : this.scope,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RealActionRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('scope: $scope')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    category,
    createdAt,
    deletedAt,
    scope,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RealActionRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.description == this.description &&
          other.category == this.category &&
          other.createdAt == this.createdAt &&
          other.deletedAt == this.deletedAt &&
          other.scope == this.scope);
}

class RealActionsCompanion extends UpdateCompanion<RealActionRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> description;
  final Value<String> category;
  final Value<int> createdAt;
  final Value<int?> deletedAt;
  final Value<String> scope;
  final Value<int> rowid;
  const RealActionsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.category = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RealActionsCompanion.insert({
    required String id,
    required String title,
    this.description = const Value.absent(),
    required String category,
    required int createdAt,
    this.deletedAt = const Value.absent(),
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       category = Value(category),
       createdAt = Value(createdAt);
  static Insertable<RealActionRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? category,
    Expression<int>? createdAt,
    Expression<int>? deletedAt,
    Expression<String>? scope,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (category != null) 'category': category,
      if (createdAt != null) 'created_at': createdAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (scope != null) 'scope': scope,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RealActionsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? description,
    Value<String>? category,
    Value<int>? createdAt,
    Value<int?>? deletedAt,
    Value<String>? scope,
    Value<int>? rowid,
  }) {
    return RealActionsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
      scope: scope ?? this.scope,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RealActionsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('scope: $scope, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AddictionLogsTable extends AddictionLogs
    with TableInfo<$AddictionLogsTable, AddictionLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AddictionLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<int> value = GeneratedColumn<int>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('shared'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    eventType,
    value,
    createdAt,
    scope,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'addiction_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<AddictionLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AddictionLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AddictionLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}value'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
    );
  }

  @override
  $AddictionLogsTable createAlias(String alias) {
    return $AddictionLogsTable(attachedDatabase, alias);
  }
}

class AddictionLogRow extends DataClass implements Insertable<AddictionLogRow> {
  final String id;

  /// feedback_threshold / cooldown_on / cooldown_off / session_long
  final String eventType;

  /// 事件附带的数值：触发时的查看次数、使用时长（分钟）等。
  final int value;
  final int createdAt;
  final String scope;
  const AddictionLogRow({
    required this.id,
    required this.eventType,
    required this.value,
    required this.createdAt,
    required this.scope,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['event_type'] = Variable<String>(eventType);
    map['value'] = Variable<int>(value);
    map['created_at'] = Variable<int>(createdAt);
    map['scope'] = Variable<String>(scope);
    return map;
  }

  AddictionLogsCompanion toCompanion(bool nullToAbsent) {
    return AddictionLogsCompanion(
      id: Value(id),
      eventType: Value(eventType),
      value: Value(value),
      createdAt: Value(createdAt),
      scope: Value(scope),
    );
  }

  factory AddictionLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AddictionLogRow(
      id: serializer.fromJson<String>(json['id']),
      eventType: serializer.fromJson<String>(json['eventType']),
      value: serializer.fromJson<int>(json['value']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      scope: serializer.fromJson<String>(json['scope']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'eventType': serializer.toJson<String>(eventType),
      'value': serializer.toJson<int>(value),
      'createdAt': serializer.toJson<int>(createdAt),
      'scope': serializer.toJson<String>(scope),
    };
  }

  AddictionLogRow copyWith({
    String? id,
    String? eventType,
    int? value,
    int? createdAt,
    String? scope,
  }) => AddictionLogRow(
    id: id ?? this.id,
    eventType: eventType ?? this.eventType,
    value: value ?? this.value,
    createdAt: createdAt ?? this.createdAt,
    scope: scope ?? this.scope,
  );
  AddictionLogRow copyWithCompanion(AddictionLogsCompanion data) {
    return AddictionLogRow(
      id: data.id.present ? data.id.value : this.id,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      value: data.value.present ? data.value.value : this.value,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      scope: data.scope.present ? data.scope.value : this.scope,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AddictionLogRow(')
          ..write('id: $id, ')
          ..write('eventType: $eventType, ')
          ..write('value: $value, ')
          ..write('createdAt: $createdAt, ')
          ..write('scope: $scope')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, eventType, value, createdAt, scope);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AddictionLogRow &&
          other.id == this.id &&
          other.eventType == this.eventType &&
          other.value == this.value &&
          other.createdAt == this.createdAt &&
          other.scope == this.scope);
}

class AddictionLogsCompanion extends UpdateCompanion<AddictionLogRow> {
  final Value<String> id;
  final Value<String> eventType;
  final Value<int> value;
  final Value<int> createdAt;
  final Value<String> scope;
  final Value<int> rowid;
  const AddictionLogsCompanion({
    this.id = const Value.absent(),
    this.eventType = const Value.absent(),
    this.value = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AddictionLogsCompanion.insert({
    required String id,
    required String eventType,
    this.value = const Value.absent(),
    required int createdAt,
    this.scope = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       eventType = Value(eventType),
       createdAt = Value(createdAt);
  static Insertable<AddictionLogRow> custom({
    Expression<String>? id,
    Expression<String>? eventType,
    Expression<int>? value,
    Expression<int>? createdAt,
    Expression<String>? scope,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (eventType != null) 'event_type': eventType,
      if (value != null) 'value': value,
      if (createdAt != null) 'created_at': createdAt,
      if (scope != null) 'scope': scope,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AddictionLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? eventType,
    Value<int>? value,
    Value<int>? createdAt,
    Value<String>? scope,
    Value<int>? rowid,
  }) {
    return AddictionLogsCompanion(
      id: id ?? this.id,
      eventType: eventType ?? this.eventType,
      value: value ?? this.value,
      createdAt: createdAt ?? this.createdAt,
      scope: scope ?? this.scope,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (value.present) {
      map['value'] = Variable<int>(value.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AddictionLogsCompanion(')
          ..write('id: $id, ')
          ..write('eventType: $eventType, ')
          ..write('value: $value, ')
          ..write('createdAt: $createdAt, ')
          ..write('scope: $scope, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $UserProfileTable userProfile = $UserProfileTable(this);
  late final $PostsTable posts = $PostsTable(this);
  late final $AiPersonasTable aiPersonas = $AiPersonasTable(this);
  late final $AiInteractionsTable aiInteractions = $AiInteractionsTable(this);
  late final $AnalysisResultsTable analysisResults = $AnalysisResultsTable(
    this,
  );
  late final $ModeSwitchLogsTable modeSwitchLogs = $ModeSwitchLogsTable(this);
  late final $NotificationLogsTable notificationLogs = $NotificationLogsTable(
    this,
  );
  late final $FeedbackViewLogsTable feedbackViewLogs = $FeedbackViewLogsTable(
    this,
  );
  late final $StickersTable stickers = $StickersTable(this);
  late final $PlanScriptsTable planScripts = $PlanScriptsTable(this);
  late final $PlanEventsTable planEvents = $PlanEventsTable(this);
  late final $ModelConfigsTable modelConfigs = $ModelConfigsTable(this);
  late final $ValueClarificationsTable valueClarifications =
      $ValueClarificationsTable(this);
  late final $RealActionsTable realActions = $RealActionsTable(this);
  late final $AddictionLogsTable addictionLogs = $AddictionLogsTable(this);
  late final Index postsCreatedAt = Index(
    'posts_created_at',
    'CREATE INDEX posts_created_at ON posts (created_at)',
  );
  late final Index aiInteractionsLookup = Index(
    'ai_interactions_lookup',
    'CREATE INDEX ai_interactions_lookup ON ai_interactions (post_id, persona_id, status)',
  );
  late final Index aiInteractionsScheduled = Index(
    'ai_interactions_scheduled',
    'CREATE INDEX ai_interactions_scheduled ON ai_interactions (scheduled_at)',
  );
  late final Index notificationLogsDelivered = Index(
    'notification_logs_delivered',
    'CREATE INDEX notification_logs_delivered ON notification_logs (delivered_at)',
  );
  late final Index planEventsDue = Index(
    'plan_events_due',
    'CREATE INDEX plan_events_due ON plan_events (status, scheduled_at)',
  );
  late final Index realActionsCreated = Index(
    'real_actions_created',
    'CREATE INDEX real_actions_created ON real_actions (created_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    appSettings,
    userProfile,
    posts,
    aiPersonas,
    aiInteractions,
    analysisResults,
    modeSwitchLogs,
    notificationLogs,
    feedbackViewLogs,
    stickers,
    planScripts,
    planEvents,
    modelConfigs,
    valueClarifications,
    realActions,
    addictionLogs,
    postsCreatedAt,
    aiInteractionsLookup,
    aiInteractionsScheduled,
    notificationLogsDelivered,
    planEventsDue,
    realActionsCreated,
  ];
}

typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<String> scope,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<String> scope,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSettingRow,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSettingRow,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSettingRow>,
          ),
          AppSettingRow,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(
                key: key,
                value: value,
                scope: scope,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                scope: scope,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSettingRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AppSettingsTable,
                    AppSettingRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSettingRow,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSettingRow,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSettingRow>,
      ),
      AppSettingRow,
      PrefetchHooks Function()
    >;
typedef $$UserProfileTableCreateCompanionBuilder =
    UserProfileCompanion Function({
      required String id,
      Value<String> nickname,
      Value<String> avatar,
      Value<String> signature,
      Value<int> level,
      Value<int> exp,
      Value<int> followers,
      Value<int> following,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$UserProfileTableUpdateCompanionBuilder =
    UserProfileCompanion Function({
      Value<String> id,
      Value<String> nickname,
      Value<String> avatar,
      Value<String> signature,
      Value<int> level,
      Value<int> exp,
      Value<int> followers,
      Value<int> following,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$UserProfileTableFilterComposer
    extends Composer<_$AppDatabase, $UserProfileTable> {
  $$UserProfileTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get exp => $composableBuilder(
    column: $table.exp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get followers => $composableBuilder(
    column: $table.followers,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get following => $composableBuilder(
    column: $table.following,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserProfileTableOrderingComposer
    extends Composer<_$AppDatabase, $UserProfileTable> {
  $$UserProfileTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get exp => $composableBuilder(
    column: $table.exp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get followers => $composableBuilder(
    column: $table.followers,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get following => $composableBuilder(
    column: $table.following,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserProfileTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserProfileTable> {
  $$UserProfileTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get nickname =>
      $composableBuilder(column: $table.nickname, builder: (column) => column);

  GeneratedColumn<String> get avatar =>
      $composableBuilder(column: $table.avatar, builder: (column) => column);

  GeneratedColumn<String> get signature =>
      $composableBuilder(column: $table.signature, builder: (column) => column);

  GeneratedColumn<int> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<int> get exp =>
      $composableBuilder(column: $table.exp, builder: (column) => column);

  GeneratedColumn<int> get followers =>
      $composableBuilder(column: $table.followers, builder: (column) => column);

  GeneratedColumn<int> get following =>
      $composableBuilder(column: $table.following, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$UserProfileTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserProfileTable,
          UserProfileRow,
          $$UserProfileTableFilterComposer,
          $$UserProfileTableOrderingComposer,
          $$UserProfileTableAnnotationComposer,
          $$UserProfileTableCreateCompanionBuilder,
          $$UserProfileTableUpdateCompanionBuilder,
          (
            UserProfileRow,
            BaseReferences<_$AppDatabase, $UserProfileTable, UserProfileRow>,
          ),
          UserProfileRow,
          PrefetchHooks Function()
        > {
  $$UserProfileTableTableManager(_$AppDatabase db, $UserProfileTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserProfileTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserProfileTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserProfileTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> nickname = const Value.absent(),
                Value<String> avatar = const Value.absent(),
                Value<String> signature = const Value.absent(),
                Value<int> level = const Value.absent(),
                Value<int> exp = const Value.absent(),
                Value<int> followers = const Value.absent(),
                Value<int> following = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UserProfileCompanion(
                id: id,
                nickname: nickname,
                avatar: avatar,
                signature: signature,
                level: level,
                exp: exp,
                followers: followers,
                following: following,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> nickname = const Value.absent(),
                Value<String> avatar = const Value.absent(),
                Value<String> signature = const Value.absent(),
                Value<int> level = const Value.absent(),
                Value<int> exp = const Value.absent(),
                Value<int> followers = const Value.absent(),
                Value<int> following = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => UserProfileCompanion.insert(
                id: id,
                nickname: nickname,
                avatar: avatar,
                signature: signature,
                level: level,
                exp: exp,
                followers: followers,
                following: following,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UserProfileTable, UserProfileRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $UserProfileTable,
                    UserProfileRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserProfileTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserProfileTable,
      UserProfileRow,
      $$UserProfileTableFilterComposer,
      $$UserProfileTableOrderingComposer,
      $$UserProfileTableAnnotationComposer,
      $$UserProfileTableCreateCompanionBuilder,
      $$UserProfileTableUpdateCompanionBuilder,
      (
        UserProfileRow,
        BaseReferences<_$AppDatabase, $UserProfileTable, UserProfileRow>,
      ),
      UserProfileRow,
      PrefetchHooks Function()
    >;
typedef $$PostsTableCreateCompanionBuilder = PostsCompanion Function({
  required String id,
  Value<String> content,
  Value<String> images,
  required int createdAt,
  Value<int?> updatedAt,
  Value<String> scope,
  Value<bool> isAiGenerated,
  Value<int?> deletedAt,
  Value<String?> topicId,
  Value<String?> topicName,
  Value<bool> allowAiReply,
  Value<String?> replyDensity,
  Value<String?> likeLevel,
  Value<int?> humanLevel,
  Value<bool> isHot,
  Value<int> likeCount,
  Value<int> commentCount,
  Value<int> rowid,
});
typedef $$PostsTableUpdateCompanionBuilder = PostsCompanion Function({
  Value<String> id,
  Value<String> content,
  Value<String> images,
  Value<int> createdAt,
  Value<int?> updatedAt,
  Value<String> scope,
  Value<bool> isAiGenerated,
  Value<int?> deletedAt,
  Value<String?> topicId,
  Value<String?> topicName,
  Value<bool> allowAiReply,
  Value<String?> replyDensity,
  Value<String?> likeLevel,
  Value<int?> humanLevel,
  Value<bool> isHot,
  Value<int> likeCount,
  Value<int> commentCount,
  Value<int> rowid,
});

final class $$PostsTableReferences
    extends BaseReferences<_$AppDatabase, $PostsTable, PostRow> {
  $$PostsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AiInteractionsTable, List<AiInteractionRow>>
  _aiInteractionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.aiInteractions,
    aliasName: 'posts__id__ai_interactions__post_id',
  );

  $$AiInteractionsTableProcessedTableManager get aiInteractionsRefs {
    final manager = $$AiInteractionsTableTableManager(
      $_db,
      $_db.aiInteractions,
    ).filter((f) => f.postId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_aiInteractionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AnalysisResultsTable, List<AnalysisResultRow>>
  _analysisResultsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.analysisResults,
    aliasName: 'posts__id__analysis_results__post_id',
  );

  $$AnalysisResultsTableProcessedTableManager get analysisResultsRefs {
    final manager = $$AnalysisResultsTableTableManager(
      $_db,
      $_db.analysisResults,
    ).filter((f) => f.postId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _analysisResultsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PlanEventsTable, List<PlanEventRow>>
  _planEventsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.planEvents,
    aliasName: 'posts__id__plan_events__post_id',
  );

  $$PlanEventsTableProcessedTableManager get planEventsRefs {
    final manager = $$PlanEventsTableTableManager(
      $_db,
      $_db.planEvents,
    ).filter((f) => f.postId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_planEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PostsTableFilterComposer extends Composer<_$AppDatabase, $PostsTable> {
  $$PostsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get images => $composableBuilder(
    column: $table.images,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isAiGenerated => $composableBuilder(
    column: $table.isAiGenerated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topicId => $composableBuilder(
    column: $table.topicId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topicName => $composableBuilder(
    column: $table.topicName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allowAiReply => $composableBuilder(
    column: $table.allowAiReply,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyDensity => $composableBuilder(
    column: $table.replyDensity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get likeLevel => $composableBuilder(
    column: $table.likeLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get humanLevel => $composableBuilder(
    column: $table.humanLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isHot => $composableBuilder(
    column: $table.isHot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get likeCount => $composableBuilder(
    column: $table.likeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get commentCount => $composableBuilder(
    column: $table.commentCount,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> aiInteractionsRefs(
    Expression<bool> Function($$AiInteractionsTableFilterComposer f) f,
  ) {
    final $$AiInteractionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.aiInteractions,
      getReferencedColumn: (t) => t.postId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AiInteractionsTableFilterComposer(
            $db: $db,
            $table: $db.aiInteractions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> analysisResultsRefs(
    Expression<bool> Function($$AnalysisResultsTableFilterComposer f) f,
  ) {
    final $$AnalysisResultsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.analysisResults,
      getReferencedColumn: (t) => t.postId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AnalysisResultsTableFilterComposer(
            $db: $db,
            $table: $db.analysisResults,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> planEventsRefs(
    Expression<bool> Function($$PlanEventsTableFilterComposer f) f,
  ) {
    final $$PlanEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.planEvents,
      getReferencedColumn: (t) => t.postId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanEventsTableFilterComposer(
            $db: $db,
            $table: $db.planEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PostsTableOrderingComposer
    extends Composer<_$AppDatabase, $PostsTable> {
  $$PostsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get images => $composableBuilder(
    column: $table.images,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isAiGenerated => $composableBuilder(
    column: $table.isAiGenerated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topicId => $composableBuilder(
    column: $table.topicId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topicName => $composableBuilder(
    column: $table.topicName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allowAiReply => $composableBuilder(
    column: $table.allowAiReply,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyDensity => $composableBuilder(
    column: $table.replyDensity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get likeLevel => $composableBuilder(
    column: $table.likeLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get humanLevel => $composableBuilder(
    column: $table.humanLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isHot => $composableBuilder(
    column: $table.isHot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get likeCount => $composableBuilder(
    column: $table.likeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get commentCount => $composableBuilder(
    column: $table.commentCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PostsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PostsTable> {
  $$PostsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get images =>
      $composableBuilder(column: $table.images, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<bool> get isAiGenerated => $composableBuilder(
    column: $table.isAiGenerated,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get topicId =>
      $composableBuilder(column: $table.topicId, builder: (column) => column);

  GeneratedColumn<String> get topicName =>
      $composableBuilder(column: $table.topicName, builder: (column) => column);

  GeneratedColumn<bool> get allowAiReply => $composableBuilder(
    column: $table.allowAiReply,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replyDensity => $composableBuilder(
    column: $table.replyDensity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get likeLevel =>
      $composableBuilder(column: $table.likeLevel, builder: (column) => column);

  GeneratedColumn<int> get humanLevel => $composableBuilder(
    column: $table.humanLevel,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isHot =>
      $composableBuilder(column: $table.isHot, builder: (column) => column);

  GeneratedColumn<int> get likeCount =>
      $composableBuilder(column: $table.likeCount, builder: (column) => column);

  GeneratedColumn<int> get commentCount => $composableBuilder(
    column: $table.commentCount,
    builder: (column) => column,
  );

  Expression<T> aiInteractionsRefs<T extends Object>(
    Expression<T> Function($$AiInteractionsTableAnnotationComposer a) f,
  ) {
    final $$AiInteractionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.aiInteractions,
      getReferencedColumn: (t) => t.postId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AiInteractionsTableAnnotationComposer(
            $db: $db,
            $table: $db.aiInteractions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> analysisResultsRefs<T extends Object>(
    Expression<T> Function($$AnalysisResultsTableAnnotationComposer a) f,
  ) {
    final $$AnalysisResultsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.analysisResults,
      getReferencedColumn: (t) => t.postId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AnalysisResultsTableAnnotationComposer(
            $db: $db,
            $table: $db.analysisResults,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> planEventsRefs<T extends Object>(
    Expression<T> Function($$PlanEventsTableAnnotationComposer a) f,
  ) {
    final $$PlanEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.planEvents,
      getReferencedColumn: (t) => t.postId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.planEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PostsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PostsTable,
          PostRow,
          $$PostsTableFilterComposer,
          $$PostsTableOrderingComposer,
          $$PostsTableAnnotationComposer,
          $$PostsTableCreateCompanionBuilder,
          $$PostsTableUpdateCompanionBuilder,
          (PostRow, $$PostsTableReferences),
          PostRow,
          PrefetchHooks Function({
            bool aiInteractionsRefs,
            bool analysisResultsRefs,
            bool planEventsRefs,
          })
        > {
  $$PostsTableTableManager(_$AppDatabase db, $PostsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PostsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PostsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PostsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> images = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> updatedAt = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<bool> isAiGenerated = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String?> topicId = const Value.absent(),
                Value<String?> topicName = const Value.absent(),
                Value<bool> allowAiReply = const Value.absent(),
                Value<String?> replyDensity = const Value.absent(),
                Value<String?> likeLevel = const Value.absent(),
                Value<int?> humanLevel = const Value.absent(),
                Value<bool> isHot = const Value.absent(),
                Value<int> likeCount = const Value.absent(),
                Value<int> commentCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PostsCompanion(
                id: id,
                content: content,
                images: images,
                createdAt: createdAt,
                updatedAt: updatedAt,
                scope: scope,
                isAiGenerated: isAiGenerated,
                deletedAt: deletedAt,
                topicId: topicId,
                topicName: topicName,
                allowAiReply: allowAiReply,
                replyDensity: replyDensity,
                likeLevel: likeLevel,
                humanLevel: humanLevel,
                isHot: isHot,
                likeCount: likeCount,
                commentCount: commentCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> content = const Value.absent(),
                Value<String> images = const Value.absent(),
                required int createdAt,
                Value<int?> updatedAt = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<bool> isAiGenerated = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String?> topicId = const Value.absent(),
                Value<String?> topicName = const Value.absent(),
                Value<bool> allowAiReply = const Value.absent(),
                Value<String?> replyDensity = const Value.absent(),
                Value<String?> likeLevel = const Value.absent(),
                Value<int?> humanLevel = const Value.absent(),
                Value<bool> isHot = const Value.absent(),
                Value<int> likeCount = const Value.absent(),
                Value<int> commentCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PostsCompanion.insert(
                id: id,
                content: content,
                images: images,
                createdAt: createdAt,
                updatedAt: updatedAt,
                scope: scope,
                isAiGenerated: isAiGenerated,
                deletedAt: deletedAt,
                topicId: topicId,
                topicName: topicName,
                allowAiReply: allowAiReply,
                replyDensity: replyDensity,
                likeLevel: likeLevel,
                humanLevel: humanLevel,
                isHot: isHot,
                likeCount: likeCount,
                commentCount: commentCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PostsTable, PostRow>(table),
                  $$PostsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                aiInteractionsRefs = false,
                analysisResultsRefs = false,
                planEventsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (aiInteractionsRefs) db.aiInteractions,
                    if (analysisResultsRefs) db.analysisResults,
                    if (planEventsRefs) db.planEvents,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (aiInteractionsRefs)
                        await $_getPrefetchedData<
                          PostRow,
                          $PostsTable,
                          AiInteractionRow
                        >(
                          currentTable: table,
                          referencedTable: $$PostsTableReferences
                              ._aiInteractionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PostsTableReferences(
                                db,
                                table,
                                p0,
                              ).aiInteractionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.postId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (analysisResultsRefs)
                        await $_getPrefetchedData<
                          PostRow,
                          $PostsTable,
                          AnalysisResultRow
                        >(
                          currentTable: table,
                          referencedTable: $$PostsTableReferences
                              ._analysisResultsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PostsTableReferences(
                                db,
                                table,
                                p0,
                              ).analysisResultsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.postId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (planEventsRefs)
                        await $_getPrefetchedData<
                          PostRow,
                          $PostsTable,
                          PlanEventRow
                        >(
                          currentTable: table,
                          referencedTable: $$PostsTableReferences
                              ._planEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PostsTableReferences(
                                db,
                                table,
                                p0,
                              ).planEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.postId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$PostsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PostsTable,
      PostRow,
      $$PostsTableFilterComposer,
      $$PostsTableOrderingComposer,
      $$PostsTableAnnotationComposer,
      $$PostsTableCreateCompanionBuilder,
      $$PostsTableUpdateCompanionBuilder,
      (PostRow, $$PostsTableReferences),
      PostRow,
      PrefetchHooks Function({
        bool aiInteractionsRefs,
        bool analysisResultsRefs,
        bool planEventsRefs,
      })
    >;
typedef $$AiPersonasTableCreateCompanionBuilder = AiPersonasCompanion Function({
  required String id,
  required String name,
  Value<String> avatar,
  Value<String> bio,
  Value<String> languageStyle,
  Value<String> tone,
  Value<String> activeHours,
  Value<double> likeProbability,
  Value<double> commentProbability,
  Value<String> replyLength,
  Value<String> voiceModel,
  Value<bool> isActive,
  Value<String> scope,
  Value<int> level,
  Value<String> badges,
  Value<int> followers,
  Value<int> following,
  Value<String> personalityType,
  Value<bool> memoryEnabled,
  Value<int> relationshipLevel,
  Value<int?> deletedAt,
  Value<int> rowid,
});
typedef $$AiPersonasTableUpdateCompanionBuilder = AiPersonasCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> avatar,
  Value<String> bio,
  Value<String> languageStyle,
  Value<String> tone,
  Value<String> activeHours,
  Value<double> likeProbability,
  Value<double> commentProbability,
  Value<String> replyLength,
  Value<String> voiceModel,
  Value<bool> isActive,
  Value<String> scope,
  Value<int> level,
  Value<String> badges,
  Value<int> followers,
  Value<int> following,
  Value<String> personalityType,
  Value<bool> memoryEnabled,
  Value<int> relationshipLevel,
  Value<int?> deletedAt,
  Value<int> rowid,
});

final class $$AiPersonasTableReferences
    extends BaseReferences<_$AppDatabase, $AiPersonasTable, AiPersonaRow> {
  $$AiPersonasTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AiInteractionsTable, List<AiInteractionRow>>
  _aiInteractionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.aiInteractions,
    aliasName: 'ai_personas__id__ai_interactions__persona_id',
  );

  $$AiInteractionsTableProcessedTableManager get aiInteractionsRefs {
    final manager = $$AiInteractionsTableTableManager(
      $_db,
      $_db.aiInteractions,
    ).filter((f) => f.personaId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_aiInteractionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AiPersonasTableFilterComposer
    extends Composer<_$AppDatabase, $AiPersonasTable> {
  $$AiPersonasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bio => $composableBuilder(
    column: $table.bio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get languageStyle => $composableBuilder(
    column: $table.languageStyle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tone => $composableBuilder(
    column: $table.tone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activeHours => $composableBuilder(
    column: $table.activeHours,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get likeProbability => $composableBuilder(
    column: $table.likeProbability,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get commentProbability => $composableBuilder(
    column: $table.commentProbability,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyLength => $composableBuilder(
    column: $table.replyLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voiceModel => $composableBuilder(
    column: $table.voiceModel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get badges => $composableBuilder(
    column: $table.badges,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get followers => $composableBuilder(
    column: $table.followers,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get following => $composableBuilder(
    column: $table.following,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get personalityType => $composableBuilder(
    column: $table.personalityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get memoryEnabled => $composableBuilder(
    column: $table.memoryEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get relationshipLevel => $composableBuilder(
    column: $table.relationshipLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> aiInteractionsRefs(
    Expression<bool> Function($$AiInteractionsTableFilterComposer f) f,
  ) {
    final $$AiInteractionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.aiInteractions,
      getReferencedColumn: (t) => t.personaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AiInteractionsTableFilterComposer(
            $db: $db,
            $table: $db.aiInteractions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AiPersonasTableOrderingComposer
    extends Composer<_$AppDatabase, $AiPersonasTable> {
  $$AiPersonasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bio => $composableBuilder(
    column: $table.bio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get languageStyle => $composableBuilder(
    column: $table.languageStyle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tone => $composableBuilder(
    column: $table.tone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activeHours => $composableBuilder(
    column: $table.activeHours,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get likeProbability => $composableBuilder(
    column: $table.likeProbability,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get commentProbability => $composableBuilder(
    column: $table.commentProbability,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyLength => $composableBuilder(
    column: $table.replyLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voiceModel => $composableBuilder(
    column: $table.voiceModel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get badges => $composableBuilder(
    column: $table.badges,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get followers => $composableBuilder(
    column: $table.followers,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get following => $composableBuilder(
    column: $table.following,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get personalityType => $composableBuilder(
    column: $table.personalityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get memoryEnabled => $composableBuilder(
    column: $table.memoryEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get relationshipLevel => $composableBuilder(
    column: $table.relationshipLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiPersonasTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiPersonasTable> {
  $$AiPersonasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get avatar =>
      $composableBuilder(column: $table.avatar, builder: (column) => column);

  GeneratedColumn<String> get bio =>
      $composableBuilder(column: $table.bio, builder: (column) => column);

  GeneratedColumn<String> get languageStyle => $composableBuilder(
    column: $table.languageStyle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tone =>
      $composableBuilder(column: $table.tone, builder: (column) => column);

  GeneratedColumn<String> get activeHours => $composableBuilder(
    column: $table.activeHours,
    builder: (column) => column,
  );

  GeneratedColumn<double> get likeProbability => $composableBuilder(
    column: $table.likeProbability,
    builder: (column) => column,
  );

  GeneratedColumn<double> get commentProbability => $composableBuilder(
    column: $table.commentProbability,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replyLength => $composableBuilder(
    column: $table.replyLength,
    builder: (column) => column,
  );

  GeneratedColumn<String> get voiceModel => $composableBuilder(
    column: $table.voiceModel,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<int> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<String> get badges =>
      $composableBuilder(column: $table.badges, builder: (column) => column);

  GeneratedColumn<int> get followers =>
      $composableBuilder(column: $table.followers, builder: (column) => column);

  GeneratedColumn<int> get following =>
      $composableBuilder(column: $table.following, builder: (column) => column);

  GeneratedColumn<String> get personalityType => $composableBuilder(
    column: $table.personalityType,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get memoryEnabled => $composableBuilder(
    column: $table.memoryEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get relationshipLevel => $composableBuilder(
    column: $table.relationshipLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> aiInteractionsRefs<T extends Object>(
    Expression<T> Function($$AiInteractionsTableAnnotationComposer a) f,
  ) {
    final $$AiInteractionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.aiInteractions,
      getReferencedColumn: (t) => t.personaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AiInteractionsTableAnnotationComposer(
            $db: $db,
            $table: $db.aiInteractions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AiPersonasTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiPersonasTable,
          AiPersonaRow,
          $$AiPersonasTableFilterComposer,
          $$AiPersonasTableOrderingComposer,
          $$AiPersonasTableAnnotationComposer,
          $$AiPersonasTableCreateCompanionBuilder,
          $$AiPersonasTableUpdateCompanionBuilder,
          (AiPersonaRow, $$AiPersonasTableReferences),
          AiPersonaRow,
          PrefetchHooks Function({bool aiInteractionsRefs})
        > {
  $$AiPersonasTableTableManager(_$AppDatabase db, $AiPersonasTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiPersonasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiPersonasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiPersonasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> avatar = const Value.absent(),
                Value<String> bio = const Value.absent(),
                Value<String> languageStyle = const Value.absent(),
                Value<String> tone = const Value.absent(),
                Value<String> activeHours = const Value.absent(),
                Value<double> likeProbability = const Value.absent(),
                Value<double> commentProbability = const Value.absent(),
                Value<String> replyLength = const Value.absent(),
                Value<String> voiceModel = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> level = const Value.absent(),
                Value<String> badges = const Value.absent(),
                Value<int> followers = const Value.absent(),
                Value<int> following = const Value.absent(),
                Value<String> personalityType = const Value.absent(),
                Value<bool> memoryEnabled = const Value.absent(),
                Value<int> relationshipLevel = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiPersonasCompanion(
                id: id,
                name: name,
                avatar: avatar,
                bio: bio,
                languageStyle: languageStyle,
                tone: tone,
                activeHours: activeHours,
                likeProbability: likeProbability,
                commentProbability: commentProbability,
                replyLength: replyLength,
                voiceModel: voiceModel,
                isActive: isActive,
                scope: scope,
                level: level,
                badges: badges,
                followers: followers,
                following: following,
                personalityType: personalityType,
                memoryEnabled: memoryEnabled,
                relationshipLevel: relationshipLevel,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> avatar = const Value.absent(),
                Value<String> bio = const Value.absent(),
                Value<String> languageStyle = const Value.absent(),
                Value<String> tone = const Value.absent(),
                Value<String> activeHours = const Value.absent(),
                Value<double> likeProbability = const Value.absent(),
                Value<double> commentProbability = const Value.absent(),
                Value<String> replyLength = const Value.absent(),
                Value<String> voiceModel = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> level = const Value.absent(),
                Value<String> badges = const Value.absent(),
                Value<int> followers = const Value.absent(),
                Value<int> following = const Value.absent(),
                Value<String> personalityType = const Value.absent(),
                Value<bool> memoryEnabled = const Value.absent(),
                Value<int> relationshipLevel = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiPersonasCompanion.insert(
                id: id,
                name: name,
                avatar: avatar,
                bio: bio,
                languageStyle: languageStyle,
                tone: tone,
                activeHours: activeHours,
                likeProbability: likeProbability,
                commentProbability: commentProbability,
                replyLength: replyLength,
                voiceModel: voiceModel,
                isActive: isActive,
                scope: scope,
                level: level,
                badges: badges,
                followers: followers,
                following: following,
                personalityType: personalityType,
                memoryEnabled: memoryEnabled,
                relationshipLevel: relationshipLevel,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AiPersonasTable, AiPersonaRow>(table),
                  $$AiPersonasTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({aiInteractionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (aiInteractionsRefs) db.aiInteractions,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (aiInteractionsRefs)
                    await $_getPrefetchedData<
                      AiPersonaRow,
                      $AiPersonasTable,
                      AiInteractionRow
                    >(
                      currentTable: table,
                      referencedTable: $$AiPersonasTableReferences
                          ._aiInteractionsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$AiPersonasTableReferences(
                            db,
                            table,
                            p0,
                          ).aiInteractionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.personaId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$AiPersonasTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiPersonasTable,
      AiPersonaRow,
      $$AiPersonasTableFilterComposer,
      $$AiPersonasTableOrderingComposer,
      $$AiPersonasTableAnnotationComposer,
      $$AiPersonasTableCreateCompanionBuilder,
      $$AiPersonasTableUpdateCompanionBuilder,
      (AiPersonaRow, $$AiPersonasTableReferences),
      AiPersonaRow,
      PrefetchHooks Function({bool aiInteractionsRefs})
    >;
typedef $$AiInteractionsTableCreateCompanionBuilder =
    AiInteractionsCompanion Function({
      required String id,
      required String postId,
      required String personaId,
      required String type,
      Value<String?> mediaType,
      Value<String?> content,
      Value<String?> voicePath,
      Value<String?> transcript,
      Value<int?> voiceDurationMs,
      required int scheduledAt,
      Value<int?> executedAt,
      Value<String> status,
      Value<bool> isAi,
      Value<String> scope,
      Value<String?> parentId,
      Value<int> likeCount,
      Value<int?> deletedAt,
      Value<int> rowid,
    });
typedef $$AiInteractionsTableUpdateCompanionBuilder =
    AiInteractionsCompanion Function({
      Value<String> id,
      Value<String> postId,
      Value<String> personaId,
      Value<String> type,
      Value<String?> mediaType,
      Value<String?> content,
      Value<String?> voicePath,
      Value<String?> transcript,
      Value<int?> voiceDurationMs,
      Value<int> scheduledAt,
      Value<int?> executedAt,
      Value<String> status,
      Value<bool> isAi,
      Value<String> scope,
      Value<String?> parentId,
      Value<int> likeCount,
      Value<int?> deletedAt,
      Value<int> rowid,
    });

final class $$AiInteractionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $AiInteractionsTable, AiInteractionRow> {
  $$AiInteractionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PostsTable _postIdTable(_$AppDatabase db) =>
      db.posts.createAlias('ai_interactions__post_id__posts__id');

  $$PostsTableProcessedTableManager get postId {
    final $_column = $_itemColumn<String>('post_id')!;

    final manager = $$PostsTableTableManager(
      $_db,
      $_db.posts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_postIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AiPersonasTable _personaIdTable(_$AppDatabase db) =>
      db.aiPersonas.createAlias('ai_interactions__persona_id__ai_personas__id');

  $$AiPersonasTableProcessedTableManager get personaId {
    final $_column = $_itemColumn<String>('persona_id')!;

    final manager = $$AiPersonasTableTableManager(
      $_db,
      $_db.aiPersonas,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personaIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AiInteractionsTableFilterComposer
    extends Composer<_$AppDatabase, $AiInteractionsTable> {
  $$AiInteractionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voicePath => $composableBuilder(
    column: $table.voicePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transcript => $composableBuilder(
    column: $table.transcript,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get voiceDurationMs => $composableBuilder(
    column: $table.voiceDurationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get executedAt => $composableBuilder(
    column: $table.executedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isAi => $composableBuilder(
    column: $table.isAi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get likeCount => $composableBuilder(
    column: $table.likeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PostsTableFilterComposer get postId {
    final $$PostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.postId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableFilterComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AiPersonasTableFilterComposer get personaId {
    final $$AiPersonasTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personaId,
      referencedTable: $db.aiPersonas,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AiPersonasTableFilterComposer(
            $db: $db,
            $table: $db.aiPersonas,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AiInteractionsTableOrderingComposer
    extends Composer<_$AppDatabase, $AiInteractionsTable> {
  $$AiInteractionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voicePath => $composableBuilder(
    column: $table.voicePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transcript => $composableBuilder(
    column: $table.transcript,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get voiceDurationMs => $composableBuilder(
    column: $table.voiceDurationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get executedAt => $composableBuilder(
    column: $table.executedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isAi => $composableBuilder(
    column: $table.isAi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get likeCount => $composableBuilder(
    column: $table.likeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PostsTableOrderingComposer get postId {
    final $$PostsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.postId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableOrderingComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AiPersonasTableOrderingComposer get personaId {
    final $$AiPersonasTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personaId,
      referencedTable: $db.aiPersonas,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AiPersonasTableOrderingComposer(
            $db: $db,
            $table: $db.aiPersonas,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AiInteractionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiInteractionsTable> {
  $$AiInteractionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get voicePath =>
      $composableBuilder(column: $table.voicePath, builder: (column) => column);

  GeneratedColumn<String> get transcript => $composableBuilder(
    column: $table.transcript,
    builder: (column) => column,
  );

  GeneratedColumn<int> get voiceDurationMs => $composableBuilder(
    column: $table.voiceDurationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get executedAt => $composableBuilder(
    column: $table.executedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get isAi =>
      $composableBuilder(column: $table.isAi, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<int> get likeCount =>
      $composableBuilder(column: $table.likeCount, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$PostsTableAnnotationComposer get postId {
    final $$PostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.postId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableAnnotationComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AiPersonasTableAnnotationComposer get personaId {
    final $$AiPersonasTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personaId,
      referencedTable: $db.aiPersonas,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AiPersonasTableAnnotationComposer(
            $db: $db,
            $table: $db.aiPersonas,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AiInteractionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiInteractionsTable,
          AiInteractionRow,
          $$AiInteractionsTableFilterComposer,
          $$AiInteractionsTableOrderingComposer,
          $$AiInteractionsTableAnnotationComposer,
          $$AiInteractionsTableCreateCompanionBuilder,
          $$AiInteractionsTableUpdateCompanionBuilder,
          (AiInteractionRow, $$AiInteractionsTableReferences),
          AiInteractionRow,
          PrefetchHooks Function({bool postId, bool personaId})
        > {
  $$AiInteractionsTableTableManager(
    _$AppDatabase db,
    $AiInteractionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiInteractionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiInteractionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiInteractionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> postId = const Value.absent(),
                Value<String> personaId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> mediaType = const Value.absent(),
                Value<String?> content = const Value.absent(),
                Value<String?> voicePath = const Value.absent(),
                Value<String?> transcript = const Value.absent(),
                Value<int?> voiceDurationMs = const Value.absent(),
                Value<int> scheduledAt = const Value.absent(),
                Value<int?> executedAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> isAi = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<int> likeCount = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiInteractionsCompanion(
                id: id,
                postId: postId,
                personaId: personaId,
                type: type,
                mediaType: mediaType,
                content: content,
                voicePath: voicePath,
                transcript: transcript,
                voiceDurationMs: voiceDurationMs,
                scheduledAt: scheduledAt,
                executedAt: executedAt,
                status: status,
                isAi: isAi,
                scope: scope,
                parentId: parentId,
                likeCount: likeCount,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String postId,
                required String personaId,
                required String type,
                Value<String?> mediaType = const Value.absent(),
                Value<String?> content = const Value.absent(),
                Value<String?> voicePath = const Value.absent(),
                Value<String?> transcript = const Value.absent(),
                Value<int?> voiceDurationMs = const Value.absent(),
                required int scheduledAt,
                Value<int?> executedAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> isAi = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<int> likeCount = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiInteractionsCompanion.insert(
                id: id,
                postId: postId,
                personaId: personaId,
                type: type,
                mediaType: mediaType,
                content: content,
                voicePath: voicePath,
                transcript: transcript,
                voiceDurationMs: voiceDurationMs,
                scheduledAt: scheduledAt,
                executedAt: executedAt,
                status: status,
                isAi: isAi,
                scope: scope,
                parentId: parentId,
                likeCount: likeCount,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AiInteractionsTable, AiInteractionRow>(table),
                  $$AiInteractionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({postId = false, personaId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (postId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.postId,
                        referencedTable: $$AiInteractionsTableReferences
                            ._postIdTable(db),
                        referencedColumn: $$AiInteractionsTableReferences
                            ._postIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (personaId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.personaId,
                        referencedTable: $$AiInteractionsTableReferences
                            ._personaIdTable(db),
                        referencedColumn: $$AiInteractionsTableReferences
                            ._personaIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AiInteractionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiInteractionsTable,
      AiInteractionRow,
      $$AiInteractionsTableFilterComposer,
      $$AiInteractionsTableOrderingComposer,
      $$AiInteractionsTableAnnotationComposer,
      $$AiInteractionsTableCreateCompanionBuilder,
      $$AiInteractionsTableUpdateCompanionBuilder,
      (AiInteractionRow, $$AiInteractionsTableReferences),
      AiInteractionRow,
      PrefetchHooks Function({bool postId, bool personaId})
    >;
typedef $$AnalysisResultsTableCreateCompanionBuilder =
    AnalysisResultsCompanion Function({
      required String id,
      required String postId,
      Value<String?> imageDescription,
      Value<String?> emotionAnalysis,
      Value<String?> logicAnalysis,
      Value<String?> factCheck,
      Value<String?> suggestions,
      required int createdAt,
      Value<String> scope,
      Value<int> rowid,
    });
typedef $$AnalysisResultsTableUpdateCompanionBuilder =
    AnalysisResultsCompanion Function({
      Value<String> id,
      Value<String> postId,
      Value<String?> imageDescription,
      Value<String?> emotionAnalysis,
      Value<String?> logicAnalysis,
      Value<String?> factCheck,
      Value<String?> suggestions,
      Value<int> createdAt,
      Value<String> scope,
      Value<int> rowid,
    });

final class $$AnalysisResultsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $AnalysisResultsTable,
          AnalysisResultRow
        > {
  $$AnalysisResultsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PostsTable _postIdTable(_$AppDatabase db) =>
      db.posts.createAlias('analysis_results__post_id__posts__id');

  $$PostsTableProcessedTableManager get postId {
    final $_column = $_itemColumn<String>('post_id')!;

    final manager = $$PostsTableTableManager(
      $_db,
      $_db.posts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_postIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AnalysisResultsTableFilterComposer
    extends Composer<_$AppDatabase, $AnalysisResultsTable> {
  $$AnalysisResultsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageDescription => $composableBuilder(
    column: $table.imageDescription,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get emotionAnalysis => $composableBuilder(
    column: $table.emotionAnalysis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get logicAnalysis => $composableBuilder(
    column: $table.logicAnalysis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get factCheck => $composableBuilder(
    column: $table.factCheck,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get suggestions => $composableBuilder(
    column: $table.suggestions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  $$PostsTableFilterComposer get postId {
    final $$PostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.postId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableFilterComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnalysisResultsTableOrderingComposer
    extends Composer<_$AppDatabase, $AnalysisResultsTable> {
  $$AnalysisResultsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageDescription => $composableBuilder(
    column: $table.imageDescription,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emotionAnalysis => $composableBuilder(
    column: $table.emotionAnalysis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get logicAnalysis => $composableBuilder(
    column: $table.logicAnalysis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get factCheck => $composableBuilder(
    column: $table.factCheck,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get suggestions => $composableBuilder(
    column: $table.suggestions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  $$PostsTableOrderingComposer get postId {
    final $$PostsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.postId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableOrderingComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnalysisResultsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AnalysisResultsTable> {
  $$AnalysisResultsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get imageDescription => $composableBuilder(
    column: $table.imageDescription,
    builder: (column) => column,
  );

  GeneratedColumn<String> get emotionAnalysis => $composableBuilder(
    column: $table.emotionAnalysis,
    builder: (column) => column,
  );

  GeneratedColumn<String> get logicAnalysis => $composableBuilder(
    column: $table.logicAnalysis,
    builder: (column) => column,
  );

  GeneratedColumn<String> get factCheck =>
      $composableBuilder(column: $table.factCheck, builder: (column) => column);

  GeneratedColumn<String> get suggestions => $composableBuilder(
    column: $table.suggestions,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  $$PostsTableAnnotationComposer get postId {
    final $$PostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.postId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableAnnotationComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnalysisResultsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AnalysisResultsTable,
          AnalysisResultRow,
          $$AnalysisResultsTableFilterComposer,
          $$AnalysisResultsTableOrderingComposer,
          $$AnalysisResultsTableAnnotationComposer,
          $$AnalysisResultsTableCreateCompanionBuilder,
          $$AnalysisResultsTableUpdateCompanionBuilder,
          (AnalysisResultRow, $$AnalysisResultsTableReferences),
          AnalysisResultRow,
          PrefetchHooks Function({bool postId})
        > {
  $$AnalysisResultsTableTableManager(
    _$AppDatabase db,
    $AnalysisResultsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnalysisResultsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnalysisResultsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnalysisResultsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> postId = const Value.absent(),
                Value<String?> imageDescription = const Value.absent(),
                Value<String?> emotionAnalysis = const Value.absent(),
                Value<String?> logicAnalysis = const Value.absent(),
                Value<String?> factCheck = const Value.absent(),
                Value<String?> suggestions = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AnalysisResultsCompanion(
                id: id,
                postId: postId,
                imageDescription: imageDescription,
                emotionAnalysis: emotionAnalysis,
                logicAnalysis: logicAnalysis,
                factCheck: factCheck,
                suggestions: suggestions,
                createdAt: createdAt,
                scope: scope,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String postId,
                Value<String?> imageDescription = const Value.absent(),
                Value<String?> emotionAnalysis = const Value.absent(),
                Value<String?> logicAnalysis = const Value.absent(),
                Value<String?> factCheck = const Value.absent(),
                Value<String?> suggestions = const Value.absent(),
                required int createdAt,
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AnalysisResultsCompanion.insert(
                id: id,
                postId: postId,
                imageDescription: imageDescription,
                emotionAnalysis: emotionAnalysis,
                logicAnalysis: logicAnalysis,
                factCheck: factCheck,
                suggestions: suggestions,
                createdAt: createdAt,
                scope: scope,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AnalysisResultsTable, AnalysisResultRow>(table),
                  $$AnalysisResultsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({postId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (postId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.postId,
                        referencedTable: $$AnalysisResultsTableReferences
                            ._postIdTable(db),
                        referencedColumn: $$AnalysisResultsTableReferences
                            ._postIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AnalysisResultsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AnalysisResultsTable,
      AnalysisResultRow,
      $$AnalysisResultsTableFilterComposer,
      $$AnalysisResultsTableOrderingComposer,
      $$AnalysisResultsTableAnnotationComposer,
      $$AnalysisResultsTableCreateCompanionBuilder,
      $$AnalysisResultsTableUpdateCompanionBuilder,
      (AnalysisResultRow, $$AnalysisResultsTableReferences),
      AnalysisResultRow,
      PrefetchHooks Function({bool postId})
    >;
typedef $$ModeSwitchLogsTableCreateCompanionBuilder =
    ModeSwitchLogsCompanion Function({
      required String id,
      required String fromMode,
      required String toMode,
      required int switchedAt,
      Value<String> archiveAction,
      Value<int> rowid,
    });
typedef $$ModeSwitchLogsTableUpdateCompanionBuilder =
    ModeSwitchLogsCompanion Function({
      Value<String> id,
      Value<String> fromMode,
      Value<String> toMode,
      Value<int> switchedAt,
      Value<String> archiveAction,
      Value<int> rowid,
    });

class $$ModeSwitchLogsTableFilterComposer
    extends Composer<_$AppDatabase, $ModeSwitchLogsTable> {
  $$ModeSwitchLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromMode => $composableBuilder(
    column: $table.fromMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toMode => $composableBuilder(
    column: $table.toMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get switchedAt => $composableBuilder(
    column: $table.switchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get archiveAction => $composableBuilder(
    column: $table.archiveAction,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ModeSwitchLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $ModeSwitchLogsTable> {
  $$ModeSwitchLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromMode => $composableBuilder(
    column: $table.fromMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toMode => $composableBuilder(
    column: $table.toMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get switchedAt => $composableBuilder(
    column: $table.switchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get archiveAction => $composableBuilder(
    column: $table.archiveAction,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ModeSwitchLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ModeSwitchLogsTable> {
  $$ModeSwitchLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fromMode =>
      $composableBuilder(column: $table.fromMode, builder: (column) => column);

  GeneratedColumn<String> get toMode =>
      $composableBuilder(column: $table.toMode, builder: (column) => column);

  GeneratedColumn<int> get switchedAt => $composableBuilder(
    column: $table.switchedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get archiveAction => $composableBuilder(
    column: $table.archiveAction,
    builder: (column) => column,
  );
}

class $$ModeSwitchLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ModeSwitchLogsTable,
          ModeSwitchLogRow,
          $$ModeSwitchLogsTableFilterComposer,
          $$ModeSwitchLogsTableOrderingComposer,
          $$ModeSwitchLogsTableAnnotationComposer,
          $$ModeSwitchLogsTableCreateCompanionBuilder,
          $$ModeSwitchLogsTableUpdateCompanionBuilder,
          (
            ModeSwitchLogRow,
            BaseReferences<
              _$AppDatabase,
              $ModeSwitchLogsTable,
              ModeSwitchLogRow
            >,
          ),
          ModeSwitchLogRow,
          PrefetchHooks Function()
        > {
  $$ModeSwitchLogsTableTableManager(
    _$AppDatabase db,
    $ModeSwitchLogsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ModeSwitchLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ModeSwitchLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ModeSwitchLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> fromMode = const Value.absent(),
                Value<String> toMode = const Value.absent(),
                Value<int> switchedAt = const Value.absent(),
                Value<String> archiveAction = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModeSwitchLogsCompanion(
                id: id,
                fromMode: fromMode,
                toMode: toMode,
                switchedAt: switchedAt,
                archiveAction: archiveAction,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String fromMode,
                required String toMode,
                required int switchedAt,
                Value<String> archiveAction = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModeSwitchLogsCompanion.insert(
                id: id,
                fromMode: fromMode,
                toMode: toMode,
                switchedAt: switchedAt,
                archiveAction: archiveAction,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ModeSwitchLogsTable, ModeSwitchLogRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ModeSwitchLogsTable,
                    ModeSwitchLogRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ModeSwitchLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ModeSwitchLogsTable,
      ModeSwitchLogRow,
      $$ModeSwitchLogsTableFilterComposer,
      $$ModeSwitchLogsTableOrderingComposer,
      $$ModeSwitchLogsTableAnnotationComposer,
      $$ModeSwitchLogsTableCreateCompanionBuilder,
      $$ModeSwitchLogsTableUpdateCompanionBuilder,
      (
        ModeSwitchLogRow,
        BaseReferences<_$AppDatabase, $ModeSwitchLogsTable, ModeSwitchLogRow>,
      ),
      ModeSwitchLogRow,
      PrefetchHooks Function()
    >;
typedef $$NotificationLogsTableCreateCompanionBuilder =
    NotificationLogsCompanion Function({
      required String id,
      required String type,
      required String title,
      Value<String> body,
      Value<String?> postId,
      Value<int?> scheduledAt,
      Value<int?> deliveredAt,
      Value<bool> isRead,
      Value<String> scope,
      Value<int> rowid,
    });
typedef $$NotificationLogsTableUpdateCompanionBuilder =
    NotificationLogsCompanion Function({
      Value<String> id,
      Value<String> type,
      Value<String> title,
      Value<String> body,
      Value<String?> postId,
      Value<int?> scheduledAt,
      Value<int?> deliveredAt,
      Value<bool> isRead,
      Value<String> scope,
      Value<int> rowid,
    });

class $$NotificationLogsTableFilterComposer
    extends Composer<_$AppDatabase, $NotificationLogsTable> {
  $$NotificationLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get postId => $composableBuilder(
    column: $table.postId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotificationLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $NotificationLogsTable> {
  $$NotificationLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get postId => $composableBuilder(
    column: $table.postId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotificationLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotificationLogsTable> {
  $$NotificationLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get postId =>
      $composableBuilder(column: $table.postId, builder: (column) => column);

  GeneratedColumn<int> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);
}

class $$NotificationLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotificationLogsTable,
          NotificationLogRow,
          $$NotificationLogsTableFilterComposer,
          $$NotificationLogsTableOrderingComposer,
          $$NotificationLogsTableAnnotationComposer,
          $$NotificationLogsTableCreateCompanionBuilder,
          $$NotificationLogsTableUpdateCompanionBuilder,
          (
            NotificationLogRow,
            BaseReferences<
              _$AppDatabase,
              $NotificationLogsTable,
              NotificationLogRow
            >,
          ),
          NotificationLogRow,
          PrefetchHooks Function()
        > {
  $$NotificationLogsTableTableManager(
    _$AppDatabase db,
    $NotificationLogsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotificationLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotificationLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotificationLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> postId = const Value.absent(),
                Value<int?> scheduledAt = const Value.absent(),
                Value<int?> deliveredAt = const Value.absent(),
                Value<bool> isRead = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotificationLogsCompanion(
                id: id,
                type: type,
                title: title,
                body: body,
                postId: postId,
                scheduledAt: scheduledAt,
                deliveredAt: deliveredAt,
                isRead: isRead,
                scope: scope,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String type,
                required String title,
                Value<String> body = const Value.absent(),
                Value<String?> postId = const Value.absent(),
                Value<int?> scheduledAt = const Value.absent(),
                Value<int?> deliveredAt = const Value.absent(),
                Value<bool> isRead = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotificationLogsCompanion.insert(
                id: id,
                type: type,
                title: title,
                body: body,
                postId: postId,
                scheduledAt: scheduledAt,
                deliveredAt: deliveredAt,
                isRead: isRead,
                scope: scope,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NotificationLogsTable, NotificationLogRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $NotificationLogsTable,
                    NotificationLogRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotificationLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotificationLogsTable,
      NotificationLogRow,
      $$NotificationLogsTableFilterComposer,
      $$NotificationLogsTableOrderingComposer,
      $$NotificationLogsTableAnnotationComposer,
      $$NotificationLogsTableCreateCompanionBuilder,
      $$NotificationLogsTableUpdateCompanionBuilder,
      (
        NotificationLogRow,
        BaseReferences<
          _$AppDatabase,
          $NotificationLogsTable,
          NotificationLogRow
        >,
      ),
      NotificationLogRow,
      PrefetchHooks Function()
    >;
typedef $$FeedbackViewLogsTableCreateCompanionBuilder =
    FeedbackViewLogsCompanion Function({
      required String id,
      Value<String?> postId,
      required int viewedAt,
      Value<int> durationMs,
      Value<String> scope,
      Value<int> rowid,
    });
typedef $$FeedbackViewLogsTableUpdateCompanionBuilder =
    FeedbackViewLogsCompanion Function({
      Value<String> id,
      Value<String?> postId,
      Value<int> viewedAt,
      Value<int> durationMs,
      Value<String> scope,
      Value<int> rowid,
    });

class $$FeedbackViewLogsTableFilterComposer
    extends Composer<_$AppDatabase, $FeedbackViewLogsTable> {
  $$FeedbackViewLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get postId => $composableBuilder(
    column: $table.postId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get viewedAt => $composableBuilder(
    column: $table.viewedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FeedbackViewLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $FeedbackViewLogsTable> {
  $$FeedbackViewLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get postId => $composableBuilder(
    column: $table.postId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get viewedAt => $composableBuilder(
    column: $table.viewedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FeedbackViewLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FeedbackViewLogsTable> {
  $$FeedbackViewLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get postId =>
      $composableBuilder(column: $table.postId, builder: (column) => column);

  GeneratedColumn<int> get viewedAt =>
      $composableBuilder(column: $table.viewedAt, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);
}

class $$FeedbackViewLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FeedbackViewLogsTable,
          FeedbackViewLogRow,
          $$FeedbackViewLogsTableFilterComposer,
          $$FeedbackViewLogsTableOrderingComposer,
          $$FeedbackViewLogsTableAnnotationComposer,
          $$FeedbackViewLogsTableCreateCompanionBuilder,
          $$FeedbackViewLogsTableUpdateCompanionBuilder,
          (
            FeedbackViewLogRow,
            BaseReferences<
              _$AppDatabase,
              $FeedbackViewLogsTable,
              FeedbackViewLogRow
            >,
          ),
          FeedbackViewLogRow,
          PrefetchHooks Function()
        > {
  $$FeedbackViewLogsTableTableManager(
    _$AppDatabase db,
    $FeedbackViewLogsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FeedbackViewLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FeedbackViewLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FeedbackViewLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> postId = const Value.absent(),
                Value<int> viewedAt = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FeedbackViewLogsCompanion(
                id: id,
                postId: postId,
                viewedAt: viewedAt,
                durationMs: durationMs,
                scope: scope,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> postId = const Value.absent(),
                required int viewedAt,
                Value<int> durationMs = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FeedbackViewLogsCompanion.insert(
                id: id,
                postId: postId,
                viewedAt: viewedAt,
                durationMs: durationMs,
                scope: scope,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FeedbackViewLogsTable, FeedbackViewLogRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $FeedbackViewLogsTable,
                    FeedbackViewLogRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FeedbackViewLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FeedbackViewLogsTable,
      FeedbackViewLogRow,
      $$FeedbackViewLogsTableFilterComposer,
      $$FeedbackViewLogsTableOrderingComposer,
      $$FeedbackViewLogsTableAnnotationComposer,
      $$FeedbackViewLogsTableCreateCompanionBuilder,
      $$FeedbackViewLogsTableUpdateCompanionBuilder,
      (
        FeedbackViewLogRow,
        BaseReferences<
          _$AppDatabase,
          $FeedbackViewLogsTable,
          FeedbackViewLogRow
        >,
      ),
      FeedbackViewLogRow,
      PrefetchHooks Function()
    >;
typedef $$StickersTableCreateCompanionBuilder = StickersCompanion Function({
  required String id,
  required String name,
  required String category,
  Value<String> source,
  required String path,
  Value<bool> isUser,
  Value<bool> isBuiltin,
  Value<int?> createdAt,
  Value<int?> deletedAt,
  Value<String> scope,
  Value<int> rowid,
});
typedef $$StickersTableUpdateCompanionBuilder = StickersCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> category,
  Value<String> source,
  Value<String> path,
  Value<bool> isUser,
  Value<bool> isBuiltin,
  Value<int?> createdAt,
  Value<int?> deletedAt,
  Value<String> scope,
  Value<int> rowid,
});

class $$StickersTableFilterComposer
    extends Composer<_$AppDatabase, $StickersTable> {
  $$StickersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isUser => $composableBuilder(
    column: $table.isUser,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBuiltin => $composableBuilder(
    column: $table.isBuiltin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StickersTableOrderingComposer
    extends Composer<_$AppDatabase, $StickersTable> {
  $$StickersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isUser => $composableBuilder(
    column: $table.isUser,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBuiltin => $composableBuilder(
    column: $table.isBuiltin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StickersTableAnnotationComposer
    extends Composer<_$AppDatabase, $StickersTable> {
  $$StickersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<bool> get isUser =>
      $composableBuilder(column: $table.isUser, builder: (column) => column);

  GeneratedColumn<bool> get isBuiltin =>
      $composableBuilder(column: $table.isBuiltin, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);
}

class $$StickersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StickersTable,
          StickerRow,
          $$StickersTableFilterComposer,
          $$StickersTableOrderingComposer,
          $$StickersTableAnnotationComposer,
          $$StickersTableCreateCompanionBuilder,
          $$StickersTableUpdateCompanionBuilder,
          (
            StickerRow,
            BaseReferences<_$AppDatabase, $StickersTable, StickerRow>,
          ),
          StickerRow,
          PrefetchHooks Function()
        > {
  $$StickersTableTableManager(_$AppDatabase db, $StickersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StickersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StickersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StickersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<bool> isUser = const Value.absent(),
                Value<bool> isBuiltin = const Value.absent(),
                Value<int?> createdAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StickersCompanion(
                id: id,
                name: name,
                category: category,
                source: source,
                path: path,
                isUser: isUser,
                isBuiltin: isBuiltin,
                createdAt: createdAt,
                deletedAt: deletedAt,
                scope: scope,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String category,
                Value<String> source = const Value.absent(),
                required String path,
                Value<bool> isUser = const Value.absent(),
                Value<bool> isBuiltin = const Value.absent(),
                Value<int?> createdAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StickersCompanion.insert(
                id: id,
                name: name,
                category: category,
                source: source,
                path: path,
                isUser: isUser,
                isBuiltin: isBuiltin,
                createdAt: createdAt,
                deletedAt: deletedAt,
                scope: scope,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StickersTable, StickerRow>(table),
                  BaseReferences<_$AppDatabase, $StickersTable, StickerRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StickersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StickersTable,
      StickerRow,
      $$StickersTableFilterComposer,
      $$StickersTableOrderingComposer,
      $$StickersTableAnnotationComposer,
      $$StickersTableCreateCompanionBuilder,
      $$StickersTableUpdateCompanionBuilder,
      (StickerRow, BaseReferences<_$AppDatabase, $StickersTable, StickerRow>),
      StickerRow,
      PrefetchHooks Function()
    >;
typedef $$PlanScriptsTableCreateCompanionBuilder =
    PlanScriptsCompanion Function({
      required String id,
      required String name,
      Value<bool> isBuiltIn,
      Value<String> postContent,
      Value<String> postImages,
      Value<String?> topicName,
      Value<String> stepsJson,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$PlanScriptsTableUpdateCompanionBuilder =
    PlanScriptsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<bool> isBuiltIn,
      Value<String> postContent,
      Value<String> postImages,
      Value<String?> topicName,
      Value<String> stepsJson,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$PlanScriptsTableFilterComposer
    extends Composer<_$AppDatabase, $PlanScriptsTable> {
  $$PlanScriptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBuiltIn => $composableBuilder(
    column: $table.isBuiltIn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get postContent => $composableBuilder(
    column: $table.postContent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get postImages => $composableBuilder(
    column: $table.postImages,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topicName => $composableBuilder(
    column: $table.topicName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stepsJson => $composableBuilder(
    column: $table.stepsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlanScriptsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlanScriptsTable> {
  $$PlanScriptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBuiltIn => $composableBuilder(
    column: $table.isBuiltIn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get postContent => $composableBuilder(
    column: $table.postContent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get postImages => $composableBuilder(
    column: $table.postImages,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topicName => $composableBuilder(
    column: $table.topicName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stepsJson => $composableBuilder(
    column: $table.stepsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlanScriptsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlanScriptsTable> {
  $$PlanScriptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isBuiltIn =>
      $composableBuilder(column: $table.isBuiltIn, builder: (column) => column);

  GeneratedColumn<String> get postContent => $composableBuilder(
    column: $table.postContent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get postImages => $composableBuilder(
    column: $table.postImages,
    builder: (column) => column,
  );

  GeneratedColumn<String> get topicName =>
      $composableBuilder(column: $table.topicName, builder: (column) => column);

  GeneratedColumn<String> get stepsJson =>
      $composableBuilder(column: $table.stepsJson, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PlanScriptsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlanScriptsTable,
          PlanScriptRow,
          $$PlanScriptsTableFilterComposer,
          $$PlanScriptsTableOrderingComposer,
          $$PlanScriptsTableAnnotationComposer,
          $$PlanScriptsTableCreateCompanionBuilder,
          $$PlanScriptsTableUpdateCompanionBuilder,
          (
            PlanScriptRow,
            BaseReferences<_$AppDatabase, $PlanScriptsTable, PlanScriptRow>,
          ),
          PlanScriptRow,
          PrefetchHooks Function()
        > {
  $$PlanScriptsTableTableManager(_$AppDatabase db, $PlanScriptsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlanScriptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlanScriptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlanScriptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> isBuiltIn = const Value.absent(),
                Value<String> postContent = const Value.absent(),
                Value<String> postImages = const Value.absent(),
                Value<String?> topicName = const Value.absent(),
                Value<String> stepsJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlanScriptsCompanion(
                id: id,
                name: name,
                isBuiltIn: isBuiltIn,
                postContent: postContent,
                postImages: postImages,
                topicName: topicName,
                stepsJson: stepsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<bool> isBuiltIn = const Value.absent(),
                Value<String> postContent = const Value.absent(),
                Value<String> postImages = const Value.absent(),
                Value<String?> topicName = const Value.absent(),
                Value<String> stepsJson = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlanScriptsCompanion.insert(
                id: id,
                name: name,
                isBuiltIn: isBuiltIn,
                postContent: postContent,
                postImages: postImages,
                topicName: topicName,
                stepsJson: stepsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlanScriptsTable, PlanScriptRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PlanScriptsTable,
                    PlanScriptRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlanScriptsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlanScriptsTable,
      PlanScriptRow,
      $$PlanScriptsTableFilterComposer,
      $$PlanScriptsTableOrderingComposer,
      $$PlanScriptsTableAnnotationComposer,
      $$PlanScriptsTableCreateCompanionBuilder,
      $$PlanScriptsTableUpdateCompanionBuilder,
      (
        PlanScriptRow,
        BaseReferences<_$AppDatabase, $PlanScriptsTable, PlanScriptRow>,
      ),
      PlanScriptRow,
      PrefetchHooks Function()
    >;
typedef $$PlanEventsTableCreateCompanionBuilder = PlanEventsCompanion Function({
  required String id,
  required String postId,
  Value<String?> scriptId,
  required String type,
  Value<String?> personaId,
  Value<String?> mediaType,
  Value<String?> content,
  Value<String?> voiceAsset,
  Value<int?> voiceDurationMs,
  Value<String?> transcript,
  Value<int?> delta,
  Value<int?> likes,
  Value<int?> comments,
  Value<String?> toMode,
  Value<String?> analysisJson,
  required int scheduledAt,
  Value<int?> executedAt,
  Value<String> status,
  Value<int> rowid,
});
typedef $$PlanEventsTableUpdateCompanionBuilder = PlanEventsCompanion Function({
  Value<String> id,
  Value<String> postId,
  Value<String?> scriptId,
  Value<String> type,
  Value<String?> personaId,
  Value<String?> mediaType,
  Value<String?> content,
  Value<String?> voiceAsset,
  Value<int?> voiceDurationMs,
  Value<String?> transcript,
  Value<int?> delta,
  Value<int?> likes,
  Value<int?> comments,
  Value<String?> toMode,
  Value<String?> analysisJson,
  Value<int> scheduledAt,
  Value<int?> executedAt,
  Value<String> status,
  Value<int> rowid,
});

final class $$PlanEventsTableReferences
    extends BaseReferences<_$AppDatabase, $PlanEventsTable, PlanEventRow> {
  $$PlanEventsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PostsTable _postIdTable(_$AppDatabase db) =>
      db.posts.createAlias('plan_events__post_id__posts__id');

  $$PostsTableProcessedTableManager get postId {
    final $_column = $_itemColumn<String>('post_id')!;

    final manager = $$PostsTableTableManager(
      $_db,
      $_db.posts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_postIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PlanEventsTableFilterComposer
    extends Composer<_$AppDatabase, $PlanEventsTable> {
  $$PlanEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scriptId => $composableBuilder(
    column: $table.scriptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get personaId => $composableBuilder(
    column: $table.personaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voiceAsset => $composableBuilder(
    column: $table.voiceAsset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get voiceDurationMs => $composableBuilder(
    column: $table.voiceDurationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transcript => $composableBuilder(
    column: $table.transcript,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get delta => $composableBuilder(
    column: $table.delta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get likes => $composableBuilder(
    column: $table.likes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get comments => $composableBuilder(
    column: $table.comments,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toMode => $composableBuilder(
    column: $table.toMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get analysisJson => $composableBuilder(
    column: $table.analysisJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get executedAt => $composableBuilder(
    column: $table.executedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  $$PostsTableFilterComposer get postId {
    final $$PostsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.postId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableFilterComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlanEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlanEventsTable> {
  $$PlanEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scriptId => $composableBuilder(
    column: $table.scriptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get personaId => $composableBuilder(
    column: $table.personaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voiceAsset => $composableBuilder(
    column: $table.voiceAsset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get voiceDurationMs => $composableBuilder(
    column: $table.voiceDurationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transcript => $composableBuilder(
    column: $table.transcript,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get delta => $composableBuilder(
    column: $table.delta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get likes => $composableBuilder(
    column: $table.likes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get comments => $composableBuilder(
    column: $table.comments,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toMode => $composableBuilder(
    column: $table.toMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get analysisJson => $composableBuilder(
    column: $table.analysisJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get executedAt => $composableBuilder(
    column: $table.executedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  $$PostsTableOrderingComposer get postId {
    final $$PostsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.postId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableOrderingComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlanEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlanEventsTable> {
  $$PlanEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get scriptId =>
      $composableBuilder(column: $table.scriptId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get personaId =>
      $composableBuilder(column: $table.personaId, builder: (column) => column);

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get voiceAsset => $composableBuilder(
    column: $table.voiceAsset,
    builder: (column) => column,
  );

  GeneratedColumn<int> get voiceDurationMs => $composableBuilder(
    column: $table.voiceDurationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get transcript => $composableBuilder(
    column: $table.transcript,
    builder: (column) => column,
  );

  GeneratedColumn<int> get delta =>
      $composableBuilder(column: $table.delta, builder: (column) => column);

  GeneratedColumn<int> get likes =>
      $composableBuilder(column: $table.likes, builder: (column) => column);

  GeneratedColumn<int> get comments =>
      $composableBuilder(column: $table.comments, builder: (column) => column);

  GeneratedColumn<String> get toMode =>
      $composableBuilder(column: $table.toMode, builder: (column) => column);

  GeneratedColumn<String> get analysisJson => $composableBuilder(
    column: $table.analysisJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get executedAt => $composableBuilder(
    column: $table.executedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  $$PostsTableAnnotationComposer get postId {
    final $$PostsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.postId,
      referencedTable: $db.posts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PostsTableAnnotationComposer(
            $db: $db,
            $table: $db.posts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlanEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlanEventsTable,
          PlanEventRow,
          $$PlanEventsTableFilterComposer,
          $$PlanEventsTableOrderingComposer,
          $$PlanEventsTableAnnotationComposer,
          $$PlanEventsTableCreateCompanionBuilder,
          $$PlanEventsTableUpdateCompanionBuilder,
          (PlanEventRow, $$PlanEventsTableReferences),
          PlanEventRow,
          PrefetchHooks Function({bool postId})
        > {
  $$PlanEventsTableTableManager(_$AppDatabase db, $PlanEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlanEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlanEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlanEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> postId = const Value.absent(),
                Value<String?> scriptId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> personaId = const Value.absent(),
                Value<String?> mediaType = const Value.absent(),
                Value<String?> content = const Value.absent(),
                Value<String?> voiceAsset = const Value.absent(),
                Value<int?> voiceDurationMs = const Value.absent(),
                Value<String?> transcript = const Value.absent(),
                Value<int?> delta = const Value.absent(),
                Value<int?> likes = const Value.absent(),
                Value<int?> comments = const Value.absent(),
                Value<String?> toMode = const Value.absent(),
                Value<String?> analysisJson = const Value.absent(),
                Value<int> scheduledAt = const Value.absent(),
                Value<int?> executedAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlanEventsCompanion(
                id: id,
                postId: postId,
                scriptId: scriptId,
                type: type,
                personaId: personaId,
                mediaType: mediaType,
                content: content,
                voiceAsset: voiceAsset,
                voiceDurationMs: voiceDurationMs,
                transcript: transcript,
                delta: delta,
                likes: likes,
                comments: comments,
                toMode: toMode,
                analysisJson: analysisJson,
                scheduledAt: scheduledAt,
                executedAt: executedAt,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String postId,
                Value<String?> scriptId = const Value.absent(),
                required String type,
                Value<String?> personaId = const Value.absent(),
                Value<String?> mediaType = const Value.absent(),
                Value<String?> content = const Value.absent(),
                Value<String?> voiceAsset = const Value.absent(),
                Value<int?> voiceDurationMs = const Value.absent(),
                Value<String?> transcript = const Value.absent(),
                Value<int?> delta = const Value.absent(),
                Value<int?> likes = const Value.absent(),
                Value<int?> comments = const Value.absent(),
                Value<String?> toMode = const Value.absent(),
                Value<String?> analysisJson = const Value.absent(),
                required int scheduledAt,
                Value<int?> executedAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlanEventsCompanion.insert(
                id: id,
                postId: postId,
                scriptId: scriptId,
                type: type,
                personaId: personaId,
                mediaType: mediaType,
                content: content,
                voiceAsset: voiceAsset,
                voiceDurationMs: voiceDurationMs,
                transcript: transcript,
                delta: delta,
                likes: likes,
                comments: comments,
                toMode: toMode,
                analysisJson: analysisJson,
                scheduledAt: scheduledAt,
                executedAt: executedAt,
                status: status,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlanEventsTable, PlanEventRow>(table),
                  $$PlanEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({postId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (postId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.postId,
                        referencedTable: $$PlanEventsTableReferences
                            ._postIdTable(db),
                        referencedColumn: $$PlanEventsTableReferences
                            ._postIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PlanEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlanEventsTable,
      PlanEventRow,
      $$PlanEventsTableFilterComposer,
      $$PlanEventsTableOrderingComposer,
      $$PlanEventsTableAnnotationComposer,
      $$PlanEventsTableCreateCompanionBuilder,
      $$PlanEventsTableUpdateCompanionBuilder,
      (PlanEventRow, $$PlanEventsTableReferences),
      PlanEventRow,
      PrefetchHooks Function({bool postId})
    >;
typedef $$ModelConfigsTableCreateCompanionBuilder =
    ModelConfigsCompanion Function({
      required String id,
      required String provider,
      required String label,
      required String baseUrl,
      required String model,
      Value<bool> enabled,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$ModelConfigsTableUpdateCompanionBuilder =
    ModelConfigsCompanion Function({
      Value<String> id,
      Value<String> provider,
      Value<String> label,
      Value<String> baseUrl,
      Value<String> model,
      Value<bool> enabled,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$ModelConfigsTableFilterComposer
    extends Composer<_$AppDatabase, $ModelConfigsTable> {
  $$ModelConfigsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ModelConfigsTableOrderingComposer
    extends Composer<_$AppDatabase, $ModelConfigsTable> {
  $$ModelConfigsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ModelConfigsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ModelConfigsTable> {
  $$ModelConfigsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ModelConfigsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ModelConfigsTable,
          ModelConfigRow,
          $$ModelConfigsTableFilterComposer,
          $$ModelConfigsTableOrderingComposer,
          $$ModelConfigsTableAnnotationComposer,
          $$ModelConfigsTableCreateCompanionBuilder,
          $$ModelConfigsTableUpdateCompanionBuilder,
          (
            ModelConfigRow,
            BaseReferences<_$AppDatabase, $ModelConfigsTable, ModelConfigRow>,
          ),
          ModelConfigRow,
          PrefetchHooks Function()
        > {
  $$ModelConfigsTableTableManager(_$AppDatabase db, $ModelConfigsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ModelConfigsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ModelConfigsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ModelConfigsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> baseUrl = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModelConfigsCompanion(
                id: id,
                provider: provider,
                label: label,
                baseUrl: baseUrl,
                model: model,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String provider,
                required String label,
                required String baseUrl,
                required String model,
                Value<bool> enabled = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ModelConfigsCompanion.insert(
                id: id,
                provider: provider,
                label: label,
                baseUrl: baseUrl,
                model: model,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ModelConfigsTable, ModelConfigRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ModelConfigsTable,
                    ModelConfigRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ModelConfigsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ModelConfigsTable,
      ModelConfigRow,
      $$ModelConfigsTableFilterComposer,
      $$ModelConfigsTableOrderingComposer,
      $$ModelConfigsTableAnnotationComposer,
      $$ModelConfigsTableCreateCompanionBuilder,
      $$ModelConfigsTableUpdateCompanionBuilder,
      (
        ModelConfigRow,
        BaseReferences<_$AppDatabase, $ModelConfigsTable, ModelConfigRow>,
      ),
      ModelConfigRow,
      PrefetchHooks Function()
    >;
typedef $$ValueClarificationsTableCreateCompanionBuilder =
    ValueClarificationsCompanion Function({
      required String id,
      required String content,
      Value<int> sortOrder,
      required int createdAt,
      Value<int?> deletedAt,
      Value<String> scope,
      Value<int> rowid,
    });
typedef $$ValueClarificationsTableUpdateCompanionBuilder =
    ValueClarificationsCompanion Function({
      Value<String> id,
      Value<String> content,
      Value<int> sortOrder,
      Value<int> createdAt,
      Value<int?> deletedAt,
      Value<String> scope,
      Value<int> rowid,
    });

class $$ValueClarificationsTableFilterComposer
    extends Composer<_$AppDatabase, $ValueClarificationsTable> {
  $$ValueClarificationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ValueClarificationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ValueClarificationsTable> {
  $$ValueClarificationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ValueClarificationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ValueClarificationsTable> {
  $$ValueClarificationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);
}

class $$ValueClarificationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ValueClarificationsTable,
          ValueClarificationRow,
          $$ValueClarificationsTableFilterComposer,
          $$ValueClarificationsTableOrderingComposer,
          $$ValueClarificationsTableAnnotationComposer,
          $$ValueClarificationsTableCreateCompanionBuilder,
          $$ValueClarificationsTableUpdateCompanionBuilder,
          (
            ValueClarificationRow,
            BaseReferences<
              _$AppDatabase,
              $ValueClarificationsTable,
              ValueClarificationRow
            >,
          ),
          ValueClarificationRow,
          PrefetchHooks Function()
        > {
  $$ValueClarificationsTableTableManager(
    _$AppDatabase db,
    $ValueClarificationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ValueClarificationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ValueClarificationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ValueClarificationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ValueClarificationsCompanion(
                id: id,
                content: content,
                sortOrder: sortOrder,
                createdAt: createdAt,
                deletedAt: deletedAt,
                scope: scope,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String content,
                Value<int> sortOrder = const Value.absent(),
                required int createdAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ValueClarificationsCompanion.insert(
                id: id,
                content: content,
                sortOrder: sortOrder,
                createdAt: createdAt,
                deletedAt: deletedAt,
                scope: scope,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ValueClarificationsTable, ValueClarificationRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $ValueClarificationsTable,
                    ValueClarificationRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ValueClarificationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ValueClarificationsTable,
      ValueClarificationRow,
      $$ValueClarificationsTableFilterComposer,
      $$ValueClarificationsTableOrderingComposer,
      $$ValueClarificationsTableAnnotationComposer,
      $$ValueClarificationsTableCreateCompanionBuilder,
      $$ValueClarificationsTableUpdateCompanionBuilder,
      (
        ValueClarificationRow,
        BaseReferences<
          _$AppDatabase,
          $ValueClarificationsTable,
          ValueClarificationRow
        >,
      ),
      ValueClarificationRow,
      PrefetchHooks Function()
    >;
typedef $$RealActionsTableCreateCompanionBuilder =
    RealActionsCompanion Function({
      required String id,
      required String title,
      Value<String> description,
      required String category,
      required int createdAt,
      Value<int?> deletedAt,
      Value<String> scope,
      Value<int> rowid,
    });
typedef $$RealActionsTableUpdateCompanionBuilder =
    RealActionsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> description,
      Value<String> category,
      Value<int> createdAt,
      Value<int?> deletedAt,
      Value<String> scope,
      Value<int> rowid,
    });

class $$RealActionsTableFilterComposer
    extends Composer<_$AppDatabase, $RealActionsTable> {
  $$RealActionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RealActionsTableOrderingComposer
    extends Composer<_$AppDatabase, $RealActionsTable> {
  $$RealActionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RealActionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RealActionsTable> {
  $$RealActionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);
}

class $$RealActionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RealActionsTable,
          RealActionRow,
          $$RealActionsTableFilterComposer,
          $$RealActionsTableOrderingComposer,
          $$RealActionsTableAnnotationComposer,
          $$RealActionsTableCreateCompanionBuilder,
          $$RealActionsTableUpdateCompanionBuilder,
          (
            RealActionRow,
            BaseReferences<_$AppDatabase, $RealActionsTable, RealActionRow>,
          ),
          RealActionRow,
          PrefetchHooks Function()
        > {
  $$RealActionsTableTableManager(_$AppDatabase db, $RealActionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RealActionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RealActionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RealActionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RealActionsCompanion(
                id: id,
                title: title,
                description: description,
                category: category,
                createdAt: createdAt,
                deletedAt: deletedAt,
                scope: scope,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String> description = const Value.absent(),
                required String category,
                required int createdAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RealActionsCompanion.insert(
                id: id,
                title: title,
                description: description,
                category: category,
                createdAt: createdAt,
                deletedAt: deletedAt,
                scope: scope,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RealActionsTable, RealActionRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $RealActionsTable,
                    RealActionRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RealActionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RealActionsTable,
      RealActionRow,
      $$RealActionsTableFilterComposer,
      $$RealActionsTableOrderingComposer,
      $$RealActionsTableAnnotationComposer,
      $$RealActionsTableCreateCompanionBuilder,
      $$RealActionsTableUpdateCompanionBuilder,
      (
        RealActionRow,
        BaseReferences<_$AppDatabase, $RealActionsTable, RealActionRow>,
      ),
      RealActionRow,
      PrefetchHooks Function()
    >;
typedef $$AddictionLogsTableCreateCompanionBuilder =
    AddictionLogsCompanion Function({
      required String id,
      required String eventType,
      Value<int> value,
      required int createdAt,
      Value<String> scope,
      Value<int> rowid,
    });
typedef $$AddictionLogsTableUpdateCompanionBuilder =
    AddictionLogsCompanion Function({
      Value<String> id,
      Value<String> eventType,
      Value<int> value,
      Value<int> createdAt,
      Value<String> scope,
      Value<int> rowid,
    });

class $$AddictionLogsTableFilterComposer
    extends Composer<_$AppDatabase, $AddictionLogsTable> {
  $$AddictionLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AddictionLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $AddictionLogsTable> {
  $$AddictionLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AddictionLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AddictionLogsTable> {
  $$AddictionLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<int> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);
}

class $$AddictionLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AddictionLogsTable,
          AddictionLogRow,
          $$AddictionLogsTableFilterComposer,
          $$AddictionLogsTableOrderingComposer,
          $$AddictionLogsTableAnnotationComposer,
          $$AddictionLogsTableCreateCompanionBuilder,
          $$AddictionLogsTableUpdateCompanionBuilder,
          (
            AddictionLogRow,
            BaseReferences<_$AppDatabase, $AddictionLogsTable, AddictionLogRow>,
          ),
          AddictionLogRow,
          PrefetchHooks Function()
        > {
  $$AddictionLogsTableTableManager(_$AppDatabase db, $AddictionLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AddictionLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AddictionLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AddictionLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<int> value = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AddictionLogsCompanion(
                id: id,
                eventType: eventType,
                value: value,
                createdAt: createdAt,
                scope: scope,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String eventType,
                Value<int> value = const Value.absent(),
                required int createdAt,
                Value<String> scope = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AddictionLogsCompanion.insert(
                id: id,
                eventType: eventType,
                value: value,
                createdAt: createdAt,
                scope: scope,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AddictionLogsTable, AddictionLogRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AddictionLogsTable,
                    AddictionLogRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AddictionLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AddictionLogsTable,
      AddictionLogRow,
      $$AddictionLogsTableFilterComposer,
      $$AddictionLogsTableOrderingComposer,
      $$AddictionLogsTableAnnotationComposer,
      $$AddictionLogsTableCreateCompanionBuilder,
      $$AddictionLogsTableUpdateCompanionBuilder,
      (
        AddictionLogRow,
        BaseReferences<_$AppDatabase, $AddictionLogsTable, AddictionLogRow>,
      ),
      AddictionLogRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$UserProfileTableTableManager get userProfile =>
      $$UserProfileTableTableManager(_db, _db.userProfile);
  $$PostsTableTableManager get posts =>
      $$PostsTableTableManager(_db, _db.posts);
  $$AiPersonasTableTableManager get aiPersonas =>
      $$AiPersonasTableTableManager(_db, _db.aiPersonas);
  $$AiInteractionsTableTableManager get aiInteractions =>
      $$AiInteractionsTableTableManager(_db, _db.aiInteractions);
  $$AnalysisResultsTableTableManager get analysisResults =>
      $$AnalysisResultsTableTableManager(_db, _db.analysisResults);
  $$ModeSwitchLogsTableTableManager get modeSwitchLogs =>
      $$ModeSwitchLogsTableTableManager(_db, _db.modeSwitchLogs);
  $$NotificationLogsTableTableManager get notificationLogs =>
      $$NotificationLogsTableTableManager(_db, _db.notificationLogs);
  $$FeedbackViewLogsTableTableManager get feedbackViewLogs =>
      $$FeedbackViewLogsTableTableManager(_db, _db.feedbackViewLogs);
  $$StickersTableTableManager get stickers =>
      $$StickersTableTableManager(_db, _db.stickers);
  $$PlanScriptsTableTableManager get planScripts =>
      $$PlanScriptsTableTableManager(_db, _db.planScripts);
  $$PlanEventsTableTableManager get planEvents =>
      $$PlanEventsTableTableManager(_db, _db.planEvents);
  $$ModelConfigsTableTableManager get modelConfigs =>
      $$ModelConfigsTableTableManager(_db, _db.modelConfigs);
  $$ValueClarificationsTableTableManager get valueClarifications =>
      $$ValueClarificationsTableTableManager(_db, _db.valueClarifications);
  $$RealActionsTableTableManager get realActions =>
      $$RealActionsTableTableManager(_db, _db.realActions);
  $$AddictionLogsTableTableManager get addictionLogs =>
      $$AddictionLogsTableTableManager(_db, _db.addictionLogs);
}
