/// 本次进程的启动时间。
///
/// 用于「使用时长」提示（规划书 §13）。阶段 A 不做系统级后台统计
/// （WorkManager / BGTaskScheduler 留到 B 阶段），进程内的时长已经够支撑
/// 那句温和的提醒——它的目的是让人抬头看一眼时间，不是做计时器。
library;

abstract final class AppSession {
  static DateTime? _startedAt;

  /// 在 `main()` 里调一次。重复调用不会覆盖首次的时间。
  static void markStarted() => _startedAt ??= DateTime.now();

  /// 取不到就现取——页面不该因为忘了初始化而崩。
  static DateTime get startedAt => _startedAt ??= DateTime.now();

  static Duration get elapsed => DateTime.now().difference(startedAt);

  /// 已经用了多少分钟（向上取整，1 分钟以内算 0）。
  static int get elapsedMinutes => elapsed.inMinutes;

  /// 超过这个时长就该提醒一句（规划书 §13「使用时长限制」）。
  static const int longSessionMinutes = 60;
}
