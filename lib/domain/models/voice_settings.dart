/// 住民语音的全局设置。
///
/// 两件事分开：**要不要说话**（开关）和**用谁的嗓子**（本机 / 云端）。
/// 开关关掉之后，已经生成的语音条照常能播，只是不再生成新的——
/// 那才是"关掉语音"该有的样子，而不是把历史记录一起吞掉。
enum VoiceSource {
  local('本机'),
  cloud('云端');

  const VoiceSource(this.label);

  final String label;

  String get key => name;

  static VoiceSource fromKey(String? raw) => switch (raw) {
    'cloud' => VoiceSource.cloud,
    _ => VoiceSource.local,
  };
}

class VoiceSettings {
  const VoiceSettings({this.enabled = true, this.source = VoiceSource.local});

  /// 是否自动生成新的语音评论。
  final bool enabled;

  /// 优先用哪条路合成。云端没配置时，实际会退回本机。
  final VoiceSource source;

  VoiceSettings copyWith({bool? enabled, VoiceSource? source}) => VoiceSettings(
    enabled: enabled ?? this.enabled,
    source: source ?? this.source,
  );
}
