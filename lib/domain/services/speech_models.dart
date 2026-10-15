import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 把随包发布的语音模型释放到应用目录（B8）。
///
/// 推理引擎要的是**文件路径**，而打进 APK 的模型住在 assets 里，
/// 只能先复制出来一次。所以这里做的是"首次运行时把大文件搬运到磁盘"，
/// 之后每次启动只核对一遍大小就放行——搬几十兆不该是每次开屏的代价。
///
/// 模型不进 git 仓库（见 `.gitignore`）：几十兆的二进制会毁掉克隆体验，
/// 仓库里给的是下载说明，`assets/models/` 里的文件由开发者自己放。
class SpeechModelStore {
  SpeechModelStore();

  static const String _ttsAssetDir = 'assets/models/tts';

  /// 合成语音要的文件。
  ///
  /// `date.fst` / `number.fst` / `phone.fst` 是文本正则化用的：
  /// 中文模型自己认字，但"3 月 24 日"这种得靠它们念对。
  static const List<String> _ttsFiles = [
    'model.onnx',
    'lexicon.txt',
    'tokens.txt',
    'speakers.txt',
    'date.fst',
    'number.fst',
    'phone.fst',
  ];

  ReleasedModels? _tts;

  /// 合成模型的目录。已经释放过就直接返回。
  Future<ReleasedModels> prepareTts() async {
    return _tts ??= await _release('tts', _ttsAssetDir, _ttsFiles);
  }

  Future<ReleasedModels> _release(
    String kind,
    String assetDir,
    List<String> names,
  ) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'speech_models', kind));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    for (final name in names) {
      final asset = await rootBundle.load('$assetDir/$name');
      final target = File(p.join(dir.path, name));
      // 大小一致就当它是最新的：这几个文件一旦换版本，体积几乎必然变化，
      // 而逐字节校验 110MB 的收益抵不上开机时那一下卡顿。
      if (target.existsSync() &&
          await target.length() == asset.lengthInBytes) {
        continue;
      }
      await target.writeAsBytes(
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
        flush: true,
      );
    }

    return ReleasedModels(
      directory: dir.path,
      pathOf: (name) => p.join(dir.path, name),
    );
  }
}

/// 模型释放的共享实例：多处取路径都从它拿，免得同一批文件被搬运两遍。
final speechModelStoreProvider = Provider<SpeechModelStore>(
  (ref) => SpeechModelStore(),
);

/// 一次释放的结果：模型所在目录，以及按名字取路径的小工具。
class ReleasedModels {
  const ReleasedModels({required this.directory, required this.pathOf});

  final String directory;
  final String Function(String name) pathOf;
}
