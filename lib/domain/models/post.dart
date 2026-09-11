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

  bool get hasImages => images.isNotEmpty;

  Post copyWith({
    int? likeCount,
    int? commentCount,
    bool? isHot,
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
    );
  }
}

class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.personaId,
    this.content,
    this.mediaType = CommentMedia.text,
    this.voiceAsset,
    this.transcript,
    this.voiceDurationMs,
    required this.createdAt,
    this.parentId,
    this.likeCount = 0,
    this.isAi = true,
  });

  final String id;
  final String postId;
  final String personaId;

  /// 文本评论正文；语音评论也保留文本（作为转写稿）。
  final String? content;
  final CommentMedia mediaType;
  final String? voiceAsset;
  final String? transcript;
  final int? voiceDurationMs;
  final DateTime createdAt;

  /// 非空表示这是一条楼中楼回复。
  final String? parentId;
  final int likeCount;
  final bool isAi;

  bool get isVoice => mediaType == CommentMedia.voice;
}
