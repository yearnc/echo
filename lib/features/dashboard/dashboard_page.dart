import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_texts.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/addiction_repository.dart';
import '../../data/repositories/clear_journal_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../domain/services/dashboard_stats.dart';
import '../../domain/services/mode_controller.dart';

/// 趋势窗口：一周。再长就只剩一条平线了。
const int _trendDays = 7;

/// 高峰时段看两周：一屏互动本来就不多，窗口太窄看不出规律。
const int _peakDays = 14;

/// 数据看板（规划书 §3.10 / §6.9）。
///
/// 两种模式看的是两个世界的东西：
/// - **回响模式**：全是 AI 造出来的数字（点赞、评论、关注），所以每一处
///   都必须带着"以下数据由 AI 生成，不代表真实社会评价"那句话
/// - **清醒模式**：只有用户自己真实记下的东西，一条 AI 数据都不给看
///   （规划书 §4：「清醒模式数据看板只展示真实记录统计」）
///
/// 这不是两个皮肤，是两套数据源。混在一起显示的话，看板本身就成了
/// 那个把人绕进去的东西——用户会分不清哪些数字是"有人真的喜欢我"。
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeControllerProvider);
    final isEcho = mode.isEcho;

    return Scaffold(
      backgroundColor: isEcho ? EchoColors.bg : ClearColors.bg,
      appBar: AppBar(
        backgroundColor: isEcho ? EchoColors.surface : ClearColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(
          color: isEcho ? EchoColors.text : ClearColors.text,
        ),
        title: Text(
          '数据看板',
          style: TextStyle(
            color: isEcho ? EchoColors.text : ClearColors.text,
            fontSize: 16,
          ),
        ),
      ),
      body: isEcho ? const _EchoBoard() : const _ClearBoard(),
    );
  }
}

// ── 回响模式：AI 制造的动静 ─────────────────────────────────────

