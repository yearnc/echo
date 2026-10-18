/// 社区层面的全局开关（v3.0）。
///
/// 和发布页那份 `EchoSettings` 分开：那一份是"这条帖子怎么回应"，
/// 这一份是"这个社区还要不要自己动"。
class CommunitySettings {
  const CommunitySettings({
    this.allowResidentPosts = false,
    this.allowLurk = true,
    this.aiPeerInteractionLimit = 2,
  });

  /// 固定住民要不要自己发动态。
  ///
  /// 临时网民只在用户发帖后出现，不会自己起头；这个开关只管固定住民。
  /// 默认关：v3.0 的重心是"用户发帖后的反馈"，而不是让信息流自己长内容。
  final bool allowResidentPosts;

  /// 允许网民"只看看、不点赞也不评论"。
  ///
  /// 默认开：真实社区里大多数人就是路过；关掉之后每个来的人都必须留痕。
  final bool allowLurk;

  /// 每帖 AI 接 AI 的上限。0 表示不让他们互相说话。
  final int aiPeerInteractionLimit;

  CommunitySettings copyWith({
    bool? allowResidentPosts,
    bool? allowLurk,
    int? aiPeerInteractionLimit,
  }) => CommunitySettings(
    allowResidentPosts: allowResidentPosts ?? this.allowResidentPosts,
    allowLurk: allowLurk ?? this.allowLurk,
    aiPeerInteractionLimit:
        aiPeerInteractionLimit ?? this.aiPeerInteractionLimit,
  );

  static const CommunitySettings defaults = CommunitySettings();
}
