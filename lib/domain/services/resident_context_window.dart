import '../../core/utils/agent_time.dart';
import '../models/private_message.dart';

/// 一位住民的常驻上下文窗口（v4.7）。
///
/// 参考 Open-ClaudeCode 的 `mutableMessages`：一个跨唤醒复用的消息数组，
/// 新内容只往后追加，不再每次醒来从数据库全量重建——前缀稳定，缓存才命得中。
///
/// 窗口里只放**对话层**：system（人设 + 最近 5 条记忆）+ 最近 20 条私信。
/// 工具调用、屏幕观察、气泡只进本轮载荷，用完即弃（见 `ResidentToolSession.act`）。
///
/// 半小时没有新动静就作废，下次按 20 条私信 + 5 条记忆重建；
/// 窗口存在期间来了新私信只追加并续期。
class ResidentContextWindow {
  ResidentContextWindow({
    required this.residentId,
    required this.promptHash,
    required this.messages,
    required this.syncedThroughMs,
    required this.dmIds,
    required DateTime now,
  }) : expiresAt = now.add(ttl);

  /// 窗口寿命：构建或刷新之后维持半小时（滑动续期）。
  static const Duration ttl = Duration(minutes: 30);

  /// 构建时带多少条私信；之后新来的只追加，不再回头砍。
  static const int baseDmCount = 20;

  final String residentId;

  /// system 提示的哈希：人设、语音开关这类设置变了就重建窗口。
  final String promptHash;

  /// system + 私信，按时间只追加。本轮载荷不写进这里。
  final List<Map<String, dynamic>> messages;

  /// 窗口里最后一条私信的时间（毫秒），下一轮从这里往后补。
  int syncedThroughMs;

  /// 已在窗口里的私信 id：同一毫秒的重复查询靠它幂等。
  final Set<String> dmIds;

  DateTime expiresAt;

  bool expired(DateTime now) => !now.isBefore(expiresAt);

  void touch(DateTime now) => expiresAt = now.add(ttl);

  void appendDm(PrivateMessage message) {
    if (!dmIds.add(message.id)) return;
    messages.add(dmMessage(message));
    final at = message.createdAt.millisecondsSinceEpoch;
    if (at > syncedThroughMs) syncedThroughMs = at;
  }

  static Map<String, dynamic> dmMessage(PrivateMessage message) => {
    'role': message.fromMe ? 'user' : 'assistant',
    'content': dmLine(message),
  };

  /// 时间线是住民视角：用户发来的标“对方”，住民自己发的不加人称——
  /// role 已经说明是谁说的话。以前写成“你：…”，模型会把整行当成
  /// 说话格式照抄（v4.6.1 真机问题）。
  static String dmLine(PrivateMessage message) {
    final when = agentTimeLabel(message.createdAt);
    final who = message.fromMe ? '对方：' : '';
    final body = switch (message.mediaType) {
      'image' => message.caption.trim().isEmpty
          ? '[发来一张图片]'
          : '[发来一张图片] ${message.caption.trim()}',
      'sticker' => message.caption.trim().isEmpty
          ? '[表情包]'
          : '[表情包] ${message.caption.trim()}',
      'voice' => message.transcript.trim().isEmpty
          ? '[语音]'
          : '（语音）${message.transcript.trim()}',
      'call' => message.content.trim().isEmpty ? '[通话]' : message.content.trim(),
      _ => message.content.trim().isEmpty
          ? '[空消息]'
          : message.content.trim(),
    };
    return '[$when] $who$body';
  }
}
