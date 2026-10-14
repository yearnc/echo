import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/voice_waveform.dart';

/// 从落盘的 wav 里取波形（B8）。
///
/// 波形**不存数据库**：它是音频的一个视图，存下来就得跟着音频一起维护，
/// 还得为它加列、加迁移。而 wav 就在本地，读一遍采样点算峰值是毫秒级的事，
/// 算完缓存进内存，同一条语音在列表里来回滚动也不会重算。
class VoiceWaveStore {
  VoiceWaveStore();

  final Map<String, List<double>> _cache = {};

  /// 文件读不出来时画等高的柱子：气泡还在，只是看不出起伏——
  /// 比整个语音条消失好得多（那会让人以为评论没了）。
  static const double _fallbackBar = 0.35;

  Future<List<double>> load(String ref) async {
    final cached = _cache[ref];
    if (cached != null) return cached;

    List<double> bars;
    try {
      bars = VoiceWaveform.bars(await _pcmOf(ref));
      if (bars.isEmpty) {
        bars = List<double>.filled(VoiceWaveform.defaultBars, _fallbackBar);
      }
    } catch (_) {
      bars = List<double>.filled(VoiceWaveform.defaultBars, _fallbackBar);
    }

    _cache[ref] = bars;
    return bars;
  }

  /// 读 WAV（16 位 PCM）里的采样点。
  ///
  /// 只需要认自家合成引擎写出来的那种格式：mono / 16 位 / 小端。
  /// 认不出来就抛异常，由 [load] 落回等高柱子。
  static Future<Float32List> _pcmOf(String ref) async {
    final path = ref.startsWith('file:') ? ref.substring('file:'.length) : ref;
    final bytes = await File(path).readAsBytes();
    if (bytes.length < 44) throw const FormatException('不是完整的 wav');

    final header = ByteData.sublistView(bytes);
    var offset = 12;
    var dataStart = -1;
    var dataSize = 0;

    // RIFF 是一串 chunk，`data` 那个里面才是采样点。
    while (offset + 8 <= bytes.length) {
      final tag = String.fromCharCodes(bytes, offset, offset + 4);
      final size = header.getUint32(offset + 4, Endian.little);
      if (tag == 'data') {
        dataStart = offset + 8;
        dataSize = size;
        break;
      }
      // chunk 按偶数字节对齐，奇数大小后面会垫一个字节。
      offset += 8 + size + (size.isOdd ? 1 : 0);
    }

    if (dataStart < 0 || dataStart >= bytes.length) {
      throw const FormatException('wav 里没有 data 段');
    }
    final end = (dataStart + dataSize).clamp(dataStart, bytes.length);

    final samples = Float32List((end - dataStart) ~/ 2);
    final body = ByteData.sublistView(bytes, dataStart, end);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = body.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }
}

final voiceWaveStoreProvider = Provider<VoiceWaveStore>(
  (ref) => VoiceWaveStore(),
);
