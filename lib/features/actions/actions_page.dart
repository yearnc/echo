import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/clear_journal_repository.dart';
import '../../domain/models/clear_journal.dart';
import '../shared_widgets/permanent_notice_banner.dart';

/// 真实行动记录页（规划书 §4）。
///
/// 与回响模式的信息流放在一起看很有意思：那边每一条都有点赞数，
/// 这边每一条都没有任何数字——唯一的数字是"本周记了几件"，
/// 而那是用户自己数出来的。
///
/// 带颜色的样式一律不加 `const`：[ClearColors] 读的是当前调色板（外观可独立切换），
/// 不是编译期常量。
class ActionsPage extends ConsumerWidget {
  const ActionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncActions = ref.watch(realActionsProvider);

    return Scaffold(
      backgroundColor: ClearColors.bg,
      appBar: AppBar(
        backgroundColor: ClearColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: ClearColors.text),
        title: Text(
          '真实行动',
          style: TextStyle(color: ClearColors.text, fontSize: 16),
        ),
      ),
      bottomNavigationBar: const SafeArea(child: PermanentNoticeBanner()),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context, ref),
        backgroundColor: ClearColors.primary,
        foregroundColor: Colors.white,
        tooltip: '记一件',
        child: const Icon(Icons.add),
      ),
      body: asyncActions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            '读取失败：$error',
            style: TextStyle(color: ClearColors.textMuted, fontSize: 12.5),
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            const _WeeklyBanner(),
            const SizedBox(height: 18),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  '还没有记录。\n想一件今天真的做过的小事——走过的一段路、读完的几页书，都算。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ClearColors.textMuted,
                    fontSize: 13,
                    height: 1.8,
                  ),
                ),
              )
            else
              for (final action in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ActionTile(
                    action: action,
                    onDelete: () => _confirmDelete(context, ref, action),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final draft = await showModalBottomSheet<_ActionDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ClearColors.surface,
      builder: (_) => const _ActionSheet(),
    );
    if (draft == null) return;
    await ref
        .read(clearJournalRepositoryProvider)
        .addAction(
          title: draft.title,
          description: draft.description,
          category: draft.category,
        );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    RealAction action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ClearColors.surface,
        title: Text(
          '删除这条记录',
          style: TextStyle(color: ClearColors.text, fontSize: 15),
        ),
        content: Text(
          '「${action.title}」会从记录里移走。',
          style: TextStyle(
            color: ClearColors.textMuted,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: TextStyle(color: ClearColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('移走', style: TextStyle(color: ClearColors.accent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(clearJournalRepositoryProvider).deleteAction(action.id);
  }
}

/// 本周统计：只有一个数字，且不带任何对比。
class _WeeklyBanner extends ConsumerWidget {
  const _WeeklyBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(weeklyActionCountProvider).value;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ClearColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ClearColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                count == null ? '—' : '$count',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: ClearColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '件事，是这周你真正做过的',
                style: TextStyle(color: ClearColors.text, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '这里不做排名，也不和上周比。',
            style: TextStyle(color: ClearColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.onDelete});

  final RealAction action;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: ClearColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ClearColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: ClearColors.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        action.category.label,
                        style: TextStyle(
                          color: ClearColors.accent,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        action.title,
                        style: TextStyle(
                          color: ClearColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (action.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    action.description,
                    style: TextStyle(
                      color: ClearColors.textMuted,
                      fontSize: 12.5,
                      height: 1.6,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  RelativeTime.format(action.createdAt),
                  style: TextStyle(
                    color: ClearColors.textFaint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.delete_outline,
              size: 17,
              color: ClearColors.textFaint,
            ),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// 新增表单的返回值。
class _ActionDraft {
  const _ActionDraft({
    required this.title,
    required this.description,
    required this.category,
  });

  final String title;
  final String description;
  final RealActionCategory category;
}

/// 新增表单：分类 + 做了什么 + 可选补充。
class _ActionSheet extends StatefulWidget {
  const _ActionSheet();

  @override
  State<_ActionSheet> createState() => _ActionSheetState();
}

class _ActionSheetState extends State<_ActionSheet> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  RealActionCategory _category = RealActionCategory.sport;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '记一件真实做过的事',
            style: TextStyle(
              color: ClearColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              for (final category in RealActionCategory.values)
                ChoiceChip(
                  label: Text(category.label),
                  selected: _category == category,
                  onSelected: (_) => setState(() => _category = category),
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    color: _category == category
                        ? Colors.white
                        : ClearColors.textMuted,
                  ),
                  selectedColor: ClearColors.primary,
                  backgroundColor: ClearColors.surfaceHigh,
                  side: BorderSide(color: ClearColors.divider),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _titleController,
            autofocus: true,
            maxLength: 40,
            style: TextStyle(color: ClearColors.text, fontSize: 14),
            decoration: InputDecoration(
              hintText: '做了什么？比如：跑了 3 公里',
              hintStyle: TextStyle(color: ClearColors.textFaint, fontSize: 13),
              counterStyle: TextStyle(
                color: ClearColors.textFaint,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _descController,
            maxLines: 2,
            maxLength: 80,
            style: TextStyle(color: ClearColors.text, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: '想补充点什么（可不填）',
              hintStyle: TextStyle(color: ClearColors.textFaint, fontSize: 13),
              counterStyle: TextStyle(
                color: ClearColors.textFaint,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final title = _titleController.text.trim();
                if (title.isEmpty) return;
                Navigator.of(context).pop(
                  _ActionDraft(
                    title: title,
                    description: _descController.text.trim(),
                    category: _category,
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: ClearColors.primary,
              ),
              child: const Text('记下'),
            ),
          ),
        ],
      ),
    );
  }
}
