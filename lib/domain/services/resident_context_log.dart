import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 一位住民在“屏幕”和“私信”两侧共用的短期上下文。
///
/// 桌宠看到的画面、冒过的气泡，私信那一轮也要知道；反过来，私信历史
/// 由 `recentTurns` 直接拼进唤醒消息，本来就同时给两边看。这样同一个
/// 住民不会出现“屏幕上一套、私信里另一套”的分裂。
///
/// 只放在内存里：截图和“刚看了一眼”本来就是短时信息，长期记忆由住民
/// 自己用 `memory_write` 决定。按 residentId 分开——切控制者时，上一位
/// 的观察不会漏给下一位。
class ResidentContextLog {
  static const int maxLines = 12;

  final Map<String, List<String>> _lines = {};

  List<String> recent(String residentId, {int limit = maxLines}) {
    final lines = _lines[residentId];
    if (lines == null || lines.isEmpty) return const [];
    final count = limit.clamp(1, maxLines);
    final from = lines.length > count ? lines.length - count : 0;
    return List<String>.unmodifiable(lines.sublist(from));
  }

  void add(String residentId, String line) {
    final text = line.trim();
    if (text.isEmpty) return;
    final lines = _lines.putIfAbsent(residentId, () => <String>[]);
    lines.add(text);
    while (lines.length > maxLines) {
      lines.removeAt(0);
    }
  }

  void clear(String residentId) {
    _lines.remove(residentId);
  }

  void clearAll() {
    _lines.clear();
  }
}

final residentContextLogProvider = Provider<ResidentContextLog>(
  (ref) => ResidentContextLog(),
);
