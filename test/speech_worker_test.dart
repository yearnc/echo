import 'dart:convert';
import 'dart:io';

import 'package:echo/domain/services/speech_runtime.dart';
import 'package:echo/domain/services/speech_worker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

/// 本机模型不进 git：没有模型的环境直接跳过，不让别人 clone 下来就红。
void main() {
  final root = Directory.current.path;
  final modelDir = p.join(root, 'assets', 'models', 'tts');
  final hasModel = File(p.join(modelDir, 'model.onnx')).existsSync();

  test(
    '本机合成在后台 isolate 里跑完，不阻塞调用方',
    () async {
      final out = File(
        p.join(Directory.systemTemp.path, 'echo_worker_test.wav'),
      );
      addTearDown(() {
        if (out.existsSync()) out.deleteSync();
      });

      final reply = await SpeechWorker.instance.synthesize(
        SpeechWorkerRequest(
          kind: 'vits',
          text: '你好，我是小满。',
          outputPath: out.path,
          files: {
            'model': p.join(modelDir, 'model.onnx'),
            'lexicon': p.join(modelDir, 'lexicon.txt'),
            'tokens': p.join(modelDir, 'tokens.txt'),
            'date': p.join(modelDir, 'date.fst'),
            'number': p.join(modelDir, 'number.fst'),
            'phone': p.join(modelDir, 'phone.fst'),
          },
          sid: 0,
          speed: 1.0,
          // flutter test 里 resolveSherpaOnnxPathSync() 拿不到包路径，
          // 直接读 package_config 找到 sherpa_onnx_windows。
          libraryPath:
              SpeechRuntime.resolveLibraryPath() ?? _windowsPackageDir(root),
        ),
      );

      expect(reply.ok, isTrue, reason: reply.error);
      expect(out.existsSync(), isTrue);
      expect(reply.durationMs, greaterThan(300));
      expect(reply.waveform, isNotEmpty);
    },
    skip: hasModel ? false : '本机没有 assets/models/tts（模型不进仓库）',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// 测试环境专用：从 package_config 找 sherpa_onnx_windows 的 windows 目录。
String? _windowsPackageDir(String root) {
  try {
    final config = File(
      p.join(root, '.dart_tool', 'package_config.json'),
    );
    final decoded =
        jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
    final packages = decoded['packages'];
    if (packages is! List) return null;
    for (final item in packages) {
      if (item is! Map || item['name'] != 'sherpa_onnx_windows') continue;
      final uri = Uri.parse(item['rootUri'] as String);
      return p.join(uri.toFilePath(), 'windows');
    }
  } catch (_) {
    return null;
  }
  return null;
}
