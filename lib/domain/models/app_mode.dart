/// 应用的两种模式（规划书 §2）。
///
/// 单 App 双模式是这个产品的核心机制，所以模式本身是领域概念，
/// 不是 UI 状态——所有涉及数据读写的地方都要先问清楚当前模式。
enum AppMode {
  /// 回响模式：AI 虚拟网友的点赞、评论、语音，完整虚拟社区。
  echo,

  /// 清醒模式：关闭虚拟反馈，只保留客观分析与真实记录。
  clear;

  bool get isEcho => this == AppMode.echo;
  bool get isClear => this == AppMode.clear;

  String get label => switch (this) {
    AppMode.echo => '回响模式',
    AppMode.clear => '清醒模式',
  };

  String get tagline => switch (this) {
    AppMode.echo => '被看见的感觉，来得比想象中快',
    AppMode.clear => '只有客观描述，没有人为你打分',
  };

  /// 数据库 `scope` 字段的取值来源（规划书 §2.4.3）。
  String get scope => switch (this) {
    AppMode.echo => 'echo',
    AppMode.clear => 'clear',
  };

  AppMode get opposite => this == AppMode.echo ? AppMode.clear : AppMode.echo;

  static AppMode fromScope(String? scope) =>
      scope == 'clear' ? AppMode.clear : AppMode.echo;
}
