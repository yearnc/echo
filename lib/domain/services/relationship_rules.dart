import 'dart:math';

/// 关系推进规则（B4）：**纯逻辑，不碰数据库、不联网**。
///
/// 住民和你的关系走到哪一步，是互动**攒**出来的，不是时间到了自动变近。
/// 这里只回答一个问题：刚发生的这件事，让你们近了多少。
/// 「什么时候会有互动」归调度器，「结果怎么写回库」归仓储。

/// 一次互动的类型。
///
/// 只认这几种。数据库里 `ai_interactions.type` 存的是字符串（还可能有
/// `repost` 这些 B 阶段之后才用的），认不出来的统一按最轻的那种算。
enum RelationshipEvent { like, comment, reply, message, follow }

extension RelationshipEventWeight on RelationshipEvent {
  /// 这一次互动值多少亲近度。
  ///
  /// 差别是有意的：点赞是"路过看了一眼"，私信是"专门想跟你说句话"，
  /// 它们在一段关系里的分量本来就不一样。
  int get weight => switch (this) {
    RelationshipEvent.like => 1,
    RelationshipEvent.follow => 2,
    RelationshipEvent.comment => 3,
    RelationshipEvent.reply => 4,
    RelationshipEvent.message => 5,
  };
}

/// 档位名（规划书 §3.9）。存进库的是数字，说给人听的是这几个词。
const List<String> relationshipTierLabels = ['陌生', '眼熟', '互关', '熟人', '好友'];

/// 一个住民和你的关系现状。与 `ai_relationships` 一行一一对应。
class RelationshipState {
  const RelationshipState({
    required this.personaId,
    this.level = 0,
    this.intimacy = 0,
    this.interactionCount = 0,
    this.lastInteractionAt,
    this.followState = 'none',
    this.memorySummary = '',
  });

  final String personaId;

  /// 0 陌生 → 1 眼熟 → 2 互关 → 3 熟人 → 4 好友。
  final int level;
  final int intimacy;

  /// 真·互动次数。与 [intimacy] 分开：一个是"聊过几回"，
  /// 一个是"多亲近"——十条礼貌回复不该等于一次深夜长谈。
  final int interactionCount;
  final DateTime? lastInteractionAt;

  /// none / following / followed / mutual（关注是 B5 的事，B4 只把它存着）。
  final String followState;

  /// 压缩过的「我记得你…」。见 [[MemorySummarizer]]。
  final String memorySummary;

  static const int maxLevel = 4;

  String get tierLabel => relationshipTierLabels[level.clamp(0, maxLevel)];

  /// 还没打过交道的人。
  factory RelationshipState.stranger(String personaId) =>
      RelationshipState(personaId: personaId);

  RelationshipState copyWith({
    int? level,
    int? intimacy,
    int? interactionCount,
    DateTime? lastInteractionAt,
    String? followState,
    String? memorySummary,
  }) => RelationshipState(
    personaId: personaId,
    level: level ?? this.level,
    intimacy: intimacy ?? this.intimacy,
    interactionCount: interactionCount ?? this.interactionCount,
    lastInteractionAt: lastInteractionAt ?? this.lastInteractionAt,
    followState: followState ?? this.followState,
    memorySummary: memorySummary ?? this.memorySummary,
  );
}

class RelationshipRules {
  /// 同一个住民**至少隔这么久**，才会再长一次亲近度。
  ///
  /// 不是"时间到了就变近"，而是"一天里被同一个人反复搭话，亲近感不会翻倍"。
  /// 次数照记（界面上那句"你们互动过 12 次"是真的），长的是关系，不是计数。
  static const Duration intimacyCooldown = Duration(hours: 6);

  /// 攒够多少亲近度到第几档。第 0 档是起点，不用攒。
  ///
  /// 一次评论 3 分，所以"他评论过你一次"就是眼熟；互关要约 4 次，
  /// 熟人十来次，好友得是大半个月里一直有来有往。
  static const List<int> thresholds = [0, 3, 10, 22, 40];

  /// 这点亲近度够到第几档。纯查表，边界含等号。
  static int levelFor(int intimacy) {
    for (var level = thresholds.length - 1; level > 0; level--) {
      if (intimacy >= thresholds[level]) return level;
    }
    return 0;
  }

  /// 关系够近之后，他会关注你（B5）。
  ///
  /// 刻意**不做成"随机某天忽然关注你"**：一个从没跟你说过话的人突然关注了你，
  /// 是最像机器人的一件事。关注是关系走到那一步的结果，不是一次抽奖。
  ///
  /// 状态机很小：none →(他关)→ followed →(你关)→ mutual；
  /// 你先关就是他回关。取消关注不在这一层——那是你自己的动作，
  /// 由仓储那边直接改。
  static String followAfter(String current, int level) {
    if (level < mutualTier) return current;
    return switch (current) {
      'none' => 'followed',
      'following' => 'mutual',
      _ => current,
    };
  }

  /// 到这一档才算"互关"（规划书 §3.9 的第 2 档）。
  static const int mutualTier = 2;

  /// 交互发生之后的新状态。
  ///
  /// **档位只升不降**：这里不做"太久没说话就退回陌生"——那属于产品要不要
  /// 做得那么刻薄的问题，而不是一条规则能顺手决定的。真要做，也该是一次
  /// 显式的、走到每个住民身上的清理，而不是让每次互动都提心吊胆。
  static RelationshipState apply({
    required RelationshipState current,
    required RelationshipEvent event,
    required DateTime at,
  }) {
    final last = current.lastInteractionAt;
    final grows = last == null || at.difference(last) >= intimacyCooldown;

    final intimacy = grows
        ? current.intimacy + event.weight
        : current.intimacy;
    final level = max(current.level, levelFor(intimacy));

    return current.copyWith(
      level: level,
      intimacy: intimacy,
      interactionCount: current.interactionCount + 1,
      // 时钟被往回调时**不倒退水位**：退回去的话，等时钟校准回来，
      // 下一次互动会因为"离那个早时刻已经很久了"而多涨一次。
      // 冷却期以最后一次真正的互动时刻为准。
      lastInteractionAt: last == null || at.isAfter(last) ? at : last,
      followState: followAfter(current.followState, level),
    );
  }

  /// 数据库里的字符串 → 事件类型。
  ///
  /// 认不出来的当成点赞：它是权重最低的那个，就算认错了，也只是少涨一点点
  /// 亲近度，不会把关系推得比实际更近。
  static RelationshipEvent eventFrom(String raw) => switch (raw) {
    'comment' => RelationshipEvent.comment,
    'reply' => RelationshipEvent.reply,
    'message' => RelationshipEvent.message,
    'follow' => RelationshipEvent.follow,
    _ => RelationshipEvent.like,
  };
}
