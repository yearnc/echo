/// 一次内容审核的判定（规划书 §6.10 内容审核与安全过滤）。
enum ModerationVerdict {
  /// 正常内容，直接放行。
  pass,

  /// 可能有问题：提醒发布者确认一次，确认后仍然可以发布。
  ///
  /// 留这一级，是因为模型的判定一定有假阳性。直接硬拦会把正常表达堵死，
  /// 而"这段话有没有问题"这件事，最终只有发布者本人说得清。
  review,

  /// 明确违规：不放行。
  block,
}

/// 审核结果。
class ModerationResult {
  const ModerationResult({
    required this.verdict,
    this.categories = const [],
    this.reason = '',
    this.fromModel = false,
  });

  /// 放行、且什么都没发生。没命中词表、又没配模型时就是它。
  static const ModerationResult ok = ModerationResult(
    verdict: ModerationVerdict.pass,
  );

  final ModerationVerdict verdict;

  /// 违规类别（见 [moderationCategoryLabel]），可能为空。
  final List<String> categories;

  /// 一句话说明，直接显示给用户，所以必须是人话。
  final String reason;

  /// 判定来自模型还是本地词表。
  ///
  /// 界面上不区分（用户不关心审他的人是谁），但测试与排查需要，
  /// 而且"这条被拦是本地词表干的"和"是模型干的"该走不同的复核路径。
  final bool fromModel;

  bool get isBlocked => verdict == ModerationVerdict.block;
  bool get needsConfirm => verdict == ModerationVerdict.review;
}

/// 违规类别的中文标签。模型返回的是英文 key，界面不能直接显示。
String moderationCategoryLabel(String key) => switch (key.trim().toLowerCase()) {
  'porn' => '色情低俗',
  'violence' => '血腥暴力',
  'illegal' => '违法犯罪',
  'selfharm' => '自杀自残',
  'hate' => '攻击与仇恨',
  'spam' => '垃圾信息',
  _ => '其他',
};
