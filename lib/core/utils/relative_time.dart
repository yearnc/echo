/// 相对时间格式化。
///
/// 不用 `intl` 的 RelativeDateTimeFormatter，是因为中文社交产品的语气
/// 有自己的习惯（"刚刚 / 3分钟前 / 昨天 20:14"），而 `intl` 的输出偏书面。
class RelativeTime {
  const RelativeTime._();

  static String format(DateTime time, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final diff = current.difference(time);

    if (diff.isNegative) return '刚刚';
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24 && current.day == time.day) {
      return '${diff.inHours}小时前';
    }

    final yesterday = current.subtract(const Duration(days: 1));
    if (time.year == yesterday.year &&
        time.month == yesterday.month &&
        time.day == yesterday.day) {
      return '昨天 ${_hm(time)}';
    }

    if (current.year == time.year) {
      return '${time.month}月${time.day}日 ${_hm(time)}';
    }
    return '${time.year}年${time.month}月${time.day}日';
  }

  /// 通知、列表右侧用的短格式：只在几分钟内用相对时间，其余直接给时刻。
  static String short(DateTime time, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final diff = current.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24 && current.day == time.day) {
      return '${diff.inHours}小时前';
    }
    if (current.year == time.year) return '${time.month}/${time.day}';
    return '${time.year}/${time.month}/${time.day}';
  }

  static String _hm(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}
