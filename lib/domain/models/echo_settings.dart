/// 回响模式的三个旋钮（规划书 §6.4 / §6.5）。
///
/// 它们决定"这条帖子会被怎么对待"——是用户自己安排别人怎么回应自己，
/// 这件事本身就值得在发布页上被看见一次。
library;

/// 回复频率：低 / 中 / 高 / 自动。
enum ReplyDensity {
  low('低'),
  medium('中'),
  high('高'),
  auto('自动');

  const ReplyDensity(this.label);
  final String label;

  /// 参与互动的人格数量区间。
  (int, int) get personaRange => switch (this) {
    ReplyDensity.low => (1, 3),
    ReplyDensity.medium => (3, 6),
    ReplyDensity.high => (7, 10),
    // 自动：交给内容判断，阶段 A 取中间偏上
    ReplyDensity.auto => (4, 8),
  };

  static ReplyDensity fromLabel(String? label) => values.firstWhere(
    (value) => value.label == label,
    orElse: () => ReplyDensity.medium,
  );
}

/// 点赞量：低 / 中 / 高 / 自动。
enum LikeLevel {
  low('低'),
  medium('中'),
  high('高'),
  auto('自动');

  const LikeLevel(this.label);
  final String label;

  /// 点赞总量的区间（规划书 §6.4 的表格）。
  (int, int) get totalRange => switch (this) {
    LikeLevel.low => (5, 15),
    LikeLevel.medium => (15, 40),
    LikeLevel.high => (40, 100),
    LikeLevel.auto => (20, 60),
  };

  static LikeLevel fromLabel(String? label) => values.firstWhere(
    (value) => value.label == label,
    orElse: () => LikeLevel.medium,
  );
}

/// AI 拟人程度：1 官方助手 → 5 戏精人格（规划书 §6.5）。
///
/// 档位越高：越口语、越可能连续追问、越可能出现语音。
class HumanLevel {
  const HumanLevel(this.value);

  final int value;

  /// 目前档位只被记录在帖子上（`posts.human_level`），还没有驱动行为。
  ///
  /// 原计划让它决定"追问概率"和"语音概率"，但两件事都要等阶段 B：
  /// - 追问需要**楼中楼**（同一个人格发两条并列评论会立刻暴露 AI 身份）
  /// - 语音需要 TTS 音色，否则评论区会出现"有波形没声音"的假语音条
  /// 所以这里先保留档位本身，不摆出用不上的概率参数。
  static HumanLevel fromValue(int? value) =>
      HumanLevel((value ?? 3).clamp(1, 5));
}

/// 一条帖子发布时的回响设置快照。
class EchoSettings {
  const EchoSettings({
    this.density = ReplyDensity.medium,
    this.likeLevel = LikeLevel.medium,
    this.humanLevel = const HumanLevel(3),
  });

  final ReplyDensity density;
  final LikeLevel likeLevel;
  final HumanLevel humanLevel;

  static const EchoSettings defaults = EchoSettings();
}
