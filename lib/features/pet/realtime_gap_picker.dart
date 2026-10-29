import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/pet_settings.dart';

/// “20 秒”“1 分 20 秒”“10 分钟”——观察间隔在页面和滚轮上的统一写法。
String formatRealtimeGap(int seconds) {
  final value = seconds.clamp(
    PetSettings.minRealtimeGapSeconds,
    PetSettings.maxRealtimeGapSeconds,
  );
  final minutes = value ~/ 60;
  final rest = value % 60;
  if (minutes == 0) return '$rest 秒';
  if (rest == 0) return '$minutes 分钟';
  return '$minutes 分 $rest 秒';
}

/// 像定闹钟那样的双轮循环选择：分 0—10、秒 0/5/…/55（5 秒一格）。
///
/// 两个轮子都是首尾相接的，往上往下都能一直转。有效范围 10 秒—10 分钟：
/// 顶部实时显示最终会落到的时长，0:00 按 10 秒算，10 分 10 秒以上按 10 分钟算。
Future<int?> showRealtimeGapPicker(
  BuildContext context, {
  required int initialSeconds,
}) {
  var minutes = (initialSeconds.clamp(
        PetSettings.minRealtimeGapSeconds,
        PetSettings.maxRealtimeGapSeconds,
      ) ~/
      60);
  // 老版本存过 15/30 秒这种不是 5 的倍数的值，落到最近的 5 秒档。
  var secondIndex = (((initialSeconds % 60) + 2) ~/ 5) % 12;
  if (minutes == 0 && secondIndex < 2) secondIndex = 2;

  int effective(int minute, int secondIndexValue) => (minute * 60 +
          secondIndexValue * 5)
      .clamp(
        PetSettings.minRealtimeGapSeconds,
        PetSettings.maxRealtimeGapSeconds,
      );

  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: EchoColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheet) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final current = effective(minutes, secondIndex);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '观察间隔',
                  style: TextStyle(
                    color: EchoColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatRealtimeGap(current),
                  style: TextStyle(
                    color: EchoColors.primary,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '10 秒 — 10 分钟，间隔越短回看越勤、越费 token',
                  style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 176,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LoopingWheel(
                        count: 11,
                        initialIndex: minutes,
                        labelBuilder: (index) => '$index',
                        onChanged: (index) =>
                            setSheetState(() => minutes = index),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '分',
                          style: TextStyle(
                            color: EchoColors.textMuted,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      _LoopingWheel(
                        count: 12,
                        initialIndex: secondIndex,
                        labelBuilder: (index) =>
                            (index * 5).toString().padLeft(2, '0'),
                        onChanged: (index) =>
                            setSheetState(() => secondIndex = index),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '秒',
                          style: TextStyle(
                            color: EchoColors.textMuted,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(current),
                    child: const Text('就用这个间隔'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// 一列可以一直转下去的滚轮。用很大的起始 item 让两边都有“上一档”。
class _LoopingWheel extends StatefulWidget {
  const _LoopingWheel({
    required this.count,
    required this.initialIndex,
    required this.labelBuilder,
    required this.onChanged,
  });

  final int count;
  final int initialIndex;
  final String Function(int index) labelBuilder;
  final ValueChanged<int> onChanged;

  @override
  State<_LoopingWheel> createState() => _LoopingWheelState();
}

class _LoopingWheelState extends State<_LoopingWheel> {
  static const int _loopBase = 1000;

  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(
        initialItem: _loopBase * widget.count + widget.initialIndex,
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      child: ListWheelScrollView.useDelegate(
        controller: _controller,
        itemExtent: 40,
        diameterRatio: 1.5,
        perspective: 0.004,
        useMagnifier: true,
        magnification: 1.12,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (value) =>
            widget.onChanged(value % widget.count),
        // childCount 留空 = 不限长度，配合很大的初始 item，两侧都能一直转。
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: null,
          builder: (context, index) {
            final value = widget.labelBuilder(index % widget.count);
            return Center(
              child: Text(
                value,
                style: TextStyle(
                  color: EchoColors.text,
                  fontSize: 20,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
