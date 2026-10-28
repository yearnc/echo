import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 录一段话，给本机语音识别用（v4.0）。
///
/// 统一录成 16kHz / 16-bit / 单声道 wav：SenseVoice 吃 16k，
/// wav 又不需要解码器，识别和气泡播放都用同一份文件。
class VoiceRecorder {
  VoiceRecorder();

  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _startedAt;
  String? _path;

  /// 最短有效录音：太短多半是误触，不送去识别。
  static const Duration minDuration = Duration(milliseconds: 600);

  /// 最长一句话。再长就不像“发一条语音”，也会让识别等太久。
  static const Duration maxDuration = Duration(seconds: 60);

  bool get isRecording => _startedAt != null;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// 开始录音。返回 false 表示没有麦克风权限。
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    await _recorder.cancel();
    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'echo_voice_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    _startedAt = DateTime.now();
    _path = path;
    return true;
  }

  /// 停止并返回录音。太短会删掉文件并返回 null。
  Future<({String path, int durationMs})?> stop() async {
    final started = _startedAt;
    _startedAt = null;
    _path = null;
    final path = await _recorder.stop();
    if (started == null || path == null) return null;

    final duration = DateTime.now().difference(started);
    if (duration < minDuration) {
      await _deleteQuietly(path);
      return null;
    }
    return (
      path: path,
      durationMs: duration.inMilliseconds.clamp(0, maxDuration.inMilliseconds),
    );
  }

  /// 上滑/点取消：不留文件。
  Future<void> cancel() async {
    final path = _path;
    _startedAt = null;
    _path = null;
    await _recorder.cancel();
    if (path != null) await _deleteQuietly(path);
  }

  Future<void> dispose() => _recorder.dispose();

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 临时文件删不掉不影响主流程，系统迟早会清。
    }
  }
}
