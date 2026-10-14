/// 心理安全与防沉迷的三个开关（规划书 §6.9 / §13）。
///
/// 都**默认开启保护**：防沉迷提醒默认开、阈值默认 8 次。理由是这类设置
/// 一旦默认关闭，就只有已经警觉的人才会去打开它，而需要它的人不会。
library;

class SafetySettings {
  const SafetySettings({
    this.addictionGuard = true,
    this.coolDownMode = false,
    this.feedbackViewThreshold = 8,
    this.minorProtection = false,
  });

  /// 防沉迷提醒总开关（规划书 §13「防沉迷默认开启」）。
  final bool addictionGuard;

  /// 冷静模式：开启后新到的点赞与评论延迟显示（规划书 §6.9）。
  final bool coolDownMode;

  /// 连续查看反馈多少次后弹一次提醒。
  final int feedbackViewThreshold;

  /// 未成年人保护（规划书 §6.10 / §13）。
  ///
  /// 它不是"切模式时那个勾选"的重复：那个是一次性的自我声明，
  /// 这个是**长期锁**——打开之后，回响模式的任何入口都不通；
  /// 而勾选那一步每次都要重来，正好留给"临时借用手机"这类场景。
  final bool minorProtection;

  SafetySettings copyWith({
    bool? addictionGuard,
    bool? coolDownMode,
    int? feedbackViewThreshold,
    bool? minorProtection,
  }) => SafetySettings(
    addictionGuard: addictionGuard ?? this.addictionGuard,
    coolDownMode: coolDownMode ?? this.coolDownMode,
    feedbackViewThreshold: feedbackViewThreshold ?? this.feedbackViewThreshold,
    minorProtection: minorProtection ?? this.minorProtection,
  );
}
