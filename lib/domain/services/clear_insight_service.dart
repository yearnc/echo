import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/addiction_repository.dart';
import '../../data/repositories/clear_insight_repository.dart';
import '../../data/repositories/clear_journal_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/usage_repository.dart';
import '../models/clear_insight.dart';
import '../models/clear_journal.dart';
import 'dashboard_stats.dart';

/// 清醒分析的计算（v31）。
///
/// 全部数字都来自本机记录：发帖、评论、已兑现的 AI 互动、真实行动、
/// 查看反馈的次数、使用时长。这里**不调用模型**，也不写煽情文案——
/// 分析的价值在于“能对上账”，而不是替用户下结论。
///
/// 返回 null 表示这段时间没有任何可分析的东西；页面据此显示空态，
/// 不拿一份“全 0 的报告”假装分析过了。
class ClearInsightService {
  const ClearInsightService({
    required this.dashboard,
    required this.journal,
    required this.addiction,
    required this.usage,
    required this.insights,
  });

  final DashboardRepository dashboard;
  final ClearJournalRepository journal;
  final AddictionRepository addiction;
  final UsageRepository usage;
  final ClearInsightRepository insights;

  static const int days = 7;

  /// 生成并落库。没有可用记录时返回 null。
  Future<ClearInsight?> generate({DateTime? now}) async {
    final insight = await compute(now: now);
    if (insight == null) return null;
    await insights.save(insight);
    return insight;
  }

  /// 只算不落库（测试与“预览”都用它）。
  Future<ClearInsight?> compute({DateTime? now}) async {
    final end = now ?? DateTime.now();
    final start = DashboardStats.dayStart(
      end,
    ).subtract(const Duration(days: days - 1));
    final sinceMs = start.millisecondsSinceEpoch;

    // 清醒分析只统计真实记录：社区里的帖子属于回响侧，
    // 把它算成“你写下了什么”会让这一页又变成看别人反应的地方。
    final posts = await dashboard.myPostTimes(since: start, scope: 'clear');
    final comments = await dashboard.myCommentTimes(since: start);
    final interactions = await dashboard.executedInteractions(since: start);
    final actions = (await journal.watchActions().first)
        .where((action) => !action.createdAt.isBefore(start))
        .toList(growable: false);
    final feedbackViews = await addiction.countFeedbackViewsSince(sinceMs);
    final waits = await addiction.countEventsSince(
      AddictionEventType.screenWait,
      sinceMs,
    );
    final usageMs = await usage.totalMsSince(start);

    final likes = interactions
        .where((item) => item.isLike)
        .fold<int>(0, (sum, item) => sum + (item.likeBatch < 1 ? 1 : item.likeBatch));
    final aiComments = interactions.where((item) => item.isComment).length;
    final received = likes + aiComments;

    final hasAnything =
        posts.isNotEmpty ||
        comments.isNotEmpty ||
        interactions.isNotEmpty ||
        actions.isNotEmpty ||
        feedbackViews > 0 ||
        waits > 0 ||
        usageMs > 0;
    if (!hasAnything) return null;

    final hours = DashboardStats.hourlyTotals([
      ...posts,
      ...comments,
      for (final action in actions) action.createdAt,
    ]);
    final peak = DashboardStats.busiestHour(hours);
    final moodTally = tallyMoods([
      for (final action in actions)
        if (action.mood != null) action.mood!,
    ]);

    final metrics = <ClearInsightMetric>[
      ClearInsightMetric(
        id: 'posting',
        label: '记录频率',
        value: '近 $days 天写下 ${posts.length} 条记录'
            '，日均 ${(posts.length / days).toStringAsFixed(1)} 条',
        detail: '来自清醒侧的记录（不含社区帖子与住民动态）',
      ),
      ClearInsightMetric(
        id: 'feedback',
        label: '互动构成',
        value: '收到 $likes 个赞、$aiComments 条评论；'
            '你主动评论 ${comments.length} 次',
        detail: '来自已兑现的 AI 互动与你的评论记录',
      ),
      ClearInsightMetric(
        id: 'ai_share',
        label: 'AI 占比',
        value: received == 0
            ? '这 $days 天没有收到新的回应'
            : '收到的 $received 次回应，全部由 AI 生成',
        detail: '这是回响模式的产品设定，不代表真实社会评价',
      ),
      ClearInsightMetric(
        id: 'mood',
        label: '情绪走向',
        value: moodTally.isEmpty
            ? '这 $days 天没有记过心情'
            : '记得最多的是「${moodTally.first.$1.label}」',
        detail: moodTally.isEmpty
            ? '记录真实行动时顺手选一个心情，这里就会有内容'
            : moodTally
                  .map((entry) => '${entry.$1.label} ${entry.$2}')
                  .join(' · '),
      ),
      ClearInsightMetric(
        id: 'time',
        label: '时间分布',
        value: peak == null
            ? '记录还太少，看不出集中时段'
            : '你记录和发帖最集中在${DashboardStats.hourLabel(peak)}',
        detail: '来自发帖、评论与真实行动的时间',
      ),
    ];

    final summary =
        '过去 $days 天：写下 ${posts.length} 条记录，'
        '收到 $received 次 AI 回应，线下记下 ${actions.length} 件事。';

    return ClearInsight(
      generatedAt: end,
      periodStart: start,
      periodEnd: end,
      summary: summary,
      metrics: metrics,
      source: 'real',
    );
  }
}

final clearInsightServiceProvider = Provider<ClearInsightService>(
  (ref) => ClearInsightService(
    dashboard: ref.watch(dashboardRepositoryProvider),
    journal: ref.watch(clearJournalRepositoryProvider),
    addiction: ref.watch(addictionRepositoryProvider),
    usage: ref.watch(usageRepositoryProvider),
    insights: ref.watch(clearInsightRepositoryProvider),
  ),
);