class _EchoBoard extends ConsumerWidget {
  const _EchoBoard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(echoDashboardProvider);

    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorNote(message: '$error'),
      data: (board) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const _Lead(
              title: '这里发生的事',
              subtitle: '点赞、评论、关注——都是 AI 住民给你的回应。',
              isEcho: true,
            ),
            const SizedBox(height: 16),
            _NumberRow(
              items: [
                ('今天发帖', '${board.postsToday}'),
                ('今天收到的赞', '${board.likesToday}'),
                ('今天收到的评论', '${board.commentsToday}'),
                ('关注我的人', '${board.followers}'),
              ],
              isEcho: true,
            ),
            const SizedBox(height: 20),
            _SectionCard(
              isEcho: true,
              title: '最近 7 天',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Legend(
                    entries: [
                      ('点赞', EchoColors.like),
                      ('评论', EchoColors.accent),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _LineChart(
                    series: [board.likesPerDay, board.commentsPerDay],
                    colors: [EchoColors.like, EchoColors.accent],
                    labels: board.dayLabels,
                    isEcho: true,
                  ),
                  const SizedBox(height: 10),
                  _DeltaLine(
                    label: '点赞',
                    daily: board.likesPerDay,
                    isEcho: true,
                  ),
                  const SizedBox(height: 4),
                  _DeltaLine(
                    label: '评论',
                    daily: board.commentsPerDay,
                    isEcho: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              isEcho: true,
              title: '互动高峰时段',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HourBars(values: board.hourly, isEcho: true),
                  const SizedBox(height: 10),
                  Text(
                    board.busiestHour == null
                        ? '还没有足够的互动看得出规律。'
                        : '回应最集中的时候是${DashboardStats.hourLabel(board.busiestHour!)}。',
                    style: TextStyle(
                      color: EchoColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              isEcho: true,
              title: '你自己',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatLine(
                    label: '最近半小时查看反馈',
                    value: '${board.feedbackViews} 次',
                    isEcho: true,
                  ),
                  _StatLine(
                    label: '本周亮屏等待',
                    value: '${board.waitsThisWeek} 次',
                    isEcho: true,
                  ),
                  _StatLine(
                    label: '本周收到的私信',
                    value: '${board.messagesThisWeek} 条',
                    isEcho: true,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    board.waitsThisWeek == 0
                        ? '本周没有过"盯着屏幕等回应"的时刻。'
                        : '等回应这件事，看板只记次数，不评价。',
                    style: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // 规划书 §3.10：这一句必须固定出现，不许在页面里被省略。
            const _FixedNotice(text: AppTexts.aiDataNotice, isEcho: true),
          ],
        );
      },
    );
  }
}

// ── 清醒模式：只看真实发生的 ───────────────────────────────────

class _ClearBoard extends ConsumerWidget {
  const _ClearBoard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(clearDashboardProvider);

    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorNote(message: '$error'),
      data: (board) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const _Lead(
              title: '你真实做过的事',
              subtitle: '这一页全是数字不出来的东西：写下的、做过的、想清楚的。',
              isEcho: false,
            ),
            const SizedBox(height: 16),
            _NumberRow(
              items: [
                ('本周记录', '${board.recordsThisWeek}'),
                ('本周真实行动', '${board.actionsThisWeek}'),
                ('我重视的事', '${board.valuesCount}'),
                ('连续记录', '${board.streakDays} 天'),
              ],
              isEcho: false,
            ),
            const SizedBox(height: 20),
            _SectionCard(
              isEcho: false,
              title: '最近 7 天的记录',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LineChart(
                    series: [board.recordsPerDay],
                    colors: [ClearColors.primary],
                    labels: board.dayLabels,
                    isEcho: false,
                  ),
                  const SizedBox(height: 10),
                  _DeltaLine(
                    label: '记录',
                    daily: board.recordsPerDay,
                    isEcho: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              isEcho: false,
              title: '为什么这里看不到点赞',
              child: Text(
                '虚拟反馈的趋势不在这边显示——那是 AI 编出来的数字，\n'
                '拿它跟你真实做过的事放在一页里比，本身就是个陷阱。',
                style: TextStyle(
                  color: ClearColors.textMuted,
                  fontSize: 12.5,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const _FixedNotice(
              text: '本页只统计你真实记录的内容，不含任何 AI 生成数据。',
              isEcho: false,
            ),
          ],
        );
      },
    );
  }
}

// ── 数据 ──────────────────────────────────────────────────────

/// 回响模式看板上的全部数字（都算好了，界面只管画）。
class EchoBoardData {
  const EchoBoardData({
    required this.postsToday,
    required this.likesToday,
    required this.commentsToday,
    required this.followers,
    required this.likesPerDay,
    required this.commentsPerDay,
    required this.dayLabels,
    required this.hourly,
    required this.busiestHour,
    required this.feedbackViews,
    required this.waitsThisWeek,
    required this.messagesThisWeek,
  });

  final int postsToday;
  final int likesToday;
  final int commentsToday;
  final int followers;
  final List<int> likesPerDay;
  final List<int> commentsPerDay;
  final List<String> dayLabels;
  final List<int> hourly;
  final int? busiestHour;
  final int feedbackViews;
  final int waitsThisWeek;
  final int messagesThisWeek;
}

/// 清醒模式看板上的数字。
class ClearBoardData {
  const ClearBoardData({
    required this.recordsThisWeek,
    required this.actionsThisWeek,
    required this.valuesCount,
    required this.streakDays,
    required this.recordsPerDay,
    required this.dayLabels,
  });

