import '../../core/constants/app_texts.dart';

/// 用户资料（阶段 A 只用得到昵称与头像，对应 `user_profile` 单行表）。
///
/// 头像存的是**引用**而不是路径本身：`asset:` / `file:` / 空字符串，
/// 交给 [UserAvatar] 走「图片优先、文字兜底」那三级解析。
class UserProfile {
  const UserProfile({
    this.nickname = '',
    this.avatarRef = '',
    this.gender = '',
    this.ageRange = '',
    this.occupation = '',
    this.city = '',
    this.interests = '',
    this.preferredName = '',
    this.intro = '',
  });

  final String nickname;
  final String avatarRef;

  /// 身份资料（v24）。存稳定枚举/自由文本，空字符串 = 没填。
  final String gender;
  final String ageRange;
  final String occupation;
  final String city;
  final String interests;

  /// 希望 AI 怎么称呼你。
  final String preferredName;
  final String intro;

  bool get hasIdentity =>
      [
        gender,
        ageRange,
        occupation,
        city,
        interests,
        preferredName,
        intro,
      ].any((value) => value.trim().isNotEmpty);

  String get genderLabel => switch (gender.trim()) {
    'male' => '男',
    'female' => '女',
    'nonbinary' => '非二元',
    'secret' => '不愿透露',
    _ => '',
  };

  /// 界面上一律用这个，而不是裸的 [nickname]。
  ///
  /// 老库（阶段 A 早期播种的那一行）昵称是空字符串，所以必须兜底——
  /// 否则界面上会出现一个没有名字的人。
  String get displayName {
    final trimmed = nickname.trim();
    return trimmed.isEmpty ? AppTexts.defaultNickname : trimmed;
  }

  /// 空字符串表示"用文字头像"（三级兜底的最后一级）。
  String? get avatarOrNull {
    final trimmed = avatarRef.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  UserProfile copyWith({
    String? nickname,
    String? avatarRef,
    String? gender,
    String? ageRange,
    String? occupation,
    String? city,
    String? interests,
    String? preferredName,
    String? intro,
  }) => UserProfile(
    nickname: nickname ?? this.nickname,
    avatarRef: avatarRef ?? this.avatarRef,
    gender: gender ?? this.gender,
    ageRange: ageRange ?? this.ageRange,
    occupation: occupation ?? this.occupation,
    city: city ?? this.city,
    interests: interests ?? this.interests,
    preferredName: preferredName ?? this.preferredName,
    intro: intro ?? this.intro,
  );
}
