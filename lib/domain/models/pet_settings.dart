/// 桌宠设置（v4.0）。
class PetSettings {
  const PetSettings({
    this.enabled = false,
    this.defaultResidentId = '',
    this.intervalMs = 1000,
    this.realtime = false,
    this.realtimeFrames = 3,
    this.realtimeGapSeconds = 20,
    this.voiceEnabled = false,
    this.translucent = true,
  });

  final bool enabled;

  /// 不在任何时段里时由谁控制。
  final String defaultResidentId;

  /// 实时模式的截屏间隔：500 / 1000 毫秒。
  final int intervalMs;

  /// 实时模式：持续截屏 + 持续唤醒。默认关，开启前要确认 token 成本。
  final bool realtime;

  /// 每次唤醒附几张画面（从这段间隔里均匀抽，不是只拿最后几张）。
  final int realtimeFrames;

  /// 实时模式两次观察之间隔多少秒。
  final int realtimeGapSeconds;

  /// 截屏间隔不再单独设置：用“观察间隔 ÷ 每次带几张”算出来，
  /// 这样每张截图都会落在一次观察的窗口里，不做无用功。
  int get captureIntervalMs {
    final frames = realtimeFrames.clamp(1, 6);
    final ms = (realtimeGapSeconds * 1000 / frames).round();
    return ms.clamp(400, 60000);
  }

  /// 通话里住民要不要出声（P4 用；默认只发文字）。
  final bool voiceEnabled;

  /// 角色身体是不是半透明（能隐约看到后面的背景）。默认开，
  /// 也就是现在这一版看起来的样子；关掉后整只完全不透明。
  final bool translucent;

  PetSettings copyWith({
    bool? enabled,
    String? defaultResidentId,
    int? intervalMs,
    bool? realtime,
    int? realtimeFrames,
    int? realtimeGapSeconds,
    bool? voiceEnabled,
    bool? translucent,
  }) => PetSettings(
    enabled: enabled ?? this.enabled,
    defaultResidentId: defaultResidentId ?? this.defaultResidentId,
    intervalMs: intervalMs ?? this.intervalMs,
    realtime: realtime ?? this.realtime,
    realtimeFrames: realtimeFrames ?? this.realtimeFrames,
    realtimeGapSeconds: realtimeGapSeconds ?? this.realtimeGapSeconds,
    voiceEnabled: voiceEnabled ?? this.voiceEnabled,
    translucent: translucent ?? this.translucent,
  );
}

/// 一段由某位固定住民控制桌宠的时间（本地分钟，0—1439）。
///
/// `startMinute > endMinute` 表示跨过零点；`covers` 两个方向都认。
class PetShift {
  const PetShift({
    required this.id,
    required this.residentId,
    required this.startMinute,
    required this.endMinute,
  });

  final String id;
  final String residentId;
  final int startMinute;
  final int endMinute;

  bool covers(int minute) {
    if (startMinute == endMinute) return false;
    if (startMinute < endMinute) {
      return minute >= startMinute && minute < endMinute;
    }
    return minute >= startMinute || minute < endMinute;
  }

  static String clock(int minute) {
    final normalized = ((minute % 1440) + 1440) % 1440;
    final hh = (normalized ~/ 60).toString().padLeft(2, '0');
    final mm = (normalized % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String get label => '${clock(startMinute)}—${clock(endMinute)}';
}
