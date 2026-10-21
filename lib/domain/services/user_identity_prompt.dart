import '../models/user_profile.dart';

/// “正在使用这个应用的人是谁”——所有 AI 请求共享的稳定前缀。
///
/// **只放稳定内容**：这里出现时间、当前页面、这次要做什么，缓存前缀
/// 就会每轮分叉。身份变化很少，改了才整体失效一次，可以接受。
class UserIdentityPrompt {
  const UserIdentityPrompt._();

  static String build(UserProfile? profile) {
    if (profile == null) return '';
    final name = profile.preferredName.trim().isNotEmpty
        ? profile.preferredName.trim()
        : profile.nickname.trim();

    final lines = <String>[];
    if (name.isNotEmpty) lines.add('称呼他：$name');
    final gender = profile.genderLabel;
    if (gender.isNotEmpty) lines.add('性别：$gender');
    if (profile.ageRange.trim().isNotEmpty) {
      lines.add('年龄段：${profile.ageRange.trim()}');
    }
    if (profile.occupation.trim().isNotEmpty) {
      lines.add('身份／职业：${profile.occupation.trim()}');
    }
    if (profile.city.trim().isNotEmpty) {
      lines.add('所在城市：${profile.city.trim()}');
    }
    if (profile.interests.trim().isNotEmpty) {
      lines.add('兴趣爱好：${profile.interests.trim()}');
    }
    if (profile.intro.trim().isNotEmpty) {
      lines.add('自我介绍：${profile.intro.trim()}');
    }
    if (lines.isEmpty) return '';

    return [
      '【关于正在使用这个应用的人】',
      ...lines,
      '说明：以上是用户自己填写的资料。提到他时用合适的称呼和代词，'
          '不要反问这些信息，也不要逐条复述；没填的不要编造。',
      '',
    ].join('\n');
  }
}
