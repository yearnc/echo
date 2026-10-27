import 'dart:typed_data';

/// 从 wav 里读 PCM，给气泡算时长和波形用。
///
/// 只需要单声道浮点采样，不追求把整份 wav 解析器写完：
/// 44.1kHz / 16-bit PCM 的 wav 是常见格式；解析失败就返回 null，
/// 调用方按“不知道时长”处理，不影响播放。
///
/// 这里同时被前台（解析云端返回的 wav）和语音 worker isolate
/// （解析参考音频）用到，所以单独放一份。
class WavPcm {
  const WavPcm({required this.samples, required this.sampleRate});

  final Float32List samples;
  final int sampleRate;

  static WavPcm? tryParse(Uint8List bytes) {
    if (bytes.length < 44) return null;
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    var pos = 12;
    int? sampleRate;
    int? channels;
    int? bits;
    Float32List? pcm;

    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = data.getUint32(pos + 4, Endian.little);
      final start = pos + 8;
      if (start + size > bytes.length && id != 'data') break;

      if (id == 'fmt ' && size >= 16) {
        final format = data.getUint16(start, Endian.little);
        channels = data.getUint16(start + 2, Endian.little);
        sampleRate = data.getUint32(start + 4, Endian.little);
        bits = data.getUint16(start + 14, Endian.little);
        // 只认整数 PCM；float32 的 wav 让播放层自己处理。
        if (format != 1) return null;
      } else if (id == 'data') {
        if (sampleRate == null || channels == null || bits == null) return null;
        final available = (bytes.length - start).clamp(0, size);
        if (bits == 16) {
          final frames = available ~/ (2 * channels);
          if (frames <= 0) return null;
          final samples = Float32List(frames);
          var read = start;
          for (var i = 0; i < frames; i++) {
            var sum = 0.0;
            for (var c = 0; c < channels; c++) {
              sum += data.getInt16(read, Endian.little) / 32768.0;
              read += 2;
            }
            samples[i] = sum / channels;
          }
          pcm = samples;
        } else if (bits == 8) {
          final frames = available ~/ channels;
          if (frames <= 0) return null;
          final samples = Float32List(frames);
          var read = start;
          for (var i = 0; i < frames; i++) {
            var sum = 0.0;
            for (var c = 0; c < channels; c++) {
              sum += (bytes[read] - 128) / 128.0;
              read++;
            }
            samples[i] = sum / channels;
          }
          pcm = samples;
        } else {
          return null;
        }
        break;
      }
      pos = start + size + (size.isOdd ? 1 : 0);
    }

    if (pcm == null || sampleRate == null || sampleRate <= 0) return null;
    return WavPcm(samples: pcm, sampleRate: sampleRate);
  }
}
