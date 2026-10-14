import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 录一段话（B8）。
///
/// 格式直接对齐识别模型要的：16 kHz、单声道、wav。
/// 让引擎自己去重采样是没必要的开销，而录音器本来就支持这么录。
class VoiceRecorder {
  VoiceRecorder();

  static const int sampleRate = 16000;

  final AudioRecorder _recorder = AudioRecorder();

  bool _active = false;
  String? _path;

  bool get isRecording => _active;

  /// 开始录。拿不到麦克风权限就返回 false。
  Future<bool> start() async {
    if (_active) return true;

    try {
      if (!await _recorder.hasPermission()) return false;

      final temp = await getTemporaryDirectory();
      final path = p.join(
        temp.path,
        'speech_${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: sampleRate,
          numChannels: 1,
        ),
        path: path,
      );
      _path = path;
      _active = true;
      return true;
    } catch (error) {
      debugPrint('[语音] 麦克风没能打开：$error');
      _active = false;
      return false;
    }
  }

  /// 停下来，返回录音文件路径。
  Future<String?> stop() async {
    if (!_active) return null;
    _active = false;
    try {
      final stopped = await _recorder.stop();
      // 有的平台 stop() 会给出真实路径，以它为准。
      return stopped ?? _path;
    } catch (error) {
      debugPrint('[语音] 录音没能正常结束：$error');
      return _path;
    }
  }

  Future<void> cancel() async {
    _active = false;
    try {
      await _recorder.cancel();
    } catch (_) {
      // 取消不掉也无所谓，文件在临时目录里，系统会清理。
    }
  }
}

final voiceRecorderProvider = Provider<VoiceRecorder>(
  (ref) {
    final recorder = VoiceRecorder();
    ref.onDispose(recorder.cancel);
    return recorder;
  },
);
