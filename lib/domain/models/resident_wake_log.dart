/// 固定住民的一次醒来（v3.9）。
///
/// 这是给住民自己看的记录，也是「固定住民 ID 的日志」页的数据源：
/// 什么时候醒的、因为什么醒、醒了多久、有没有给下次的自己留话。
class ResidentWakeLog {
  const ResidentWakeLog({
    required this.id,
    required this.residentId,
    required this.trigger,
    required this.wokeAt,
    this.endedAt,
    this.note = '',
    this.noteAt,
    this.tools = const [],
  });

  final String id;
  final String residentId;

  /// user_action / heartbeat / background / setup
  final String trigger;
  final DateTime wokeAt;
  final DateTime? endedAt;

  /// 留给下一次醒来的自己的话。
  final String note;
  final DateTime? noteAt;

  /// 这一轮调用了哪些工具（原始名，按调用顺序）。v43 起记录。
  final List<String> tools;

  bool get hasNote => note.trim().isNotEmpty;
  bool get hasTools => tools.isNotEmpty;

  /// 工具名给页面上看的中文说法。
  static String toolLabel(String name) => switch (name) {
    'memory_search' || 'memory_read' || 'memory_list_recent' => '翻记忆',
    'memory_write' || 'memory_update' || 'memory_delete' => '记事情',
    'web_search' => '联网搜索',
    'browse_feed' => '刷帖子',
    'read_post' => '看帖子',
    'like_post' => '点赞',
    'comment_post' => '写评论',
    'reply_inbox' => '回评论',
    'send_dm' => '发私信',
    'send_voice' => '发语音',
    'send_sticker' => '发表情',
    'create_post' => '发动态',
    'generate_image' => '画图',
    'check_wake_log' => '看自己的日志',
    'leave_note' => '留句话',
    'set_alarm' => '定闹钟',
    'cancel_alarm' => '取消闹钟',
    'list_alarms' => '看闹钟',
    'pet_status' => '看桌宠',
    'pet_say' => '冒气泡',
    'pet_react' => '换动作',
    'pet_look' => '看屏幕',
    'pet_request_watch' => '申请观察',
    'pet_sleep' => '缩成一团',
    'pet_note' => '记下看到的',
    'list_tools' => '查工具',
    'list_stickers' => '挑表情',
    'cancel_pending_segment' => '取消待发',
    'rewrite_pending_segment' => '改写待发',
    'finish' => '已读不回',
    _ => name,
  };

  /// 触发方式的中文说法（日志页与工具结果共用一份）。
  String get triggerLabel => switch (trigger) {
    'user_action' => '有人叫了 TA',
    'heartbeat' => '自己醒来看看',
    'background' => '系统后台叫醒',
    'setup' => '刚住进来',
    'alarm' => '给自己定的闹钟',
    'pet' => '桌宠醒着',
    _ => '醒来',
  };

  /// 这一轮醒着多久；还没结束就返回 null。
  Duration? get awakeFor {
    final end = endedAt;
    if (end == null) return null;
    final span = end.difference(wokeAt);
    return span.isNegative ? Duration.zero : span;
  }
}
