import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/pet_settings_repository.dart';
import '../../domain/models/custom_resident.dart';
import '../../domain/models/pet_settings.dart';
import '../../domain/services/pet_controller.dart';
import '../../domain/services/pet_observe_service.dart';
import '../shared_widgets/user_avatar.dart';
import 'realtime_gap_picker.dart';

/// 「我的 → 桌宠」（v4.0）。
///
/// 形象只有一只，和住民无关；这里选的是“今天由谁控制它”。
/// 时段表优先于默认控制者，同一时刻只会有一位。
class PetPage extends ConsumerStatefulWidget {
  const PetPage({super.key});

  @override
  ConsumerState<PetPage> createState() => _PetPageState();
}

class _PetPageState extends ConsumerState<PetPage> {
  bool _watchRequest = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(petControllerProvider.notifier).refresh();
      final pending = await ref
          .read(petSettingsRepositoryProvider)
          .hasWatchRequest();
      if (mounted) setState(() => _watchRequest = pending);
    });
  }

  Future<void> _toggle(bool value) async {
    final result = value
        ? await ref.read(petControllerProvider.notifier).enable()
        : await ref.read(petControllerProvider.notifier).disable();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Future<void> _toggleRealtime(bool value) async {
    if (value) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          backgroundColor: EchoColors.surface,
          title: const Text('开启实时观察？'),
          content: const Text(
            '桌宠会持续截取屏幕，把最近几帧原图反复发给当前控制住民，'
            '并反复回看。这会比平时消耗多得多的 token。\n\n'
            '关闭时，它会先把这段时间总结成一条记忆，写入成功后才删除截图。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('先不开'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('我明白，开启'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final result = await ref
        .read(petControllerProvider.notifier)
        .setRealtime(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Future<void> _acceptWatchRequest() async {
    await ref.read(petSettingsRepositoryProvider).clearWatchRequest();
    if (mounted) setState(() => _watchRequest = false);
    await _toggleRealtime(true);
  }

  Future<void> _declineWatchRequest() async {
    await ref.read(petSettingsRepositoryProvider).clearWatchRequest();
    if (mounted) setState(() => _watchRequest = false);
  }

  Future<void> _pickRealtimeFrames() async {
    final current = ref.read(petControllerProvider).realtimeFrames;
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: EchoColors.surface,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final count in const [2, 3, 4, 6])
              ListTile(
                title: Text('$count 张'),
                subtitle: count >= 4
                    ? Text(
                        '图片越多，token 消耗越高',
                        style: TextStyle(
                          color: EchoColors.textFaint,
                          fontSize: 11,
                        ),
                      )
                    : null,
                trailing: current == count
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(sheet).pop(count),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await ref
          .read(petControllerProvider.notifier)
          .setRealtimeFrames(selected);
    }
  }

  Future<void> _pickRealtimeGap() async {
    final current = ref.read(petControllerProvider).realtimeGapSeconds;
    final selected = await showRealtimeGapPicker(
      context,
      initialSeconds: current,
    );
    if (selected != null) {
      await ref
          .read(petControllerProvider.notifier)
          .setRealtimeGap(selected);
    }
  }

  Future<void> _pickDefaultResident(List<CustomResident> residents) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: EchoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Text(
                '平时由谁控制桌宠',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            for (final resident in residents)
              ListTile(
                title: Text(resident.name),
                trailing:
                    resident.id ==
                        ref.read(petControllerProvider).defaultResidentId
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(sheet).pop(resident.id),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await ref.read(petControllerProvider.notifier).setDefaultResident(selected);
  }

  Future<void> _addShift(List<CustomResident> residents) async {
    if (residents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先建一位固定住民，再来排班')),
      );
      return;
    }
    String residentId = residents.first.id;
    TimeOfDay start = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 22, minute: 0);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<TimeOfDay?> pick(TimeOfDay initial) =>
              showTimePicker(context: dialogContext, initialTime: initial);
          return AlertDialog(
            backgroundColor: EchoColors.surface,
            title: const Text('加一段值班'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<String>(
                  isExpanded: true,
                  value: residentId,
                  items: [
                    for (final resident in residents)
                      DropdownMenuItem(
                        value: resident.id,
                        child: Text(resident.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => residentId = value);
                  },
                ),
                const SizedBox(height: 14),
                _TimeRow(
                  label: '开始',
                  value: start,
                  onTap: () async {
                    final picked = await pick(start);
                    if (picked != null) setDialogState(() => start = picked);
                  },
                ),
                _TimeRow(
                  label: '结束',
                  value: end,
                  onTap: () async {
                    final picked = await pick(end);
                    if (picked != null) setDialogState(() => end = picked);
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  '开始晚于结束表示跨过零点。',
                  style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialog).pop(true),
                child: const Text('加上'),
              ),
            ],
          );
        },
      ),
    );
    if (saved != true) return;
    await ref
        .read(petSettingsRepositoryProvider)
        .addShift(
          residentId: residentId,
          startMinute: start.hour * 60 + start.minute,
          endMinute: end.hour * 60 + end.minute,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(petControllerProvider);
    final residents =
        ref.watch(customResidentsProvider).value ?? const [];
    final shifts = ref.watch(petShiftsProvider).value ?? const <PetShift>[];
    final byId = {
      for (final resident in residents) resident.id: resident,
    };
    final controller = state.controllerId == null
        ? null
        : byId[state.controllerId];

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          '桌宠',
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
          _StatusCard(
            state: state,
            controllerName: controller?.name,
            controllerAvatar: controller?.avatarAsset,
            onToggle: state.busy ? null : _toggle,
          ),
          if (_watchRequest) ...[
            const SizedBox(height: 10),
            _RequestCard(
              name: controller?.name ?? '控制你的住民',
              onAccept: _acceptWatchRequest,
              onDecline: _declineWatchRequest,
            ),
          ],
          if (!state.overlayGranted) ...[
            const SizedBox(height: 10),
            _HintCard(
              icon: Icons.layers_outlined,
              title: '还差一个悬浮窗权限',
              body: '要让它待在其他应用上面，需要系统里的「显示在其他应用上层」。'
                  '点开启时如果没授权，会自动跳到那个设置页。',
            ),
          ],
          const SizedBox(height: 18),
          const _Section('由谁控制'),
          _Tile(
            icon: Icons.person_outline,
            title: '默认控制者',
            value: controller?.name ?? '还没选',
            onTap: () => _pickDefaultResident(residents),
          ),
          _Tile(
            icon: Icons.schedule,
            title: '按时段值班',
            value: shifts.isEmpty ? '没有排班' : '${shifts.length} 段',
            onTap: () => _addShift(residents),
          ),
          for (final shift in shifts)
            _ShiftRow(
              shift: shift,
              name: byId[shift.residentId]?.name ?? '已离开的住民',
              onDelete: () => ref
                  .read(petSettingsRepositoryProvider)
                  .removeShift(shift.id),
            ),
          const SizedBox(height: 18),
          const _Section('观察'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: state.realtime,
            title: Text(
              '实时观察',
              style: TextStyle(color: EchoColors.text, fontSize: 14),
            ),
            subtitle: Text(
              state.realtime
                  ? '正在持续看屏幕、反复回看。关闭时会先总结写记忆。'
                  : '持续截屏并反复回看，会消耗大量 token。默认关闭。',
              style: TextStyle(color: EchoColors.textMuted, fontSize: 11.5),
            ),
            onChanged: state.busy ? null : _toggleRealtime,
          ),
          _Tile(
            icon: Icons.photo_library_outlined,
            title: '每次观察带几张画面',
            value: '${state.realtimeFrames} 张',
            onTap: _pickRealtimeFrames,
          ),
          _Tile(
            icon: Icons.timer_outlined,
            title: '观察间隔',
            value: formatRealtimeGap(state.realtimeGapSeconds),
            onTap: _pickRealtimeGap,
          ),
          const _ObserveStatusCard(),
          const SizedBox(height: 12),
          Text(
            '桌宠看到的画面只会发给你在「模型配置」里选定的服务商；'
            '截图在关闭实时观察、总结写成功之后删除。锁屏时不会截取。',
            style: TextStyle(
              color: EchoColors.textFaint,
              fontSize: 11.5,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          if (state.error.isNotEmpty)
            Text(
              state.error,
              style: TextStyle(color: EchoColors.like, fontSize: 12),
            ),
          TextButton.icon(
            onPressed: () => context.push(RoutePaths.help),
            icon: const Icon(Icons.help_outline, size: 16),
            label: const Text('桌宠怎么用'),
          ),
        ],
      ),
    );
  }
}

