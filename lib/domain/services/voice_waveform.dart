import 'dart:math' as math;
import 'dart:typed_data';

/// 语音条的波形与时长（B8）。
///
/// 阶段 A 那排竖条是画上去的（按 `i % 5` 算高度，跟音频没关系）。
/// 真语音有了之后，波形就该是这段声音本身——用户扫一眼能看出
/// "前面说话、中间停顿、后面又说了"，而不是一张装饰图。
///
/// 纯函数，不碰文件也不碰引擎，好测。
class VoiceWaveform {
  const VoiceWaveform._();

  /// 气泡上画几根柱子。跟阶段 A 的宽度对齐，不用改版式。
  static const int defaultBars = 22;

  /// 最矮的一根也有这么高，免得安静段落看起来像"这里没数据"。
  static const double _minBar = 0.12;

  /// 从 PCM 采样里抽柱子：每根取这一段的峰值，最后整排归一化到 0—1。
  static List<double> bars(Float32List samples, {int count = defaultBars}) {
    if (samples.isEmpty || count <= 0) return const [];

    final raw = <double>[];
    final step = samples.length / count;
    var peak = 0.0;

    for (var i = 0; i < count; i++) {
      final start = (i * step).floor();
      final end = math.min(((i + 1) * step).ceil(), samples.length);
      var local = 0.0;
      for (var j = start; j < end; j++) {
        final value = samples[j].abs();
        if (value > local) local = value;
      }
      raw.add(local);
      if (local > peak) peak = local;
    }

    if (peak <= 0) return List<double>.filled(count, _minBar);
    return [
      for (final value in raw) math.max(_minBar, value / peak),
    ];
  }

  /// 时长（毫秒）。按采样点数算，不是按字符数估——
  /// 语音条上那个秒数就该是它播出来有多长。
  static int durationMs(int sampleCount, int sampleRate) {
    if (sampleRate <= 0 || sampleCount <= 0) return 0;
    return (sampleCount * 1000 / sampleRate).round();
  }
}
