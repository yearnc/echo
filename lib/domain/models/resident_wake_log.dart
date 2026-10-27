/// 固定住民的一次醒来（v3.9）。
///
/// 这是给住民自己看的记录，也是「固定住民 ID 的日志」页的数据源：
/// 什么时候醒的、因为什么醒、醒了多久、有没有给下次的自己留话。
class ResidentWakeLog {
  const ResidentWakeLog({
    required this.id,
    required this.residentId,
    required this.trigger,
    required this.wokeAt,
    this.endedAt,
    this.note = '',
    this.noteAt,
  });

  final String id;
  final String residentId;

  /// user_action / heartbeat / background / setup
  final String trigger;
  final DateTime wokeAt;
  final DateTime? endedAt;

  /// 留给下一次醒来的自己的话。
  final String note;
  final DateTime? noteAt;

  bool get hasNote => note.trim().isNotEmpty;

  /// 触发方式的中文说法（日志页与工具结果共用一份）。
  String get triggerLabel => switch (trigger) {
    'user_action' => '有人叫了 TA',
    'heartbeat' => '自己醒来看看',
    'background' => '系统后台叫醒',
    'setup' => '刚住进来',
    _ => '醒来',
  };

  /// 这一轮醒着多久；还没结束就返回 null。
  Duration? get awakeFor {
    final end = endedAt;
    if (end == null) return null;
    final span = end.difference(wokeAt);
    return span.isNegative ? Duration.zero : span;
  }
}
