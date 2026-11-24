import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/resident_alarm_repository.dart';
import '../../data/repositories/resident_sleep_repository.dart';
import '../../data/repositories/resident_wake_log_repository.dart';
import '../../domain/models/resident_alarm.dart';
import '../../domain/models/resident_sleep.dart';
import '../../domain/models/resident_wake_log.dart';

/// 「固定住民 ID」的日志（v3.9）。
///
/// 住民每次醒来都会留下一条：什么时候、因为什么、醒了多久，
/// 以及有没有给下一次的自己留言。它不是监控面板——页面上的说明也写着
/// “这是 TA 自己的日志”，用户看得到，是在看一个人怎么过日子。
class ResidentWakeLogPage extends ConsumerWidget {
  const ResidentWakeLogPage({super.key, required this.residentId});

  final String residentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resident = ref.watch(customResidentAnyByIdProvider(residentId));
    final logs = ref.watch(residentWakeLogsProvider(residentId));
    final alarms =
        ref.watch(residentAlarmsProvider(residentId)).value ??
        const <ResidentAlarm>[];
    final sleeps =
        ref.watch(residentSleepPeriodsProvider(residentId)).value ??
        const <ResidentSleepPeriod>[];

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${resident?.name ?? '固定住民'}的日志',
              style: TextStyle(
                color: EchoColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              residentId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: EchoColors.textFaint, fontSize: 10.5),
            ),
          ],
        ),
      ),
      body: logs.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: EchoColors.primary)),
        error: (error, _) => Center(
          child: Text(
            '读不到日志：$error',
            style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                if (alarms.isNotEmpty) _AlarmCard(alarms: alarms),
                if (sleeps.isNotEmpty) ...[
                  if (alarms.isNotEmpty) const SizedBox(height: 8),
                  _SleepCard(
                    sleeps: sleeps,
                    onOpen: () => context.push(
                      RoutePaths.residentSleepHistory(residentId),
                    ),
                  ),
                ],
                const SizedBox(height: 80),
                const SizedBox(height: 260, child: _Empty()),
              ],
            );
          }
          final now = DateTime.now();
          final today = list.where((log) => _sameDay(log.wokeAt, now)).toList();
          final older = list.where((log) => !_sameDay(log.wokeAt, now)).toList();
          final latest = list.first;
          final rows = <Widget>[
            if (today.isNotEmpty) ...[
              const _DayHeader(label: '今天'),
              for (final log in today) _LogTile(log: log),
            ] else
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 12, 2, 4),
                child: Text(
                  '今天还没醒过',
                  style: TextStyle(color: EchoColors.textFaint, fontSize: 12),
                ),
              ),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
              _SummaryCard(
                name: resident?.name ?? 'TA',
                todayCount: today.length,
                latest: latest,
              ),
              if (alarms.isNotEmpty) ...[
                const SizedBox(height: 8),
                _AlarmCard(alarms: alarms),
              ],
              if (sleeps.isNotEmpty) ...[
                const SizedBox(height: 8),
                _SleepCard(
                  sleeps: sleeps,
                  onOpen: () => context.push(
                    RoutePaths.residentSleepHistory(residentId),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              ...rows,
              if (older.isNotEmpty) ...[
                const SizedBox(height: 6),
                Center(
                  child: TextButton.icon(
                    onPressed: () => context.push(
                      RoutePaths.residentWakeHistory(residentId),
                    ),
                    icon: const Icon(Icons.history, size: 15),
                    label: Text('查看更早的日志（${older.length} 条）'),
                    style: TextButton.styleFrom(
                      foregroundColor: EchoColors.primary,
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '日志记“醒来的时间、调用了哪些工具、给自己留的话”，'
                '以及每次入睡和醒来的时间；几轮连续的对话会合并成一次，'
                '聊天内容仍然只在私信和评论里。',
                style: TextStyle(
                  color: EchoColors.textFaint,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.name,
    required this.todayCount,
    required this.latest,
  });

  final String name;
  final int todayCount;
  final ResidentWakeLog latest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            todayCount == 0 ? '今天还没醒' : '今天醒了 $todayCount 次',
            style: TextStyle(
              color: EchoColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '最近一次：${_short(latest.wokeAt)} · ${latest.triggerLabel}',
            style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5),
          ),
          if (latest.hasNote) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: EchoColors.surfaceHigh,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '给下一次的自己：「${latest.note.trim()}」',
                style: TextStyle(
                  color: EchoColors.textMuted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _short(DateTime at) =>
      '${at.month}月${at.day}日 ${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}

/// 还没响的闹钟（v4.0）。住民给自己定的时间，用户也能看见——
/// 不是监控，而是“TA 打算什么时候再来”。
class _AlarmCard extends StatelessWidget {
  const _AlarmCard({required this.alarms});

  final List<ResidentAlarm> alarms;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alarm, size: 15, color: EchoColors.primary),
              const SizedBox(width: 6),
              Text(
                alarms.length == 1 ? 'TA 定了一个闹钟' : 'TA 定了 ${alarms.length} 个闹钟',
                style: TextStyle(
                  color: EchoColors.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          for (final alarm in alarms)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${_when(alarm.fireAt)}'
                '${alarm.reason.trim().isEmpty ? '' : ' · ${alarm.reason.trim()}'}',
                style: TextStyle(
                  color: EchoColors.textMuted,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '到点前 3 小时内，如果没有待办，系统不会因为空闲叫醒 TA；'
            '更早的时候照常生活。',
            style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
          ),
        ],
      ),
    );
  }

  static String _when(DateTime at) {
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '${at.month}月${at.day}日 $hh:$mm';
  }
}

/// 睡眠摘要（v50）：主页面只看最近一段，点进去才是全部记录。
class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.sleeps, required this.onOpen});

  final List<ResidentSleepPeriod> sleeps;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final active = sleeps.where((item) => item.isSleeping);
    final current = active.isEmpty ? null : active.first;
    final latest = current ?? sleeps.first;
    return Material(
      color: EchoColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: current != null
                  ? EchoColors.primary.withValues(alpha: 0.35)
                  : EchoColors.divider,
              width: 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.nightlight_round,
                    size: 15,
                    color: EchoColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      current != null ? 'TA 正在睡' : '最近一次睡眠',
                      style: TextStyle(
                        color: EchoColors.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: EchoColors.textFaint,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                _line(latest),
                style: TextStyle(
                  color: EchoColors.textMuted,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
              if (latest.farewell.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  '入睡前说：「${latest.farewell.trim()}」',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: EchoColors.textFaint,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 5),
              Text(
                '共 ${sleeps.length} 段记录 · 点开查看全部',
                style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _line(ResidentSleepPeriod period) => sleepLine(period);
}

/// 睡眠记录的完整一行（摘要卡与二级页共用）。
String sleepLine(ResidentSleepPeriod period) {
  final start = _whenDate(period.startedAt);
  if (period.isSleeping) {
    return '睡梦中 · $start 入睡（${_duration(period.duration)}）';
  }
  final end = period.endedAt == null ? '' : _whenDate(period.endedAt!);
  final endLabel = period.endedByLabel.isEmpty ? '' : ' · ${period.endedByLabel}';
  return '$start → $end（${_duration(period.duration)}）$endLabel';
}

String _whenDate(DateTime at) {
  final hh = at.hour.toString().padLeft(2, '0');
  final mm = at.minute.toString().padLeft(2, '0');
  return '${at.month}月${at.day}日 $hh:$mm';
}

String _duration(Duration span) {
  if (span.inDays > 0) {
    final hours = span.inHours % 24;
    return hours == 0 ? '${span.inDays} 天' : '${span.inDays} 天 $hours 小时';
  }
  if (span.inHours > 0) return '${span.inHours} 小时';
  return span.inMinutes <= 0 ? '不到 1 分钟' : '${span.inMinutes} 分钟';
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Text(
        label,
        style: TextStyle(
          color: EchoColors.textFaint,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});

  final ResidentWakeLog log;

  @override
  Widget build(BuildContext context) {
    final duration = log.awakeFor;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: EchoColors.divider, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${log.wokeAt.hour.toString().padLeft(2, '0')}:'
                '${log.wokeAt.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: EchoColors.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  log.triggerLabel,
                  style: TextStyle(color: EchoColors.textMuted, fontSize: 12),
                ),
              ),
              if (duration != null)
                Text(
                  _durationLabel(duration),
                  style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
                ),
            ],
          ),
          if (log.hasTools) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final entry in _toolCounts(log.tools).entries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: EchoColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.value > 1
                          ? '${entry.key} ×${entry.value}'
                          : entry.key,
                      style: TextStyle(
                        color: EchoColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (log.hasAside) ...[
            const SizedBox(height: 7),
            Text(
              '碎碎念：「${log.aside.trim()}」',
              style: TextStyle(
                color: EchoColors.textMuted,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
          if (log.hasNote) ...[
            const SizedBox(height: 7),
            Text(
              '给下一次的自己：「${log.note.trim()}」',
              style: TextStyle(
                color: EchoColors.textMuted,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 同一轮里同一个工具可能调了好几次；页面按“中文说法 + 次数”合并。
  static Map<String, int> _toolCounts(List<String> tools) {
    final counts = <String, int>{};
    for (final tool in tools) {
      final label = ResidentWakeLog.toolLabel(tool);
      counts[label] = (counts[label] ?? 0) + 1;
    }
    return counts;
  }

  static String _durationLabel(Duration span) {
    if (span.inMinutes <= 0) return '不到 1 分钟';
    if (span.inHours <= 0) return '醒了 ${span.inMinutes} 分钟';
    return '醒了 ${span.inHours} 小时 ${span.inMinutes % 60} 分钟';
  }
}

/// 全部睡眠记录（从日志页的睡眠卡进入）。
class ResidentSleepHistoryPage extends ConsumerWidget {
  const ResidentSleepHistoryPage({super.key, required this.residentId});

  final String residentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resident = ref.watch(customResidentAnyByIdProvider(residentId));
    final sleeps = ref.watch(residentSleepPeriodsProvider(residentId));
    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          '${resident?.name ?? '固定住民'}的睡眠记录',
          style: TextStyle(
            color: EchoColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: sleeps.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: EchoColors.primary)),
        error: (error, _) => Center(
          child: Text(
            '读不到睡眠记录：$error',
            style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: _Empty());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
              for (final period in list)
                _SleepHistoryTile(period: period),
              const SizedBox(height: 10),
              Text(
                '五天没有互动会自动入睡；你也可以在「固定住民 → 右上角月亮」里'
                '手动让 TA 睡。睡着的住民不会被心跳、闹钟或后台叫醒。',
                style: TextStyle(
                  color: EchoColors.textFaint,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SleepHistoryTile extends StatelessWidget {
  const _SleepHistoryTile({required this.period});

  final ResidentSleepPeriod period;

  @override
  Widget build(BuildContext context) {
    final sleeping = period.isSleeping;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: sleeping
              ? EchoColors.primary.withValues(alpha: 0.35)
              : EchoColors.divider,
          width: 0.7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                sleeping ? Icons.nightlight_round : Icons.dark_mode_outlined,
                size: 14,
                color: sleeping ? EchoColors.primary : EchoColors.textFaint,
              ),
              const SizedBox(width: 6),
              Text(
                sleepLine(period),
                style: TextStyle(
                  color: EchoColors.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            period.startedByLabel,
            style: TextStyle(color: EchoColors.textMuted, fontSize: 11.5),
          ),
          if (period.farewell.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              '入睡前说：「${period.farewell.trim()}」',
              style: TextStyle(
                color: EchoColors.textFaint,
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 早期日志（从日志页底部进入）。今天的仍留在主页面。
class ResidentWakeHistoryPage extends ConsumerWidget {
  const ResidentWakeHistoryPage({super.key, required this.residentId});

  final String residentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resident = ref.watch(customResidentAnyByIdProvider(residentId));
    final logs = ref.watch(residentWakeLogsProvider(residentId));
    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          '${resident?.name ?? '固定住民'}的早期日志',
          style: TextStyle(
            color: EchoColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: logs.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: EchoColors.primary)),
        error: (error, _) => Center(
          child: Text(
            '读不到日志：$error',
            style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
          ),
        ),
        data: (list) {
          final now = DateTime.now();
          final older = list
              .where((log) => !ResidentWakeLogPage._sameDay(log.wokeAt, now))
              .toList();
          if (older.isEmpty) {
            return const Center(child: _Empty());
          }
          final rows = <Widget>[];
          DateTime? day;
          for (final log in older) {
            if (day == null || !ResidentWakeLogPage._sameDay(day, log.wokeAt)) {
              day = log.wokeAt;
              rows.add(
                _DayHeader(
                  label: '${log.wokeAt.year}年${log.wokeAt.month}月'
                      '${log.wokeAt.day}日',
                ),
              );
            }
            rows.add(_LogTile(log: log));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              ...rows,
              const SizedBox(height: 10),
              Text(
                '今天的记录在上一页；这里按天保留更早的醒来记录。',
                style: TextStyle(
                  color: EchoColors.textFaint,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.nightlight_round, size: 34, color: EchoColors.textFaint),
            const SizedBox(height: 14),
            Text(
              'TA 还没有醒过。',
              style: TextStyle(color: EchoColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              '等有人跟 TA 说话，或者后台叫醒 TA，这里就会有记录。',
              textAlign: TextAlign.center,
              style: TextStyle(color: EchoColors.textFaint, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
