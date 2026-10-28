/// 固定住民给自己定的一个闹钟（v4.0）。
///
/// 它是一次性的：到点被消费之后不再重复。住户可以用它决定
/// “下一次什么时候醒来”，而不是只能等心跳的 1.5 小时空闲间隔。
class ResidentAlarm {
  const ResidentAlarm({
    required this.id,
    required this.residentId,
    required this.fireAt,
    this.reason = '',
    required this.createdAt,
    this.firedAt,
    this.cancelledAt,
  });

  final String id;
  final String residentId;
  final DateTime fireAt;

  /// 定的时候想做的事，醒来时随“现在”一起交给它。
  final String reason;
  final DateTime createdAt;
  final DateTime? firedAt;
  final DateTime? cancelledAt;

  bool get isPending => firedAt == null && cancelledAt == null;
  bool get isDue => isPending && !fireAt.isAfter(DateTime.now());
}
