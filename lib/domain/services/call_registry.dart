/// 正在进行的私信通话（v4.0）。
///
/// 桌宠和通话不能同时占着同一位住民：如果在控制时段开始前用户已经和 TA
/// 通上话，就**推迟** TA 的桌宠控制，等通话结束再接管。
/// 只用内存记录即可——进程没了，通话和桌宠也都不在了。
class CallRegistry {
  CallRegistry._();

  static final Set<String> _active = {};

  static void begin(String residentId) {
    if (residentId.trim().isEmpty) return;
    _active.add(residentId);
  }

  static void end(String residentId) {
    _active.remove(residentId);
  }

  static bool isActive(String residentId) => _active.contains(residentId);

  static bool get hasAny => _active.isNotEmpty;
}