  final int recordsThisWeek;
  final int actionsThisWeek;
  final int valuesCount;
  final int streakDays;
  final List<int> recordsPerDay;
  final List<String> dayLabels;
}

final echoDashboardProvider = FutureProvider.autoDispose<EchoBoardData>((
  ref,
) async {
  final dashboard = ref.watch(dashboardRepositoryProvider);
  final addiction = ref.watch(addictionRepositoryProvider);
  final now = DateTime.now();

  // 一次取两周的数据：7 天的趋势和 14 天的高峰都从这里切。
  // 分两次查要来回两趟，而这里的行数本来就很少。
  final peakSince = DashboardStats.dayStart(
    now,
  ).subtract(const Duration(days: _peakDays - 1));

  final posts = await dashboard.myPostTimes(since: peakSince);
  final interactions = await dashboard.executedInteractions(since: peakSince);
  final followers = await dashboard.followerCount();

  final likes = [
    for (final item in interactions)
      if (item.isLike) (at: item.at, value: math.max(1, item.likeBatch)),
  ];
  final comments = [
    for (final item in interactions)
      if (item.isComment) (at: item.at, value: 1),
  ];

  final likesPerDay = DashboardStats.dailyTotals(
    likes,
    days: _trendDays,
    now: now,
  );
  final commentsPerDay = DashboardStats.dailyTotals(
    comments,
    days: _trendDays,
    now: now,
  );
  final postsPerDay = DashboardStats.dailyTotals([
    for (final at in posts) (at: at, value: 1),
  ], days: _trendDays, now: now);

  final hourly = DashboardStats.hourlyTotals([
    for (final item in interactions) item.at,
  ]);

  final weekAgo = now.subtract(const Duration(days: 7));

  return EchoBoardData(
    postsToday: postsPerDay.last,
    likesToday: likesPerDay.last,
    commentsToday: commentsPerDay.last,
    followers: followers,
    likesPerDay: likesPerDay,
    commentsPerDay: commentsPerDay,
    dayLabels: [
      for (final day in DashboardStats.recentDays(days: _trendDays, now: now))
        DashboardStats.weekdayLabel(day),
    ],
    hourly: hourly,
    busiestHour: DashboardStats.busiestHour(hourly),
    feedbackViews: await addiction.countFeedbackViews(),
    waitsThisWeek: await addiction.countEventsSince(
      AddictionEventType.screenWait,
      weekAgo.millisecondsSinceEpoch,
    ),
    messagesThisWeek: await dashboard.receivedMessageCount(since: weekAgo),
  );
});

final clearDashboardProvider = FutureProvider.autoDispose<ClearBoardData>((
  ref,
) async {
  final dashboard = ref.watch(dashboardRepositoryProvider);
  final journal = ref.watch(clearJournalRepositoryProvider);
  final now = DateTime.now();

  // 「最近 7 天」按自然日切（和左边那张趋势图对齐），
  // 「本周」按滚动 7 天算——用户心里的"这周做了几次"是后者。
  final trendSince = DashboardStats.dayStart(
    now,
  ).subtract(const Duration(days: _trendDays - 1));
  final weekAgo = now.subtract(const Duration(days: 7));

  final posts = await dashboard.myPostTimes(
    since: trendSince,
    scope: 'clear',
  );
  final actions = await journal.watchActions().first;
  final values = await journal.listValues();

  final recordsPerDay = DashboardStats.dailyTotals([
    for (final at in posts) (at: at, value: 1),
  ], days: _trendDays, now: now);

  return ClearBoardData(
    recordsThisWeek: posts.where((at) => at.isAfter(weekAgo)).length +
        actions.where((a) => a.createdAt.isAfter(weekAgo)).length,
    actionsThisWeek: actions.where((a) => a.createdAt.isAfter(weekAgo)).length,
    valuesCount: values.length,
    streakDays: _streak(recordsPerDay),
    recordsPerDay: recordsPerDay,
    dayLabels: [
      for (final day in DashboardStats.recentDays(days: _trendDays, now: now))
        DashboardStats.weekdayLabel(day),
    ],
  );
});

/// 从最后一天往回数，连续几天有记录。
int _streak(List<int> daily) {
  var days = 0;
  for (var i = daily.length - 1; i >= 0; i--) {
    if (daily[i] == 0) break;
    days += 1;
  }
  return days;
}

// ── 小部件 ────────────────────────────────────────────────────

class _Lead extends StatelessWidget {
  const _Lead({
    required this.title,
    required this.subtitle,
    required this.isEcho,
  });

