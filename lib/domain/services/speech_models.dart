import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 把随包发布的语音模型释放到应用目录（B8 / v3.8）。
///
/// 推理引擎要的是**文件路径**，而打进 APK 的模型住在 assets 里，
/// 只能先复制出来一次。所以这里做的是"首次运行时把大文件搬运到磁盘"，
/// 之后每次启动只核对一遍大小就放行——搬几百兆不该是每次开屏的代价。
///
/// v3.8 起有两套模型：
/// - `assets/models/tts/`：vits-zh-ll，5 个中文声线，给“仅文字描述”；
/// - `assets/models/zipvoice/`：ZipVoice INT8 + vocos 声码器，给参考音频克隆。
///
/// 模型不进 git 仓库（见 `.gitignore`）：几百兆的二进制会毁掉克隆体验，
/// 仓库里给的是下载说明，文件由开发者自己放。
class SpeechModelStore {
  SpeechModelStore();

  static const String _vitsAssetDir = 'assets/models/tts';
  static const String _zipVoiceAssetDir = 'assets/models/zipvoice';

  Future<ReleasedModels>? _vitsFuture;
  Future<ReleasedModels>? _zipVoiceFuture;

  /// 文字描述那套（vits-zh-ll）。
  ///
  /// 缓存的是 **Future** 而不是结果：启动预热和用户点语音可能同时调到这里，
  /// 缓结果的话两边都会开始搬同一批文件，互相把对方写了一半的文件覆盖掉。
  Future<ReleasedModels> prepareTts() {
    return _vitsFuture ??= _releaseDirectory('vits-zh-ll', _vitsAssetDir);
  }

  /// 克隆那套（ZipVoice + vocos 声码器）。
  Future<ReleasedModels> prepareZipVoice() {
    return _zipVoiceFuture ??= _prepareZipVoice();
  }

  Future<ReleasedModels> _prepareZipVoice() async {
    final models = await _releaseDirectory('zipvoice', _zipVoiceAssetDir);
    await _extractEspeakData(models);
    return models;
  }

  /// `espeak-ng-data` 是一个 355 个文件、带子目录的小文件树。
  ///
  /// Flutter 的目录式资源声明不会递归打包，所以它被压成一个 zip 随包；
  /// 这里只在目标目录还没有解压过时解开一次。
  Future<void> _extractEspeakData(ReleasedModels models) async {
    final target = Directory(models.pathOf('espeak-ng-data'));
    if (File(p.join(target.path, 'phondata')).existsSync()) return;

    final zip = File(models.pathOf('espeak-ng-data.zip'));
    if (!zip.existsSync()) {
      throw StateError('缺少 espeak-ng-data.zip');
    }
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final relative = p.normalize(entry.name);
      if (relative.startsWith('..') || p.isAbsolute(relative)) continue;
      final file = File(p.join(models.directory, relative));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.content, flush: true);
    }
  }

  /// 把一个 asset 目录整体搬运出来。
  ///
  /// 用 [AssetManifest] 列出目录里的所有文件，这样 espeak-ng-data 那种
  /// 几十个小文件、还带子目录的模型也能原样复制，不用手写清单。
  Future<ReleasedModels> _releaseDirectory(
    String kind,
    String assetDir,
  ) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'speech_models', kind));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final prefix = '$assetDir/';
    final assets = manifest
        .listAssets()
        .where((asset) => asset.startsWith(prefix))
        .toList(growable: false);

    for (final asset in assets) {
      final relative = asset.substring(prefix.length);
      if (relative.isEmpty) continue;
      final target = File(p.joinAll([dir.path, ...relative.split('/')]));
      final data = await rootBundle.load(asset);
      // 大小一致就当它是最新的：这几个文件一旦换版本，体积几乎必然变化，
      // 而逐字节校验几百兆的收益抵不上开机时那一下卡顿。
      if (target.existsSync() &&
          await target.length() == data.lengthInBytes) {
        continue;
      }
      await target.parent.create(recursive: true);
      await target.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
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
