/// 固定住民的一段睡眠（v50）。
///
/// 睡眠不是“关掉这个人”，而是让 TA 停下来歇一会儿：
/// 五天没有任何互动会自动入睡；用户也可以从睡眠页手动让 TA 睡。
/// 无论是哪一种，日志里都会留下 `startedAt → endedAt`。
/// 唤醒时告诉住民“你睡了多久”。
///
/// 两种情况位置不同：用户从睡眠页手动唤醒时，把它放在待办清单**最后**；
/// 用户直接发私信/找 TA 时，放在这一轮消息的**最前面**。
class SleepWakeNotice {
  const SleepWakeNotice({
    required this.sleptFrom,
    required this.wokeAt,
    required this.manual,
  });

  final DateTime sleptFrom;
  final DateTime wokeAt;

  /// true = 用户从睡眠页唤醒；false = 用户直接找 TA 时被唤醒。
  final bool manual;

  Duration get duration => wokeAt.difference(sleptFrom);

  String get timingLabel =>
      '你从「${_when(sleptFrom)}」睡到了现在（${durationLabel(duration)}）';

  String get manualLine => '$timingLabel，现在醒了。说点什么吧。';

  String get interactionLine =>
      '$timingLabel，现在被对方叫醒了。先看看对方说了什么，再自然地接上；'
      '不要提“睡眠功能”，也不要把这句话原样复述出来。';

  static String _when(DateTime at) {
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '${at.year}年${at.month}月${at.day}日 $hh:$mm';
  }

  static String durationLabel(Duration span) {
    if (span.inDays > 0) {
      final hours = span.inHours % 24;
      return hours == 0
          ? '共 ${span.inDays} 天'
          : '共 ${span.inDays} 天 $hours 小时';
    }
    if (span.inHours > 0) {
      final minutes = span.inMinutes % 60;
      return minutes == 0
          ? '共 ${span.inHours} 小时'
          : '共 ${span.inHours} 小时 $minutes 分钟';
    }
    return span.inMinutes <= 0 ? '不到 1 分钟' : '共 ${span.inMinutes} 分钟';
  }
}

class ResidentSleepPeriod {
  const ResidentSleepPeriod({
    required this.id,
    required this.residentId,
    required this.startedAt,
    required this.startedBy,
    this.endedAt,
    this.endedBy = '',
    this.farewell = '',
  });

  final String id;
  final String residentId;
  final DateTime startedAt;

  /// 空 = 现在还在睡。
  final DateTime? endedAt;

  /// manual / auto
  final String startedBy;

  /// manual / interaction
  final String endedBy;

  /// 入睡前留下的最后一句话。
  final String farewell;

  bool get isSleeping => endedAt == null;

  Duration get duration =>
      (endedAt ?? DateTime.now()).difference(startedAt);

  String get startedByLabel => switch (startedBy) {
    'auto' => '五天没有互动，自动入睡',
    'manual' => '用户让 TA 睡一会儿',
    _ => startedBy,
  };

  String get endedByLabel => switch (endedBy) {
    'manual' => '用户从睡眠页唤醒',
    'interaction' => '用户主动找 TA，被唤醒',
    _ => '',
  };
}
