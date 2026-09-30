import 'ai_persona.dart';

/// 「某个住民在某个时刻要发一条动态」——世界 tick 与内容生成之间的契约。
///
/// 时刻是内容的一部分：早上发的是早上的事，凌晨发的是凌晨的事。
/// 所以它要跟着人一起交给生成器，而不是等生成完了再随便盖个时间戳。
class ResidentMoment {
  const ResidentMoment({required this.persona, required this.at});

  final AiPersona persona;

  /// 这条动态"发生"的时刻。世界 tick 会把它排在过去——
  /// 用户没开 APP 的那几个小时里，社区也该发生点什么。
  final DateTime at;
}

/// 住民要发的一条动态（还没落库）。
class ResidentPostDraft {
  const ResidentPostDraft({
    required this.personaId,
    required this.content,
    this.topicName,
    this.newBio,
  });

  final String personaId;
  final String content;
  final String? topicName;

  /// 顺手换的新签名（B3.5），没有就是 null。
  ///
  /// 跟着动态一起生成，是因为"改签名"这件事在真人身上本来就跟着某个由头
  /// ——今天这条动态就是他心情的由头。这样也不需要为一句十几个字
  /// 单独发一次模型请求。
  final String? newBio;
}
