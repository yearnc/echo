/// 给模型看的时间标签：年月日、周几、时段、24 小时制精确到分钟。
///
/// 住民的对话记录、持久上下文时间线和工具结果必须用**同一份**格式：
/// 两套格式混着用，模型就分不清哪种方括号是“系统标注的发送时间”，
/// 会把它当成正文照着复读（v4.6.1 真机问题：私信里冒出
/// 「[10月30日 21:32] 你：…」）。
String agentTimeLabel(DateTime at) {
  final phase = switch (at.hour) {
    >= 5 && < 8 => '清晨',
    >= 8 && < 11 => '上午',
    >= 11 && < 14 => '中午',
    >= 14 && < 17 => '下午',
    >= 17 && < 19 => '傍晚',
    >= 19 && < 23 => '晚上',
    _ => '深夜',
  };
  final hh = at.hour.toString().padLeft(2, '0');
  final mm = at.minute.toString().padLeft(2, '0');
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  final week = weekdays[at.weekday - 1];
  return '${at.year}年${at.month}月${at.day}日 周$week $phase $hh:$mm';
}