  final String title;
  final String subtitle;
  final bool isEcho;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: isEcho ? EchoColors.text : ClearColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: isEcho ? EchoColors.textMuted : ClearColors.textMuted,
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// 一排数字卡。用 `Wrap` 而不是 `GridView`：手机窄的时候自然换行。
class _NumberRow extends StatelessWidget {
  const _NumberRow({required this.items, required this.isEcho});

  final List<(String, String)> items;
  final bool isEcho;

  @override
  Widget build(BuildContext context) {
    final surface = isEcho ? EchoColors.surface : ClearColors.surface;
    final divider = isEcho ? EchoColors.divider : ClearColors.divider;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final (label, value) in items)
          Container(
            width: 158,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: isEcho ? EchoColors.text : ClearColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: isEcho ? EchoColors.textMuted : ClearColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    required this.isEcho,
  });

  final String title;
  final Widget child;
  final bool isEcho;

  @override
  Widget build(BuildContext context) {
    final surface = isEcho ? EchoColors.surface : ClearColors.surface;
    final divider = isEcho ? EchoColors.divider : ClearColors.divider;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isEcho ? EchoColors.text : ClearColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.entries});

  final List<(String, Color)> entries;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (label, color) in entries) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: EchoColors.textMuted, fontSize: 11.5),
          ),
          const SizedBox(width: 14),
        ],
      ],
    );
  }
}

/// 一条"涨了多少"的说明。
class _DeltaLine extends StatelessWidget {
  const _DeltaLine({
    required this.label,
    required this.daily,
    required this.isEcho,
  });

