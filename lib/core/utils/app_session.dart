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

  /// 当前这段前台会话是从什么时候开始的。
  ///
  /// 落库的会话只有在退出/切后台时才写；用户一直开着 APP 时，
  /// “今天用了多久”不能只算已经落库的那部分——否则到了一小时，
  /// 数字还停在昨天的 0。这里补上正在进行的这一段。
  static DateTime? _foregroundSince;

  static void markForeground() => _foregroundSince ??= DateTime.now();

  static void markBackground() => _foregroundSince = null;

  /// 正在进行的这段会话已经持续了多久（不在前台时为 0）。
  static Duration get foregroundElapsed {
    final start = _foregroundSince;
    if (start == null) return Duration.zero;
    final now = DateTime.now();
    return now.isAfter(start) ? now.difference(start) : Duration.zero;
  }

  /// 正在进行的这段会话里，属于**今天**的毫秒数。
  static int get foregroundMsToday {
    final start = _foregroundSince;
    if (start == null) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = start.isAfter(today) ? start : today;
    if (!now.isAfter(from)) return 0;
    return now.difference(from).inMilliseconds;
  }
}
