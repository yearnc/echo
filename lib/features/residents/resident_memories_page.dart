import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/resident_memory_repository.dart';
import '../../domain/models/resident_memory.dart';

/// 一位固定住民的长期记忆。
///
/// 这一页是"我到底让 TA 记住了什么"的答案：能看、能改、能删，
/// 也能关掉整个记忆。删除只影响以后不再注入，私信与评论原文不动。
class ResidentMemoriesPage extends ConsumerStatefulWidget {
  const ResidentMemoriesPage({super.key, required this.residentId});

  final String residentId;

  @override
  ConsumerState<ResidentMemoriesPage> createState() =>
      _ResidentMemoriesPageState();
}

class _ResidentMemoriesPageState extends ConsumerState<ResidentMemoriesPage> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final resident = ref.watch(customResidentByIdProvider(widget.residentId));
    final active = ref.watch(activeMemoriesProvider(widget.residentId));
    final archived = ref.watch(archivedMemoriesProvider(widget.residentId));

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          '${resident?.name ?? '固定住民'}的记忆',
          style: TextStyle(color: EchoColors.text, fontSize: 16),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _MemoryHeader(
            enabled: resident?.memoryEnabled ?? true,
            activeCount: active.value?.length ?? 0,
            limit: resident?.memoryLimit,
            onToggle: resident == null
                ? null
                : (value) => ref
                      .read(customResidentRepositoryProvider)
                      .upsert(resident.copyWith(memoryEnabled: value)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _TabChip(
                label: '记忆',
                selected: !_showArchived,
                onTap: () => setState(() => _showArchived = false),
              ),
              const SizedBox(width: 8),
              _TabChip(
                label: '已归档${_archivedCount(archived)}',
                selected: _showArchived,
                onTap: () => setState(() => _showArchived = true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_showArchived)
            ..._buildArchived(archived)
          else
            ..._buildActive(active),
        ],
      ),
    );
  }

  String _archivedCount(AsyncValue<List<ResidentMemory>> archived) {
    final count = archived.value?.length ?? 0;
    return count == 0 ? '' : ' $count';
  }

  List<Widget> _buildActive(AsyncValue<List<ResidentMemory>> memories) {
    return memories.when(
      loading: () => [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
      error: (error, _) => [_ErrorText('读不到记忆：$error')],
      data: (list) {
        if (list.isEmpty) {
          return const [
            _EmptyHint(
              '还没有记住什么。\nTA 会在读过你的帖子、跟你在私信里说过话之后开始记。',
            ),
          ];
        }
        return [
          for (final memory in list)
            _MemoryTile(
              memory: memory,
              onEdit: () => _edit(memory),
              onDelete: () => _delete(memory),
            ),
        ];
      },
    );
  }

  List<Widget> _buildArchived(AsyncValue<List<ResidentMemory>> memories) {
    return memories.when(
      loading: () => [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
      error: (error, _) => [_ErrorText('读不到归档：$error')],
      data: (list) {
        if (list.isEmpty) {
          return const [
            _EmptyHint('还没有归档的记忆。\n超过上限时，最早的条目会先移到这里。'),
          ];
        }
        return [
          for (final memory in list)
            _MemoryTile(
              memory: memory,
              archived: true,
              onRestore: () => ref
                  .read(residentMemoryRepositoryProvider)
                  .restore(memory.id),
              onDelete: () => _delete(memory),
            ),
        ];
      },
    );
  }

  Future<void> _edit(ResidentMemory memory) async {
    final summary = TextEditingController(text: memory.summary);
    final content = TextEditingController(text: memory.content);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑这条记忆'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: summary,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '摘要',
                  hintText: '一句话，越短越容易被想起来',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: content,
                maxLines: 5,
                decoration: const InputDecoration(labelText: '原文'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await ref
          .read(residentMemoryRepositoryProvider)
          .updateText(
            id: memory.id,
            summary: summary.text.trim(),
            content: content.text.trim(),
            tags: memory.tags,
          );
    }
    summary.dispose();
    content.dispose();
  }

  Future<void> _delete(ResidentMemory memory) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条记忆？'),
        content: const Text(
          'TA 以后不会再想起这件事。原始私信和评论仍然保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(residentMemoryRepositoryProvider).softDelete(memory.id);
  }
}

class _MemoryHeader extends StatelessWidget {
  const _MemoryHeader({
    required this.enabled,
    required this.activeCount,
    required this.limit,
    required this.onToggle,
  });

  final bool enabled;
  final int activeCount;
  final int? limit;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final limitText = limit == null ? '无上限' : '$limit';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '当前 $activeCount / $limitText',
                style: TextStyle(
                  color: EchoColors.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Switch(
                value: enabled,
                onChanged: onToggle,
              ),
            ],
          ),
          Text(
            enabled
                ? '只记你明确说过的事实和偏好；开启后，相关片段会随对话发送给模型服务商。'
                : '记忆已关闭：不再写入、不再检索，已有条目仍然保留。',
            style: TextStyle(
              color: EchoColors.textFaint,
              fontSize: 11.5,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? EchoColors.primary.withValues(alpha: 0.16)
              : EchoColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? EchoColors.primary : EchoColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? EchoColors.primary : EchoColors.textMuted,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({
    required this.memory,
    this.archived = false,
    this.onEdit,
    this.onDelete,
    this.onRestore,
  });

  final ResidentMemory memory;
  final bool archived;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
        decoration: BoxDecoration(
          color: EchoColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EchoColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _sourceLabel(memory.source),
                  style: TextStyle(
                    color: EchoColors.primary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  RelativeTime.format(memory.updatedAt),
                  style: TextStyle(
                    color: EchoColors.textFaint,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                if (archived && onRestore != null)
                  IconButton(
                    onPressed: onRestore,
                    tooltip: '恢复',
                    icon: Icon(
                      Icons.unarchive_outlined,
                      size: 18,
                      color: EchoColors.textMuted,
                    ),
                  ),
                if (onEdit != null)
                  IconButton(
                    onPressed: onEdit,
                    tooltip: '编辑',
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 17,
                      color: EchoColors.textMuted,
                    ),
                  ),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    tooltip: '删除',
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: EchoColors.textMuted,
                    ),
                  ),
              ],
            ),
            Text(
              memory.summary.isNotEmpty ? memory.summary : memory.content,
              style: TextStyle(
                color: EchoColors.text,
                fontSize: 13.5,
                height: 1.6,
              ),
            ),
            if (memory.content.isNotEmpty &&
                memory.content != memory.summary) ...[
              const SizedBox(height: 4),
              Text(
                memory.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: EchoColors.textMuted,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ],
            if (memory.tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tag in memory.tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: EchoColors.bg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          color: EchoColors.textFaint,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _sourceLabel(String source) => switch (source) {
    // 标签只回答“这条记忆从哪个渠道来”。谁说的、怎么说的，摘要里已经写了，
    // 不必在同一个角标里再分一层“TA 发的 / 你发的”。
    'post' || 'self_post' => '来自帖子',
    'comment' || 'self_comment' => '来自评论',
    'dm' || 'self_dm' => '来自私信',
    'manual' => '手动添加',
    _ => '记忆',
  };
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: EchoColors.textFaint,
          fontSize: 12.5,
          height: 1.8,
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: EchoColors.like, fontSize: 12),
      ),
    );
  }
}
