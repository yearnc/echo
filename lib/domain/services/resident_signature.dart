import 'dart:math';

import '../models/resident_post.dart';

/// 住民换签名的规矩（B3.5）。
///
/// 签名是一个人最随手、也最容易被看见的表达——QQ 状态、微信签名，改一句
/// 就是"我现在是这样"。住民该有这件能力，但不能想改就改：一天换三次签名的人
/// 不像人，像程序在动。
///
/// 这里管的是**什么时候值得改**，不管改成什么——那是内容生成层的事
/// （模型写，或者按圈层取预置句）。所以它是纯逻辑，能单独测。
class ResidentSignature {
  /// 同一个人两次换签名之间，至少隔这么久。
  static const Duration cooldown = Duration(days: 3);

  /// 冷却都过得去的时候，仍然只有这个概率真的改。
  ///
  /// 光有冷却不够用：世界 tick 一次最多补四条动态，用户一天开几次 APP
  /// 就 tick 几轮，全都放行的话，社区给人感觉是"这帮人天天在换签名"。
  /// 真人改签名是件挺郑重的、要攒一攒才做的事。
  static const double chance = 0.3;

  /// 一次 tick 最多几个人换（所以 [pick] 只挑一个）。
  static const int maxPerTick = 1;

  /// 签名不该长过这个。模型偶尔会写成一句小作文——那不是签名，是又一条动态，
  /// 这样的候选直接不要，而不是截一半（截出来的句子没有一句话是完整的）。
  static const int maxLength = 20;

  /// 从这批刚写好的动态里，挑一个顺手改了签名的人。返回 null 就是这次都不改。
  ///
  /// 候选只可能是"这次发了动态、并且生成层给了新签名"的人——改签名的由头
  /// 就是这条动态本身。[lastChangedAt] 是每个住民上次改签名的时刻。
  static ResidentPostDraft? pick({
    required List<ResidentPostDraft> drafts,
    required DateTime at,
    required Map<String, DateTime> lastChangedAt,
    Random? random,
    double chance = ResidentSignature.chance,
  }) {
    final fresh = drafts
        .where((draft) => _usable(draft.newBio))
        .toList(growable: false);
    if (fresh.isEmpty) return null;

    final eligible = fresh
        .where((draft) => _pastCooldown(lastChangedAt[draft.personaId], at))
        .toList(growable: false);
    if (eligible.isEmpty) return null;

    final rng = random ?? Random();
    if (rng.nextDouble() >= chance) return null;

    return eligible[rng.nextInt(eligible.length)];
  }

  static bool _usable(String? bio) {
    final trimmed = (bio ?? '').trim();
    return trimmed.isNotEmpty && trimmed.length <= maxLength;
  }

  static bool _pastCooldown(DateTime? last, DateTime at) {
    if (last == null) return true;
    return at.difference(last) >= cooldown;
  }
}
