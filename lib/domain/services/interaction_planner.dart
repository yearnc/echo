import 'dart:math';

import '../models/ai_persona.dart';
import '../models/echo_settings.dart';

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

  List<PlannedInteraction> plan({
    required DateTime now,
    required List<AiPersona> personas,
    required EchoSettings settings,
    Duration? window,
  }) {
    if (personas.isEmpty) return const [];

    final effectiveWindow = window ?? defaultWindow;
    final selected = _pickPersonas(personas, settings.density);
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
      if (_random.nextDouble() > persona.commentProbability) continue;

      final samples = persona.commentSamples;
      planned.add(
        PlannedInteraction(
          personaId: persona.id,
          type: 'comment',
          scheduledAt: _nudgeToActiveHour(
            commentTimes[commentIndex % commentTimes.length],
            persona,
          ),
          content: samples.isEmpty
              ? null
              : samples[_random.nextInt(samples.length)],
          // 语音评论要等 TTS 音色接进来（阶段 B）。在那之前统一按文本排期，
          // 免得评论区出现"有波形、没声音"的假语音条。
          mediaType: 'text',
        ),
      );
      commentIndex++;

      // 刻意**不**让同一个人格对同一条帖子评论第二次。
      //
      // 规划书 §3.6 提过"连续回复、追问"，但项目作者的判断更重要（2026-09-11）：
      // 一个账号在同一条帖子下留两条语气不同的评论，会立刻暴露"这是 AI"，
      // 破坏整个社区的可信度。真正的"追问"应该是**楼中楼回复**——
      // 那属于阶段 B：需要先有对话上下文，而不是并列两条顶层评论。
    }

    planned.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return planned;
  }

  /// 按频率档位挑住民，并优先挑"这个点本来就活跃"的人。
  List<AiPersona> _pickPersonas(
    List<AiPersona> personas,
    ReplyDensity density,
  ) {
    final (min, max) = density.personaRange;
    final count = min + _random.nextInt(max - min + 1);

    final pool = List<AiPersona>.of(personas)..shuffle(_random);
    return pool.take(count.clamp(0, pool.length)).toList(growable: false);
  }

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
