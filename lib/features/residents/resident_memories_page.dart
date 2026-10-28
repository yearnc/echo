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
    // 显示用（含已删除，名字不能丢）；改开关用“还在社区里的”。
    final resident = ref.watch(
      customResidentAnyByIdProvider(widget.residentId),
    );
    final activeResident = ref.watch(
      customResidentByIdProvider(widget.residentId),
    );
    final active = ref.watch(activeMemoriesProvider(widget.residentId));
    final archived = ref.watch(archivedMemoriesProvider(widget.residentId));
    final activeCount = active.value?.length ?? 0;
    final archivedCount = archived.value?.length ?? 0;

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
              '${resident?.name ?? '固定住民'}的记忆',
              style: TextStyle(
                color: EchoColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '只有 TA 自己和你在这里看得到',
              style: TextStyle(color: EchoColors.textFaint, fontSize: 10.5),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          _MemoryHero(
            name: resident?.name ?? 'TA',
            enabled: resident?.memoryEnabled ?? true,
            activeCount: activeCount,
            archivedCount: archivedCount,
            limit: resident?.memoryLimit,
            onToggle: activeResident == null
                ? null
                : (value) => ref
                      .read(customResidentRepositoryProvider)
                      .upsert(activeResident.copyWith(memoryEnabled: value)),
          ),
          const SizedBox(height: 16),
          _SegmentedTabs(
            showArchived: _showArchived,
            activeCount: activeCount,
            archivedCount: archivedCount,
            onChanged: (archivedTab) =>
                setState(() => _showArchived = archivedTab),
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

  List<Widget> _buildActive(AsyncValue<List<ResidentMemory>> memories) {
    return memories.when(
      loading: () => [const _LoadingBlock()],
      error: (error, _) => [_ErrorText('读不到记忆：$error')],
      data: (list) {
        if (list.isEmpty) {
          return const [
            _EmptyHint(
              icon: Icons.spa_outlined,
              title: '还没有记住什么',
              text: 'TA 会在翻过你的帖子、跟你在私信里说过话之后，\n自己决定把哪些事写进记忆。',
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
      loading: () => [const _LoadingBlock()],
      error: (error, _) => [_ErrorText('读不到归档：$error')],
      data: (list) {
        if (list.isEmpty) {
          return const [
            _EmptyHint(
              icon: Icons.inventory_2_outlined,
              title: '还没有归档的记忆',
              text: '超过上限时，最早的条目会先移到这里；\n归档不是删除，随时可以恢复。',
            ),
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

/// 页头：把“记住了多少、还能装多少、关没关”一眼说清。
class _MemoryHero extends StatelessWidget {
  const _MemoryHero({
    required this.name,
    required this.enabled,
    required this.activeCount,
    required this.archivedCount,
    required this.limit,
    required this.onToggle,
  });

  final String name;
  final bool enabled;
  final int activeCount;
  final int archivedCount;
  final int? limit;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final capacity = limit == null || limit! <= 0
        ? null
        : (activeCount / limit!).clamp(0.0, 1.0);
    final over = limit != null && limit! > 0 && activeCount >= limit!;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled
              ? EchoColors.primary.withValues(alpha: 0.35)
              : EchoColors.divider,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            EchoColors.surface,
            Color.lerp(
                  EchoColors.surface,
                  enabled ? EchoColors.primary : EchoColors.textFaint,
                  0.09,
                ) ??
                EchoColors.surface,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: EchoColors.primary.withValues(alpha: 0.14),
                  border: Border.all(
                    color: EchoColors.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: enabled ? EchoColors.primary : EchoColors.textFaint,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      enabled ? '$name 记得的事' : '记忆已关闭',
                      style: TextStyle(
                        color: EchoColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? '翻过帖子、聊过天之后，TA 自己决定记什么'
                          : '不再写入，也不再检索；已有条目仍然保留',
                      style: TextStyle(
                        color: EchoColors.textFaint,
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: onToggle,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Stat(value: '$activeCount', label: '记住'),
              _Stat(
                value: limit == null || limit! <= 0 ? '∞' : '$limit',
                label: '上限',
              ),
              _Stat(value: '$archivedCount', label: '已归档'),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: capacity ?? 0.02,
              backgroundColor: EchoColors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation(
                over ? EchoColors.hot : EchoColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            limit == null || limit! <= 0
                ? '没有上限：TA 可以一直记下去'
                : (over
                      ? '已经装满：再记新的，最早的一条会移到归档'
                      : '还能记住 ${(limit! - activeCount).clamp(0, limit!)} 条'),
            style: TextStyle(
              color: EchoColors.textFaint,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: EchoColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          Text(
            label,
            style: TextStyle(color: EchoColors.textFaint, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

/// 两栏切换：记忆 / 已归档。
class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.showArchived,
    required this.activeCount,
    required this.archivedCount,
    required this.onChanged,
  });

  final bool showArchived;
  final int activeCount;
  final int archivedCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Row(
        children: [
          _tab('记忆 $activeCount', !showArchived, () => onChanged(false)),
          _tab(
            archivedCount == 0 ? '已归档' : '已归档 $archivedCount',
            showArchived,
            () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? EchoColors.primary.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? EchoColors.primary.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? EchoColors.primary : EchoColors.textMuted,
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
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
    final style = _SourceStyle.of(memory.source);
    final summary = memory.summary.isNotEmpty ? memory.summary : memory.content;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: EchoColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: archived
                ? EchoColors.divider
                : style.color.withValues(alpha: 0.28),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                color: archived
                    ? EchoColors.textFaint.withValues(alpha: 0.45)
                    : style.color,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 11, 6, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _Badge(
                            icon: style.icon,
                            label: style.label,
                            color: archived ? EchoColors.textFaint : style.color,
                          ),
                          if (archived) ...[
                            const SizedBox(width: 6),
                            _Badge(
                              icon: Icons.inventory_2_outlined,
                              label: '已归档',
                              color: EchoColors.textFaint,
                            ),
                          ],
                          const Spacer(),
                          Text(
                            RelativeTime.format(memory.updatedAt),
                            style: TextStyle(
                              color: EchoColors.textFaint,
                              fontSize: 10.5,
                            ),
                          ),
                          _menu(context),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        summary,
                        style: TextStyle(
                          color: EchoColors.text,
                          fontSize: 13.5,
                          height: 1.55,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (memory.content.isNotEmpty &&
                          memory.content != memory.summary) ...[
                        const SizedBox(height: 5),
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
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final tag in memory.tags)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: EchoColors.surfaceHigh.withValues(
                                    alpha: 0.65,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: EchoColors.divider,
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  '# $tag',
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '更多',
      padding: EdgeInsets.zero,
      iconSize: 18,
      icon: Icon(Icons.more_horiz, color: EchoColors.textFaint),
      color: EchoColors.surfaceHigh,
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit?.call();
          case 'restore':
            onRestore?.call();
          case 'delete':
            onDelete?.call();
        }
      },
      itemBuilder: (context) => [
        if (onEdit != null)
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
        if (onRestore != null)
          const PopupMenuItem(value: 'restore', child: Text('恢复')),
        if (onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: Text('删除', style: TextStyle(color: EchoColors.like)),
          ),
      ],
    );
  }
}

/// 来源的图标与颜色。只回答“从哪来”，不再分“谁说的”。
class _SourceStyle {
  const _SourceStyle({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  static _SourceStyle of(String source) => switch (source) {
    'post' || 'self_post' => _SourceStyle(
      icon: Icons.article_outlined,
      label: '来自帖子',
      color: EchoColors.primary,
    ),
    'comment' || 'self_comment' => _SourceStyle(
      icon: Icons.forum_outlined,
      label: '来自评论',
      color: EchoColors.accent,
    ),
    'dm' || 'self_dm' => _SourceStyle(
      icon: Icons.mail_outline,
      label: '来自私信',
      color: EchoColors.success,
    ),
    'wake' => _SourceStyle(
      icon: Icons.bolt_outlined,
      label: '来自互动',
      color: EchoColors.hot,
    ),
    'call' => _SourceStyle(
      icon: Icons.phone_in_talk_outlined,
      label: '来自通话',
      color: EchoColors.success,
    ),
    'pet' => _SourceStyle(
      icon: Icons.pets_outlined,
      label: '来自桌宠',
      color: EchoColors.primary,
    ),
    'manual' => _SourceStyle(
      icon: Icons.edit_note,
      label: '手动添加',
      color: EchoColors.textMuted,
    ),
    _ => _SourceStyle(
      icon: Icons.bookmark_border,
      label: '记忆',
      color: EchoColors.textMuted,
    ),
  };
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10.5, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: EchoColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: EchoColors.surfaceHigh.withValues(alpha: 0.7),
            ),
            child: Icon(icon, size: 21, color: EchoColors.textFaint),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: EchoColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: EchoColors.textFaint,
              fontSize: 11.5,
              height: 1.75,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(child: CircularProgressIndicator()),
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
