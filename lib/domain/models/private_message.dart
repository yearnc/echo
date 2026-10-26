/// 一条私信（B5）。
///
/// 与评论是两种东西：评论挂在帖子下面，谁都能看；私信是一对一的一段对话，
/// 只有你和他在里面。所以它自己一张表、自己一套口吻。
class PrivateMessage {
  const PrivateMessage({
    required this.id,
    required this.personaId,
    required this.fromMe,
    required this.content,
    required this.createdAt,
    this.mediaType = 'text',
    this.caption = '',
    this.voicePath = '',
    this.voiceDurationMs,
    this.transcript = '',
    this.read = false,
  });

  final String id;
  final String personaId;

  /// true = 我发出去的，false = 他发来的。
  final bool fromMe;
  final String content;
  final DateTime createdAt;

  /// text / voice / sticker / image。表情包把路径存在 [content] 里——
  /// 一个表情包就是一张图，为它单独开一列不值得。
  final String mediaType;

  /// 图片描述 / 表情包的名字与标签。不是聊天正文，但住民要靠它
  /// 知道“这张图里是什么、这个表情在表达什么”。
  final String caption;
  final String voicePath;
  final int? voiceDurationMs;
  final String transcript;

  /// 只有收到的消息才谈得上已读。
  final bool read;
}

/// 会话列表里的一行：一个人 + 你们最后说的那句话。
class Conversation {
  const Conversation({
    required this.personaId,
    required this.lastMessage,
    required this.lastAt,
    required this.unreadCount,
    this.lastFromMe = false,
  });

  final String personaId;
  final String lastMessage;
  final DateTime lastAt;
  final int unreadCount;

  /// 最后一句是不是我发的——列表上要能看出来"球在他那边"。
  final bool lastFromMe;
}
