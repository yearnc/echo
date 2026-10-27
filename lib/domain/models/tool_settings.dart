/// 固定住民一次唤醒里能用多少工具、最多跑多久（v41）。
///
/// 这两项以前写死在 [ResidentToolSession] 里（8 轮 / 20 秒）。写死的问题是
/// 模型一慢就什么都做不完：查记忆、回评论、发私信挤在二十秒里，
/// 最后只能草草收一句。放宽默认值，也允许用户自己调——
/// 调大更慢但做得更完整，调小更省钱。
class ToolSettings {
  const ToolSettings({this.maxRounds = 12, this.timeoutSeconds = 30});

  /// 一次唤醒最多几轮“模型 → 工具 → 模型”。
  final int maxRounds;

  /// 一次唤醒的总超时（秒）。
  final int timeoutSeconds;

  Duration get timeout => Duration(seconds: timeoutSeconds);

  /// 有语音工具时额外给的时间：云端合成一句话可能要几十秒。
  Duration get voiceTimeout => Duration(seconds: timeoutSeconds + 60);

  static const ToolSettings defaults = ToolSettings();

  static const int minRounds = 4;
  static const int maxRoundsLimit = 30;
  static const int minTimeoutSeconds = 10;
  static const int maxTimeoutSeconds = 180;

  /// 每轮单次请求的上限。总超时再长，也不该让一次请求无限挂着。
  Duration get perCallTimeout => const Duration(seconds: 20);

  ToolSettings copyWith({int? maxRounds, int? timeoutSeconds}) => ToolSettings(
    maxRounds: (maxRounds ?? this.maxRounds).clamp(minRounds, maxRoundsLimit),
    timeoutSeconds: (timeoutSeconds ?? this.timeoutSeconds).clamp(
      minTimeoutSeconds,
      maxTimeoutSeconds,
    ),
  );
}
