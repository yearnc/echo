/// 私信气泡下方那行时间。
///
/// 列表里用相对时间（“3 分钟前”）是为了让信息流看起来在流动；
/// 一对一聊天里每一句的**具体时刻**更重要——“你昨晚说的”和“你刚说的”
/// 对读的人来说是两件事。
String formatMessageTime(DateTime at) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final hh = at.hour.toString().padLeft(2, '0');
  final mm = at.minute.toString().padLeft(2, '0');
  final clock = '$hh:$mm';

  final diff = today.difference(day).inDays;
  if (diff == 0) return clock;
  if (diff == 1) return '昨天 $clock';
  if (diff < 7) return '周${_weekday(at.weekday)} $clock';
  if (at.year == now.year) return '${at.month}月${at.day}日 $clock';
  return '${at.year}年${at.month}月${at.day}日 $clock';
}

String _weekday(int weekday) => switch (weekday) {
  1 => '一',
  2 => '二',
  3 => '三',
  4 => '四',
  5 => '五',
  6 => '六',
  _ => '日',
};
