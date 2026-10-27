/// 固定住民这一轮正在干什么（v41）。
///
/// 只在**本进程**里有意义：住民的模型调用在前台/后台的同一台设备上跑，
/// 用户正在聊天页等它时，把它此刻的动作显示出来就够了。
/// 不落库、不跨进程——进程被杀掉时本来也没有“正在思考”这回事。
enum ResidentActivityKind { reading, thinking, tool, speaking }

class ResidentActivity {
  const ResidentActivity({
    required this.label,
    required this.kind,
    required this.since,
  });

  final String label;
  final ResidentActivityKind kind;
  final DateTime since;

  bool get isStale =>
      DateTime.now().difference(since) > const Duration(minutes: 5);
}
