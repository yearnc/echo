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
    this.dailyLimitMinutes = 0,
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

  /// 清醒模式每日使用上限（分钟）。0 = 关闭。
  ///
  /// 这是用户自己给自己设的，不是产品强加的。到点只提醒一次，
  /// 不锁屏、不强制退出——“提醒”的目的是让人抬头看一眼。
  final int dailyLimitMinutes;

  bool get dailyLimitEnabled => dailyLimitMinutes > 0;

  SafetySettings copyWith({
    bool? addictionGuard,
    bool? coolDownMode,
    int? feedbackViewThreshold,
    bool? minorProtection,
    int? dailyLimitMinutes,
  }) => SafetySettings(
    addictionGuard: addictionGuard ?? this.addictionGuard,
    coolDownMode: coolDownMode ?? this.coolDownMode,
    feedbackViewThreshold: feedbackViewThreshold ?? this.feedbackViewThreshold,
    minorProtection: minorProtection ?? this.minorProtection,
    dailyLimitMinutes: dailyLimitMinutes ?? this.dailyLimitMinutes,
  );
}
