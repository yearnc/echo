import '../../domain/models/demo_script.dart';

/// 时间轴推进器：纯逻辑，不碰 UI、不碰计时器。
///
/// 拆出来是为了能直接单测——"第 7 秒该发生什么"这种事
/// 不应该只能靠眼睛盯着屏幕看。
class DemoTimeline {
  DemoTimeline(List<DemoStep> steps) : _steps = List.unmodifiable(steps);

  final List<DemoStep> _steps;
  int _cursor = 0;

  int get total => _steps.length;
  int get cursor => _cursor;
  bool get isFinished => _cursor >= _steps.length;

  List<DemoStep> get steps => _steps;

  /// 返回到 [elapsedMs] 为止新到期的动作（可能一次多个）。
  List<DemoStep> advanceTo(int elapsedMs) {
    final due = <DemoStep>[];
    while (_cursor < _steps.length && _steps[_cursor].atMs <= elapsedMs) {
      due.add(_steps[_cursor]);
      _cursor++;
    }
    return due;
  }

  /// 单步：手动放出下一个动作（拍摄时想逐个确认镜头用）。
  DemoStep? stepOnce() {
    if (isFinished) return null;
    final step = _steps[_cursor];
    _cursor++;
    return step;
  }

  /// 下一个动作的时间点，用于"单步"后同步时钟。
  int? get nextAtMs => isFinished ? null : _steps[_cursor].atMs;

  void reset() => _cursor = 0;

  /// 进度 0..1，供进度条使用。
  double progressAt(int elapsedMs) {
    if (_steps.isEmpty) return 1;
    final last = _steps.last.atMs;
    if (last == 0) return 1;
    return (elapsedMs / last).clamp(0.0, 1.0);
  }
}
