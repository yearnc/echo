/// 全应用共用的文案常量。
///
/// 合规模块尤其重要：这些字句是规划书里定死的，不允许在业务代码里随手改写。
/// 集中在这里，是为了保证「回响模式页面底部小字」和「清醒模式永久提示」
/// 在所有页面里逐字一致。
class AppTexts {
  const AppTexts._();

  // ── 合规标识 ────────────────────────────────────────────────

  /// 回响模式所有页面底部固定小字（规划书 §3.7 / §3.11）。
  static const String aiDisclaimer = '内容由AI生成，仅供参考';

  /// 清醒模式永久提示（规划书 §2.4.1），不可关闭、不可删除。
  static const String permanentNotice = '本 APP 不含真实用户，请勿将此处认可等同于现实价值。';

  /// 数据看板必须带的标注（规划书 §3.10）。
  static const String aiDataNotice = '以下数据由 AI 生成，不代表真实社会评价。';

  /// 语音播放器底部小字（规划书 §6.6）。
  static const String aiVoiceNotice = 'AI 生成语音';

  /// 截图第三方模型时告知用户内容会离开本机（规划书 §12）。
  static const String thirdPartyApiNotice = '调用第三方模型时，帖内容会发送给你配置的 API。';

  // ── 心理安全（规划书 §6.10 / §13）─────────────────────────────

  static const String riskWarningTitle = '使用前请了解';
  static const String riskWarningBody =
      '回响模式中的点赞、评论、私信全部由 AI 生成，不是真实的人。\n'
      '如果长时间沉浸其中，你可能会更难从真实生活里获得确定感。';
  static const String addictionReminder = '这条帖子的价值不等于点赞量。';
  static const String coolDownReminder = '冷静模式已开启：点赞和评论会延迟显示。';
  static const String helpEntry = '心理援助';

  // ── 模式切换（规划书 §2.4）──────────────────────────────────

  static const String switchToEchoConfirm = '即将重新启用虚拟反馈，可能强化外部评价依赖。';
  static const String switchToEchoAgeGate = '我已理解并承诺本人已经满 18 周岁';
  static const String switchToClearBody = '将停止所有虚拟互动，并归档已有 AI 评论、点赞与语音。';

  // ── 用户资料默认值 ──────────────────────────────────────────

  /// 默认昵称。
  ///
  /// 开源仓库里刻意不放任何真实姓名；真实昵称由用户在自己的资料页填写。
  static const String defaultNickname = '同学';

  // ── 空态 / 通用 ─────────────────────────────────────────────

  static const String emptyFeed = '还没有帖子\n发一条，看看世界会怎么回应你。';
  static const String emptyRecords = '还没有记录\n记录一件今天真实发生的事。';
  static const String emptyNotifications = '暂时没有新通知';
}
