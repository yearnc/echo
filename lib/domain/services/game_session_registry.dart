/// 正在棋盘边的对局（v4.8）。
///
/// 和 [CallRegistry] 一样只活在本进程里：用户在下一局时，桌宠的普通/实时
/// 观察先停一停，别一边下棋一边截游戏画面、白花 token，也别让屏幕观察的
/// 唤醒和走棋抢同一段上下文。
class GameSessionRegistry {
  GameSessionRegistry._();

  static final Map<String, String> _matches = {};

  static void begin(String matchId, String residentId) {
    if (matchId.trim().isEmpty || residentId.trim().isEmpty) return;
    _matches[matchId] = residentId;
  }

  static void end(String matchId) {
    _matches.remove(matchId);
  }

  static bool isActiveResident(String residentId) =>
      _matches.containsValue(residentId);

  static bool get hasAny => _matches.isNotEmpty;

  static void clear() => _matches.clear();
}
