import 'dart:math';

import '../models/ai_persona.dart';
import '../models/echo_settings.dart';
import 'relationship_rules.dart';

/// 一条排好期的互动（还没落到数据库）。
class PlannedInteraction {
  const PlannedInteraction({
    required this.personaId,
    required this.type,
    required this.scheduledAt,
    this.content,
    this.mediaType = 'text',
    this.likeBatch = 1,
  });

  final String personaId;

  /// like / comment
  final String type;
  final DateTime scheduledAt;
  final String? content;
  final String mediaType;

  /// type=like 时表示"这一批代表多少个赞"：
  /// 居民自己的点赞是 1，匿名人群批次是 5~40（社区里沉默的大多数）。
  final int likeBatch;

  bool get isLike => type == 'like';
  bool get isComment => type == 'comment';

  PlannedInteraction copyWith({DateTime? scheduledAt}) => PlannedInteraction(
    personaId: personaId,
    type: type,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    content: content,
    mediaType: mediaType,
    likeBatch: likeBatch,
  );
}

/// 互动排期规划器：**纯逻辑，不碰数据库、不联网**。
///
/// 抽成纯函数是为了能真的测——"发帖后 48 小时内到底会发生什么"
/// 不应该只能靠等两天来验证。
class InteractionPlanner {
  InteractionPlanner({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// 默认排期窗口：0—48 小时（规划书 §3.6）。
  static const Duration defaultWindow = Duration(hours: 48);

  /// [delay] 会把所有排期整体往后推，用于冷静模式（规划书 §6.9）。
  /// 它作用在最终结果上而不是窗口起点，这样"摊开到 48 小时"的形态不变，
  /// 只是整体晚一点开始。
  /// [relations] 是这些人和你的关系（B4）：熟的人更可能注意到你发了什么，
  /// 也更可能真的开口。传空表就是"全是陌生"，行为与 B4 之前完全一样。
  List<PlannedInteraction> plan({
    required DateTime now,
    required List<AiPersona> personas,
    required EchoSettings settings,
    Map<String, RelationshipState> relations = const {},
    Duration? window,
    Duration delay = Duration.zero,
  }) {
    if (personas.isEmpty) return const [];

    final effectiveWindow = window ?? defaultWindow;
    final selected = _pickPersonas(personas, settings.density, relations);
    if (selected.isEmpty) return const [];

    final planned = <PlannedInteraction>[];

    // ── 点赞：先到，撑起"有人看见你了"的第一波 ──
    // 第一条点赞刻意排得很快（几十秒内）：规划书要求"避免全部集中在前 10 分钟"，
    // 指的是**整体**摊开到 48 小时，而不是让人发完帖对着空评论区坐十分钟。
    // "发出去了就有人路过"才是社区该有的手感。
    var remainingLikes = _randomIn(settings.likeLevel.totalRange);
    final likeTimes = _spread(
      now: now,
      window: effectiveWindow,
      count: selected.length * 2,
      firstWithin: const Duration(seconds: 20),
      firstSpread: const Duration(minutes: 2),
    );
    var likeIndex = 0;

    for (final persona in selected) {
      if (remainingLikes <= 0) break;
      // 每个人格有自己的点赞倾向：沉默的赞几乎必点，潜水员很少点
      if (_random.nextDouble() > persona.likeProbability) continue;

      planned.add(
        PlannedInteraction(
          personaId: persona.id,
          type: 'like',
          scheduledAt: _nudgeToActiveHour(
            likeTimes[likeIndex % likeTimes.length],
            persona,
          ),
          likeBatch: 1,
        ),
      );
      likeIndex++;
      remainingLikes -= 1;
    }

    // 剩下的赞交给"人群批次"：社区里绝大多数人只是路过点个赞，不会说话。
    // 用沉默点赞型住民的头像代表这一批人。
    final crowdBearer = _pickCrowdBearer(selected);
    while (remainingLikes > 0) {
      final batch = min(remainingLikes, _randomIn((5, 40)));
      planned.add(
        PlannedInteraction(
          personaId: crowdBearer.id,
          type: 'like',
          scheduledAt: _nudgeToActiveHour(
            likeTimes[likeIndex % likeTimes.length],
            crowdBearer,
          ),
          likeBatch: batch,
        ),
      );
      likeIndex++;
      remainingLikes -= batch;
    }

    // ── 评论：后到，而且要比点赞**慢**（真实社区的节奏） ──
    final commentTimes = _spread(
      now: now.add(const Duration(minutes: 2)),
      window: effectiveWindow - const Duration(minutes: 2),
      count: selected.length + 4,
      firstWithin: const Duration(minutes: 1),
      firstSpread: const Duration(minutes: 10),
    );
    var commentIndex = 0;

    for (final persona in selected) {
      final level = _levelOf(relations, persona.id);
      if (_random.nextDouble() > commentChance(persona, level)) continue;

      planned.add(
        PlannedInteraction(
          personaId: persona.id,
          type: 'comment',
          scheduledAt: _nudgeToActiveHour(
            commentTimes[commentIndex % commentTimes.length],
            persona,
          ),
          // 排期**不再预填台词**（v3.0）。内容由发帖后的模型请求按帖子写；
          // 没模型或失败就取消这批评论，绝不拿固定台词顶上——那正是
          // "钻石帖子下面说今天汤熬得好"的来源。
          content: null,
          // 排期这一层只写文字。语音是**兑现之后**才合成、才升级的（B8）：
          // 合成要一两秒，提前把 media_type 标成 voice 只会让评论区
          // 先出现一排点不响的播放键。
          mediaType: 'text',
        ),
      );
      commentIndex++;

      // 刻意**不**让同一个人格对同一条帖子评论第二次。
      //
      // 规划书 §3.6 提过"连续回复、追问"，但下面这个判断更重要（2026-09-11 定）：
      // 一个账号在同一条帖子下留两条语气不同的评论，会立刻暴露"这是 AI"，
      // 破坏整个社区的可信度。真正的"追问"应该是**楼中楼回复**——
      // 那属于阶段 B：需要先有对话上下文，而不是并列两条顶层评论。
    }

    planned.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    if (delay <= Duration.zero) return planned;

    // 冷静模式：整批往后推。反馈不是不来，是不那么快就来——
    // 这正是要练的：等待期间不刷新，也过得下去。
    return planned
        .map((item) => item.copyWith(scheduledAt: item.scheduledAt.add(delay)))
        .toList(growable: false);
  }

  /// 按频率档位挑住民（B4 之后，关系近的人占一点便宜）。
  ///
  /// 做法是让他们**多拿几张签**，而不是"必定到场"：熟人每次都在，
  /// 那是订阅了通知，不是朋友。关系没到互关的人，签数跟以前一样。
  List<AiPersona> _pickPersonas(
    List<AiPersona> personas,
    ReplyDensity density,
    Map<String, RelationshipState> relations,
  ) {
    final (min, max) = density.personaRange;
    final count = min + _random.nextInt(max - min + 1);

    final tickets = <AiPersona>[];
    for (final persona in personas) {
      final level = _levelOf(relations, persona.id);
      tickets.add(persona);
      if (level >= 2) tickets.add(persona);
      if (level >= 4) tickets.add(persona);
    }
    tickets.shuffle(_random);

    final picked = <AiPersona>[];
    final seen = <String>{};
    for (final persona in tickets) {
      if (picked.length >= count) break;
      // 抽中同一人的第二张签，不该让他在名单里出现两次
      if (!seen.add(persona.id)) continue;
      picked.add(persona);
    }
    return picked;
  }

  /// 关系越近，越可能真的开口（B4）。
  ///
  /// 陌生人点个赞就走了，熟人会多留一句——这是社区里最自然不过的事。
  /// 每档多 5%，上限压在 0.95：再熟也有不想说话的时候。
  static double commentChance(AiPersona persona, int level) =>
      (persona.commentProbability + level * 0.05).clamp(0.0, 0.95);

  /// 这个人会**用语音**说话吗（B8）。
  ///
  /// 语音不是"更高级的评论"，社区里的人各有理由用它：打字嫌麻烦的、
  /// 话懒得说全的、夜里只想留一句的。所以概率跟着语气标签走，
  /// 而不是跟着"活跃度"——话多的人反而更常打字。
  static double voiceChance(AiPersona persona) {
    final model = persona.voiceModel;
    if (model.contains('lazy') || model.contains('quiet')) return 0.34;
    if (model.contains('warm') || model.contains('soft')) return 0.22;
    return 0.16;
  }

  /// 一条帖子下面最多留几条语音。
  ///
  /// 评论区里一半人都在发语音，那不是社区，是语音信箱。
  static const int maxVoicesPerPost = 2;

  static int _levelOf(Map<String, RelationshipState> relations, String id) =>
      relations[id]?.level ?? 0;

  /// 用"沉默点赞型"住民代表匿名人群；没有就用第一个。
  AiPersona _pickCrowdBearer(List<AiPersona> personas) {
    for (final persona in personas) {
      if (persona.personalityType.contains('沉默')) return persona;
    }
    return personas.first;
  }

  /// 在窗口内生成一串由密到疏的时间点（前几个很快，后面拉开）。
  List<DateTime> _spread({
    required DateTime now,
    required Duration window,
    required int count,
    required Duration firstWithin,
    required Duration firstSpread,
  }) {
    final times = <DateTime>[];
    var cursor = now.add(_randomDuration(firstWithin, firstSpread));
    for (var i = 0; i < count; i++) {
      if (cursor.isAfter(now.add(window))) break;
      times.add(cursor);

      // 间隔随时间推移逐渐拉长：1 分钟内 → 最长 6 小时
      final progress = i / max(1, count - 1);
      final minGap = Duration(minutes: (2 + progress * 20).round());
      final maxGap = Duration(minutes: (25 + progress * 335).round());
      cursor = cursor.add(_randomDuration(minGap, maxGap));
    }
    if (times.isEmpty) times.add(now.add(firstWithin));
    return times;
  }

  /// 把时间点挪到该住民的活跃时段内（规划书 §3.3：不同人格不同作息）。
  ///
  /// 只往后挪，最多 6 小时，避免把排期推出 48 小时窗口。
  DateTime _nudgeToActiveHour(DateTime time, AiPersona persona) {
    if (persona.activeHours.isEmpty) return time;
    for (var shift = 0; shift <= 6; shift++) {
      final candidate = time.add(Duration(hours: shift));
      if (persona.isActiveAt(candidate)) return candidate;
    }
    return time;
  }

  Duration _randomDuration(Duration min, Duration max) {
    final low = min.inSeconds;
    final high = max.inSeconds;
    if (high <= low) return min;
    return Duration(seconds: low + _random.nextInt(high - low));
  }

  int _randomIn((int, int) range) {
    final (low, high) = range;
    if (high <= low) return low;
    return low + _random.nextInt(high - low + 1);
  }
}
