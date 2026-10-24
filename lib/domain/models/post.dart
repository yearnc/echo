/// 帖子与评论的领域模型。
///
/// 刻意不直接用 Drift 生成的行对象：数据库结构会随迁移变化，
/// 而 UI 和业务逻辑需要的是稳定的形状。
library;

/// 评论的媒体形态（规划书 §3.5 互动机制）。
enum CommentMedia { text, voice, image, emoji }

class Post {
  const Post({
    required this.id,
    required this.content,
    this.images = const [],
    this.topicName,
    required this.createdAt,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isAiGenerated = false,
    this.scope = 'shared',
    this.allowAiReply = true,
    this.isHot = false,
    this.authorPersonaId,
    this.authorResidentId,
    this.likedByMe = false,
  });

  final String id;
  final String content;

  /// 图片引用，`asset:` 或 `file:` 前缀，与 [UserAvatar.avatarRef] 同一套约定。
  final List<String> images;
  final String? topicName;
  final DateTime createdAt;
  final int likeCount;
  final int commentCount;
  final bool isAiGenerated;
  final String scope;
  final bool allowAiReply;
  final bool isHot;

  /// 住民自己发的动态记的是他的 id；用户发的是 null。
  ///
  /// 住民动态走同一张表（阶段 B 计划书决策 3），所以"这是谁发的"
  /// 只能靠这一列分——信息流、帖子详情、通知都看它。
  final String? authorPersonaId;

  /// 固定住民自己发的动态记的是他的 id；用户发的为空。
  final String? authorResidentId;

  /// 我点过赞没有。住民当然不知道这件事——这颗心只属于这台设备。
  final bool likedByMe;

  bool get hasImages => images.isNotEmpty;
  bool get isByResident =>
      authorPersonaId != null || authorResidentId != null;

  Post copyWith({
    int? likeCount,
    int? commentCount,
    bool? isHot,
    bool? likedByMe,
  }) {
    return Post(
      id: id,
      content: content,
      images: images,
      topicName: topicName,
      createdAt: createdAt,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isAiGenerated: isAiGenerated,
      scope: scope,
      allowAiReply: allowAiReply,
      isHot: isHot ?? this.isHot,
      authorPersonaId: authorPersonaId,
      authorResidentId: authorResidentId,
      likedByMe: likedByMe ?? this.likedByMe,
    );
  }
}

class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    this.personaId,
    this.content,
    this.mediaType = CommentMedia.text,
    this.caption = '',
    this.voiceAsset,
    this.transcript,
    this.voiceDurationMs,
    required this.createdAt,
    this.parentId,
    this.replyToName,
    this.likeCount = 0,
    this.isAi = true,
  });

  final String id;
  final String postId;

  /// 说话的住民；**null 表示这条是本机用户自己说的**。
  final String? personaId;

  /// 文本评论正文；语音评论也保留文本（作为转写稿）。
  final String? content;
  final CommentMedia mediaType;

  /// 图片/表情包评论附带的文字，可以为空。
  final String caption;
  final String? voiceAsset;
  final String? transcript;
  final int? voiceDurationMs;
  final DateTime createdAt;

  /// 非空表示这是一条楼中楼回复。
  final String? parentId;

  /// 在回谁。只用来显示"回复 XXX"。
  final String? replyToName;

  final int likeCount;
  final bool isAi;

  bool get isVoice => mediaType == CommentMedia.voice;
}
