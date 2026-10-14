/// 数据看板的聚合逻辑（B9，规划书 §3.10）。
///
/// 这里只干一件事：把一串"什么时候发生了多少"变成能画出来的柱子。
/// 纯函数、不碰数据库——看板上的数字是给人看的，算错了没人看得出来，
/// 所以它必须能被测。
library;

/// 一次带时间的计数（一条互动、一条帖子……）。
typedef TimedCount = ({DateTime at, int value});

class DashboardStats {
  const DashboardStats._();

  /// 最近 [days] 天的每日总量，**最后一个是今天**。
  ///
  /// 窗口外的不算、将来的也不算：看板画的是已经发生的事。
  static List<int> dailyTotals(
    List<TimedCount> items, {
    int days = 7,
    DateTime? now,
  }) {
    final today = dayStart(now ?? DateTime.now());
    final totals = List<int>.filled(days, 0);

    for (final item in items) {
      final offset = today.difference(dayStart(item.at)).inDays;
      if (offset < 0 || offset >= days) continue;
      totals[days - 1 - offset] += item.value;
    }
    return totals;
  }

  /// 24 小时的分布，下标就是钟点。
  static List<int> hourlyTotals(List<DateTime> times) {
    final hours = List<int>.filled(24, 0);
    for (final time in times) {
      hours[time.hour] += 1;
    }
    return hours;
  }

  /// 最忙的那个钟点；一次都没有时返回 null。
  static int? busiestHour(List<int> hourly) {
    var best = -1;
    var bestValue = 0;
    for (var hour = 0; hour < hourly.length; hour++) {
      if (hourly[hour] > bestValue) {
        bestValue = hourly[hour];
        best = hour;
      }
    }
    return bestValue == 0 ? null : best;
  }

  /// 后半段相对前半段的变化（百分比）。
  ///
  /// 前半段是 0 时返回 null：从"没有"涨到"有几个"不是百分之多少，
  /// 那种话没法说，界面该说"刚开始有"。
  static int? growthPercent(List<int> daily) {
    if (daily.length < 2) return null;
    final half = daily.length ~/ 2;
    final previous = daily.take(half).fold<int>(0, (sum, v) => sum + v);
    final recent = daily.skip(half).fold<int>(0, (sum, v) => sum + v);
    if (previous == 0) return null;
    return ((recent - previous) / previous * 100).round();
  }

  /// 一天的零点。窗口切分统一按自然日，不按"过去 24 小时"——
  /// 用户心里的"今天"是日历上的今天。
  static DateTime dayStart(DateTime time) =>
      DateTime(time.year, time.month, time.day);

  /// 最近 [days] 天的日期（升序，最后一个是今天）。
  static List<DateTime> recentDays({int days = 7, DateTime? now}) {
    final today = dayStart(now ?? DateTime.now());
    return [
      for (var offset = days - 1; offset >= 0; offset--)
        today.subtract(Duration(days: offset)),
    ];
  }

  /// 星期几，用中文的一个字（图上位置小，写不下"星期一"）。
  static String weekdayLabel(DateTime day) =>
      const ['一', '二', '三', '四', '五', '六', '日'][day.weekday - 1];

  /// 高峰时段的说法："晚上 8 点"。
  static String hourLabel(int hour) {
    if (hour < 6) return '凌晨 $hour 点';
    if (hour < 12) return '上午 $hour 点';
    if (hour < 13) return '中午 $hour 点';
    if (hour < 18) return '下午 ${hour - 12} 点';
    return '晚上 ${hour - 12} 点';
  }
}