/// 实时观察此刻到底有没有收到画面、有没有真的回看。
/// 这不是“调试面板”，是让用户不用猜“它是不是卡了”。
class _ObserveStatusCard extends ConsumerWidget {
  const _ObserveStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(petObserveServiceProvider);
    return ValueListenableBuilder<PetObserveStatus>(
      valueListenable: service.status,
      builder: (context, value, _) {
        final lines = <String>[
          '已收到 ${value.frames} 帧',
          if (value.lastFrameAt != null)
            '最近一帧：${_clock(value.lastFrameAt!)}',
          '上次观察：${value.lastWake.isEmpty ? '还没有' : value.lastWake}',
        ];
        return Container(
          margin: const EdgeInsets.only(top: 4, bottom: 4),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: EchoColors.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 14,
                    color: EchoColors.textFaint,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '实时观察状态',
                    style: TextStyle(
                      color: EchoColors.textMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                lines.join(' · '),
                style: TextStyle(
                  color: EchoColors.textFaint,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
              if (value.lastError.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  value.lastError,
                  style: TextStyle(color: EchoColors.like, fontSize: 11),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}';
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.state,
    required this.controllerName,
    required this.controllerAvatar,
    required this.onToggle,
  });

  final PetRuntimeState state;
  final String? controllerName;
  final String? controllerAvatar;
  final Future<void> Function(bool)? onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EchoColors.divider, width: 0.8),
      ),
      child: Row(
        children: [
          UserAvatar(
            name: controllerName ?? '桌宠',
            avatarRef: controllerAvatar,
            size: 46,
            showRing: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.enabled ? '正在屏幕上' : '还在休息',
                  style: TextStyle(
                    color: EchoColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  state.enabled
                      ? (controllerName == null
                            ? '暂时没人控制（TA 可能正在通话）'
                            : '现在由 $controllerName 控制')
                      : '打开后它会待在其他应用上层',
                  style: TextStyle(
                    color: EchoColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: state.enabled,
            onChanged: state.busy || onToggle == null
                ? null
                : (value) {
                    onToggle!(value);
                  },
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.name,
    required this.onAccept,
    required this.onDecline,
  });

  final String name;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 12, 10),
      decoration: BoxDecoration(
        color: EchoColors.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: EchoColors.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$name 想申请实时观察',
            style: TextStyle(
              color: EchoColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '同意后会持续截屏并反复回看，token 消耗会明显增加。',
            style: TextStyle(color: EchoColors.textMuted, fontSize: 12),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onDecline, child: const Text('先不要')),
              FilledButton(onPressed: onAccept, child: const Text('同意')),
            ],
          ),
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: EchoColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: EchoColors.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: EchoColors.textMuted,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
      child: Text(
        title,
        style: TextStyle(
          color: EchoColors.textFaint,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 19, color: EchoColors.textMuted),
      title: Text(
        title,
        style: TextStyle(color: EchoColors.text, fontSize: 14),
      ),
      trailing: Text(
        value,
        style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5),
      ),
      onTap: onTap,
    );
  }
}

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({
    required this.shift,
    required this.name,
    required this.onDelete,
  });

  final PetShift shift;
  final String name;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EchoColors.divider, width: 0.7),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 15, color: EchoColors.textFaint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${shift.label} · $name',
              style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: Icon(Icons.close, size: 15, color: EchoColors.textFaint),
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final TimeOfDay value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: Text(
        value.format(context),
        style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
      ),
      onTap: onTap,
    );
  }
}
