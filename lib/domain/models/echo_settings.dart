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
  ///
  /// 每档都给得比以前多一点：这里抽 6 个人，按各自 0.5 左右的开口率，
  /// 最后只落到 3 条评论——用户看到的"社区"就永远是两三条。数量先够，
  /// 像不像人再交给提示词和人格去管。
  (int, int) get personaRange => switch (this) {
    ReplyDensity.low => (2, 4),
    ReplyDensity.medium => (6, 10),
    ReplyDensity.high => (12, 18),
    // 自动：交给内容判断，阶段 A 取中间偏上。
    // 上限压在 10：12 个人选 12 个，熟人就"每条必到"了，一眼假。
    ReplyDensity.auto => (7, 10),
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
    this.density = ReplyDensity.auto,
    this.likeLevel = LikeLevel.auto,
    this.humanLevel = const HumanLevel(3),
  });

  final ReplyDensity density;
  final LikeLevel likeLevel;
  final HumanLevel humanLevel;

  static const EchoSettings defaults = EchoSettings();
}
