import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/resident_sleep_repository.dart';
import '../../domain/models/custom_resident.dart';
import '../../domain/models/resident_sleep.dart';
import '../../domain/services/resident_sleep_service.dart';
import '../shared_widgets/user_avatar.dart';

/// 固定住民的睡眠页（v50）。
///
/// 这里只做两件事：让 TA 睡、把 TA 叫醒。真正的“五天没互动自动睡”
/// 由 [ResidentSleepService] 在冷启动/心跳/后台里判断。
class ResidentSleepPage extends ConsumerStatefulWidget {
  const ResidentSleepPage({super.key});

  @override
  ConsumerState<ResidentSleepPage> createState() => _ResidentSleepPageState();
}

class _ResidentSleepPageState extends ConsumerState<ResidentSleepPage> {
  bool _busy = false;

  Future<void> _sleep(ResidentSleepView view) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('让「${view.resident.name}」睡一会儿？'),
        content: const Text(
          'TA 会先留最后一句话，然后进入睡眠。睡着期间不会自己醒来、'
          '不会发动态，也不会收到后台唤醒；你直接发私信、打电话、'
          '约游戏或让 TA 控制桌宠时，TA 会立刻醒来。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('让 TA 睡'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(residentSleepServiceProvider)
          .sleepNow(view.resident.id);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${view.resident.name} 睡下了')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('没能让 TA 睡下：$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _wake(ResidentSleepView view) async {
    setState(() => _busy = true);
    try {
      final notice = await ref
          .read(residentSleepServiceProvider)
          .wakeManually(view.resident.id);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notice == null
                ? '${view.resident.name} 本来就醒着'
                : '${view.resident.name} 醒了，正在回神…',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('没能叫醒 TA：$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 睡眠状态变化时自动刷新列表（手动入睡/唤醒、自动入睡都会触发）。
    final residents =
        ref.watch(customResidentsProvider).value ?? const <CustomResident>[];
    final sleeping = {
      for (final period
          in ref.watch(sleepingResidentsProvider).value ??
              const <ResidentSleepPeriod>[])
        period.residentId: period,
    };
    final now = DateTime.now();
    final list = [
      for (final resident in residents)
        ResidentSleepView(
          resident: resident,
          period: sleeping[resident.id],
          quietFor: now.difference(resident.interactionAnchor),
        ),
    ];
    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          '睡眠',
          style: TextStyle(
            color: EchoColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          const _IntroCard(),
          const SizedBox(height: 12),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Center(
                child: Text(
                  '还没有固定住民。',
                  style: TextStyle(
                    color: EchoColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            for (final view in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _ResidentSleepTile(
                  view: view,
                  busy: _busy,
                  onSleep: () => _sleep(view),
                  onWake: () => _wake(view),
                ),
              ),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        color: EchoColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: EchoColors.primary.withValues(alpha: 0.28),
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
                size: 18,
                color: EchoColors.primary,
              ),
              const SizedBox(width: 7),
              Text(
                '让热闹停在该停的地方',
                style: TextStyle(
                  color: EchoColors.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '连续 5 天没有任何互动，TA 会自动睡下；入睡前会给你留最后一句话。'
            '睡着的住民不会被心跳、闹钟或后台叫醒。'
            '你直接发私信、打电话、约游戏，或者亲手打开它控制的桌宠，'
            '都算“找 TA”，会立刻把 TA 叫醒。发帖和评论别人不算。',
            style: TextStyle(
              color: EchoColors.textMuted,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResidentSleepTile extends StatelessWidget {
  const _ResidentSleepTile({
    required this.view,
    required this.busy,
    required this.onSleep,
    required this.onWake,
  });

  final ResidentSleepView view;
  final bool busy;
  final VoidCallback onSleep;
  final VoidCallback onWake;

  @override
  Widget build(BuildContext context) {
    final period = view.period;
    final sleeping = period != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: sleeping
              ? EchoColors.primary.withValues(alpha: 0.35)
              : EchoColors.divider,
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              UserAvatar(
                name: view.resident.name,
                avatarRef: view.resident.avatarAsset.isEmpty
                    ? null
                    : view.resident.avatarAsset,
                size: 42,
              ),
              if (sleeping)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: EchoColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.nightlight_round,
                      size: 12,
                      color: EchoColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.resident.name,
                  style: TextStyle(
                    color: EchoColors.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  sleeping
                      ? '睡梦中 · 从 ${_when(period.startedAt)} 开始'
                      : _quietLabel(view.quietFor),
                  style: TextStyle(
                    color: sleeping ? EchoColors.primary : EchoColors.textMuted,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
                if (sleeping && period.farewell.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      '「${period.farewell.trim()}」',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: EchoColors.textFaint,
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (sleeping)
            TextButton(
              onPressed: busy ? null : onWake,
              child: const Text('唤醒'),
            )
          else
            TextButton(
              onPressed: busy ? null : onSleep,
              child: const Text('让 TA 睡'),
            ),
        ],
      ),
    );
  }

  static String _quietLabel(Duration quiet) {
    if (quiet.inDays >= 5) {
      return '已经 ${quiet.inDays} 天没互动，下次检查会入睡';
    }
    if (quiet.inDays >= 1) {
      return '醒着 · 已经 ${quiet.inDays} 天没互动';
    }
    final hours = quiet.inHours <= 0 ? 0 : quiet.inHours;
    return hours == 0 ? '醒着 · 刚刚还聊过' : '醒着 · 已经 $hours 小时没互动';
  }

  static String _when(DateTime at) {
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '${at.month}月${at.day}日 $hh:$mm';
  }
}
