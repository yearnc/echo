import 'dart:ffi';
import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// 离线语音运行时（B8）。
///
/// 语音合成用的原生库，进程里初始化一次就够——
/// 每建一个引擎就重复初始化，DLL 会被加载好几遍。
class SpeechRuntime {
  SpeechRuntime._();

  static bool _ready = false;

  /// 确保原生库已加载。可以在任意线程安全地多调几次。
  static void ensure() {
    if (_ready) return;
    _ready = true;
    _preheatOnWindows();
    sherpa.initBindings();
  }
}

/// Windows 上有一处坑：`System32` 里躺着一个旧版 `onnxruntime.dll`
/// （Windows 自带的组件在用），而 sherpa 的原生库依赖同名文件，
/// 隐式解析会先撞上系统那份，然后报 "requested API version [28] is not
/// available, only API versions [1, 17]"，接着整个进程崩掉。
///
/// 办法是先把**包里那份**按绝对路径加载进内存：同名模块已经在内存里，
/// 后面解析依赖时就直接复用它。必须在 [sherpa.initBindings] 之前做。
///
/// 桌面预览（exe 同目录优先）本来撞不上这个坑，但打包成正式应用时
/// 依赖顺序会变，所以无条件预加载，稳一点。
void _preheatOnWindows() {
  if (!Platform.isWindows) return;
  try {
    final packageDir = sherpa.resolveSherpaOnnxPathSync();
    if (packageDir == null) return;
    DynamicLibrary.open('$packageDir\\onnxruntime.dll');
  } catch (_) {
    // 预加载失败就照原样继续：真加载不了会在建引擎时报错，
    // 那条路径本来就被 try/catch 兜着（语音降级成纯文字）。
  }
}