  final String label;
  final List<int> daily;
  final bool isEcho;

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) return const SizedBox.shrink();

    final growth = DashboardStats.growthPercent(daily);
    final muted = isEcho ? EchoColors.textMuted : ClearColors.textMuted;
    final text = growth == null
        ? '刚开始有'
        : growth > 0
        ? '比前几天多了 $growth%'
        : growth < 0
        ? '比前几天少了 ${-growth}%'
        : '和前几天一样';

    return Text(
      '$label：$text',
      style: TextStyle(color: muted, fontSize: 11.5),
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({
    required this.label,
    required this.value,
    required this.isEcho,
  });

  final String label;
  final String value;
  final bool isEcho;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: isEcho ? EchoColors.textMuted : ClearColors.textMuted,
              fontSize: 12.5,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: isEcho ? EchoColors.text : ClearColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 页脚那句固定的话。
///
/// 单独做成一个部件，是为了让"这一句必须出现"在代码里看得见：
/// 回响模式的看板没有它就不合规（规划书 §3.10）。
class _FixedNotice extends StatelessWidget {
  const _FixedNotice({required this.text, required this.isEcho});

  final String text;
  final bool isEcho;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isEcho ? EchoColors.surfaceHigh : ClearColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isEcho ? EchoColors.textMuted : ClearColors.textMuted,
          fontSize: 12,
          height: 1.5,
        ),
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '看板这次没读出来：$message',
          style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ── 图（自己画，不引第三方图表库） ──────────────────────────────

/// 折线图：几条线共用一个纵轴。
class _LineChart extends StatelessWidget {
  const _LineChart({
    required this.series,
    required this.colors,
    required this.labels,
    required this.isEcho,
  });

  final List<List<int>> series;
  final List<Color> colors;
  final List<String> labels;
  final bool isEcho;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: CustomPaint(
        size: Size.infinite,
        painter: _LinePainter(
          series: series,
          colors: colors,
          labels: labels,
          axisColor: isEcho ? EchoColors.divider : ClearColors.divider,
          labelColor: isEcho ? EchoColors.textFaint : ClearColors.textFaint,
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.series,
    required this.colors,
    required this.labels,
    required this.axisColor,
    required this.labelColor,
  });

  final List<List<int>> series;
  final List<Color> colors;
  final List<String> labels;
  final Color axisColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty || series.first.isEmpty) return;

    const bottomGap = 18.0;
    final chartHeight = size.height - bottomGap;
    final maxValue = series
        .expand((line) => line)
        .fold<int>(0, (best, value) => value > best ? value : best);
    // 全是 0 的时候画一条贴底的线：空图比平线更让人以为自己看错了。
    final top = maxValue == 0 ? 1 : maxValue;

    final step = series.first.length == 1
        ? 0.0
        : size.width / (series.first.length - 1);

    // 横轴（一条淡淡的底线，让图有"地面"）
    final axis = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, chartHeight),
      Offset(size.width, chartHeight),
      axis,
    );

    for (var s = 0; s < series.length; s++) {
      final line = series[s];
      final color = colors[s % colors.length];
      final path = Path();
      for (var i = 0; i < line.length; i++) {
        final x = step * i;
        final y = chartHeight - (line[i] / top) * (chartHeight - 6);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );

      // 点：数字少的时候，点比线更能说明"这里有个数"
      for (var i = 0; i < line.length; i++) {
        final x = step * i;
        final y = chartHeight - (line[i] / top) * (chartHeight - 6);
        canvas.drawCircle(Offset(x, y), 3, Paint()..color = color);
        canvas.drawCircle(
          Offset(x, y),
          1.4,
          Paint()..color = const Color(0xFFFFFFFF),
        );
      }
    }

    // 横轴标签
    for (var i = 0; i < labels.length; i++) {
      final painter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(color: labelColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (step * i - painter.width / 2).clamp(
        0.0,
        size.width - painter.width,
      );
      painter.paint(canvas, Offset(x, chartHeight + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.series != series || old.colors != colors || old.labels != labels;
}

/// 24 小时的柱子（互动高峰）。
class _HourBars extends StatelessWidget {
  const _HourBars({required this.values, required this.isEcho});

  final List<int> values;
  final bool isEcho;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: CustomPaint(
        size: Size.infinite,
        painter: _HourPainter(
          values: values,
          barColor: isEcho ? EchoColors.like : ClearColors.primary,
          labelColor: isEcho ? EchoColors.textFaint : ClearColors.textFaint,
          axisColor: isEcho ? EchoColors.divider : ClearColors.divider,
        ),
      ),
    );
  }
}

class _HourPainter extends CustomPainter {
  _HourPainter({
    required this.values,
    required this.barColor,
    required this.labelColor,
    required this.axisColor,
  });

  final List<int> values;
  final Color barColor;
  final Color labelColor;
  final Color axisColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    const bottomGap = 14.0;
    final chartHeight = size.height - bottomGap;
    final maxValue = values.fold<int>(0, (best, v) => v > best ? v : best);
    final top = maxValue == 0 ? 1 : maxValue;

    final slot = size.width / values.length;
    final barWidth = math.max(1.5, slot - 2);

    final axis = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, chartHeight),
      Offset(size.width, chartHeight),
      axis,
    );

    for (var i = 0; i < values.length; i++) {
      // 至少 2 像素高：0 和"极少"在柱状图上分不出来，那不行
      final height = values[i] == 0
          ? 2.0
          : math.max(3.0, (values[i] / top) * (chartHeight - 4));
      final x = slot * i + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, chartHeight - height, barWidth, height),
          const Radius.circular(2),
        ),
        Paint()
          ..color = values[i] == 0
              ? axisColor
              : barColor.withValues(alpha: 0.85),
      );
    }

    // 只标 0 / 6 / 12 / 18 四个刻度，24 个数字挤不下
    for (final hour in const [0, 6, 12, 18]) {
      final painter = TextPainter(
        text: TextSpan(
          text: '$hour',
          style: TextStyle(color: labelColor, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (slot * hour - painter.width / 2).clamp(
        0.0,
        size.width - painter.width,
      );
      painter.paint(canvas, Offset(x, chartHeight + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _HourPainter old) => old.values != values;
}
