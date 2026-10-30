import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../domain/services/resident_timeline.dart';

/// 「住民的上下文」：唯一时间线的查看与清空（v4.5）。
///
/// 这里展示的是住民**此刻能读到的东西**：屏幕观察、气泡、私信、动作和摘要。
/// 清空只动时间线，不删长期记忆、私信原文和帖子——边界必须写清楚。
final residentContextEventsProvider = StreamProvider.autoDispose
    .family<List<ResidentContextEventRow>, String>((ref, residentId) {
      return ref.watch(residentTimelineProvider).watchEvents(residentId);
    });

class ResidentContextPage extends ConsumerStatefulWidget {
  const ResidentContextPage({super.key, required this.residentId});

  final String residentId;

  @override
  ConsumerState<ResidentContextPage> createState() =>
      _ResidentContextPageState();
}

class _ResidentContextPageState extends ConsumerState<ResidentContextPage> {
  bool _clearing = false;

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: EchoColors.surface,
        title: const Text('清空上下文？'),
        content: const Text(
          '只清空这条“住民能读到的上下文”，不会删除长期记忆、私信原文和帖子。'
          '清空后，旧私信不会自动灌回来；以后新说的话仍然会正常进入上下文。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('先不清'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _clearing = true);
    try {
      await ref
          .read(residentTimelineProvider)
          .clearContext(widget.residentId);
      ref.invalidate(residentContextEventsProvider(widget.residentId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('上下文已清空')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清空失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resident = ref.watch(
      customResidentAnyByIdProvider(widget.residentId),
    );
    final events = ref.watch(
      residentContextEventsProvider(widget.residentId),
    );

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          '${resident?.name ?? '住民'}的上下文',
          style: TextStyle(
            color: EchoColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '清空上下文',
            onPressed: _clearing ? null : _clear,
            icon: _clearing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_outlined, size: 20),
          ),
        ],
      ),
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            '上下文没读出来：$error',
            style: TextStyle(color: EchoColors.like),
          ),
        ),
        data: (rows) {
          final active = rows.where((row) => row.compactedAt == null).toList();
          final tokens = active.fold<int>(0, (sum, row) => sum + row.tokens);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
              _Header(
                total: rows.length,
                active: active.length,
                tokens: tokens,
              ),
              const SizedBox(height: 14),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    '还没有上下文。住民下一次醒来、看屏幕或私信时，'
                    '这里会长出第一条记录。',
                    style: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 12.5,
                      height: 1.6,
                    ),
                  ),
                ),
              for (final row in rows) ...[
                _EventCard(row: row),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.active,
    required this.tokens,
  });

  final int total;
  final int active;
  final int tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '住民现在能读到的上下文',
            style: TextStyle(
              color: EchoColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '共 $total 条记录，其中 $active 条还没被压缩；'
            '约 $tokens token。'
            '已经压缩的旧记录会变灰，但仍留在下面供查看。',
            style: TextStyle(
              color: EchoColors.textMuted,
              fontSize: 11.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.row});

  final ResidentContextEventRow row;

  static const Map<String, String> _labels = {
    'dm_in': '收到私信',
    'dm_out': '发出的私信',
    'screen': '屏幕观察',
    'bubble': '气泡',
    'action': '动作',
    'summary': '摘要',
  };

  @override
  Widget build(BuildContext context) {
    final compacted = row.compactedAt != null;
    final at = DateTime.fromMillisecondsSinceEpoch(row.createdAt);
    final time =
        '${at.month}月${at.day}日 '
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    final isSummary = row.kind == 'summary';
    return Opacity(
      opacity: compacted ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: isSummary ? EchoColors.primary.withValues(alpha: 0.08) : EchoColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSummary
                ? EchoColors.primary.withValues(alpha: 0.25)
                : EchoColors.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _labels[row.kind] ?? row.kind,
                  style: TextStyle(
                    color: isSummary ? EchoColors.primary : EchoColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  time,
                  style: TextStyle(color: EchoColors.textFaint, fontSize: 10.5),
                ),
                if (compacted) ...[
                  const SizedBox(width: 8),
                  Text(
                    '已压缩',
                    style: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 10,
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  '${row.tokens} token',
                  style: TextStyle(color: EchoColors.textFaint, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              row.content,
              style: TextStyle(
                color: EchoColors.text,
                fontSize: 12,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
