import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/clear_journal_repository.dart';
import '../../domain/models/clear_journal.dart';
import '../shared_widgets/permanent_notice_banner.dart';

/// 价值澄清页（规划书 §4）。
///
/// 题目是「写下我真正重视的 5 件事」。位置只有 5 个是**刻意的**——
/// 收集愿望不需要上限，排序才需要。用户被迫取舍的那一刻，
/// 才是这个练习真正开始工作的时候。
///
/// 注意：本文件里凡是带颜色的样式都不加 `const`——
/// [ClearColors] 是指向当前调色板的 getter（外观可以独立切换），不是编译期常量。
class ValuesPage extends ConsumerWidget {
  const ValuesPage({super.key});

  /// 清单上限（规划书定的 5）。
  static const int maxItems = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncItems = ref.watch(valueItemsProvider);
    final items = asyncItems.value ?? const <ValueItem>[];
    final isFull = items.length >= maxItems;

    return Scaffold(
      backgroundColor: ClearColors.bg,
      appBar: AppBar(
        backgroundColor: ClearColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: ClearColors.text),
        title: Text(
          '价值澄清',
          style: TextStyle(color: ClearColors.text, fontSize: 16),
        ),
      ),
      bottomNavigationBar: const SafeArea(child: PermanentNoticeBanner()),
      body: asyncItems.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            '读取失败：$error',
            style: TextStyle(color: ClearColors.textMuted, fontSize: 12.5),
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const _Intro(),
            const SizedBox(height: 18),
            if (list.isEmpty)
              const _EmptyHint()
            else
              for (var i = 0; i < list.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ValueTile(
                    index: i,
                    item: list[i],
                    onEdit: () => _edit(context, ref, list[i]),
                    onMoveUp: i == 0 ? null : () => _move(ref, list, i, i - 1),
                    onMoveDown: i == list.length - 1
                        ? null
                        : () => _move(ref, list, i, i + 1),
                    onDelete: () => _delete(context, ref, list[i]),
                  ),
                ),
            const SizedBox(height: 4),
            if (isFull)
              _FullNotice(onGo: () => context.push(RoutePaths.actions))
            else
              OutlinedButton.icon(
                onPressed: () => _add(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: Text('写下一件（还剩 ${maxItems - list.length} 个位置）'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ClearColors.accent,
                  side: BorderSide(color: ClearColors.divider),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final content = await showDialog<String>(
      context: context,
      builder: (_) => const _TextInputDialog(title: '重视的一件事', hint: '比如：家人的健康'),
    );
    if (content == null || content.trim().isEmpty) return;
    await ref.read(clearJournalRepositoryProvider).addValue(content);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ValueItem item,
  ) async {
    final content = await showDialog<String>(
      context: context,
      builder: (_) => _TextInputDialog(
        title: '修改',
        hint: '改成一个更准确的说法',
        initial: item.content,
      ),
    );
    if (content == null || content.trim().isEmpty) return;
    await ref
        .read(clearJournalRepositoryProvider)
        .updateValueContent(item.id, content);
  }

  /// 上移 / 下移：把数组调整后整体写回顺序。
  ///
  /// 每次重排都全量落库（最多 5 条），比维护相邻两条的 sortOrder 交换简单，
  /// 也不会出现"两条序号一样"的中间态。
  Future<void> _move(
    WidgetRef ref,
    List<ValueItem> items,
    int from,
    int to,
  ) async {
    final ids = items.map((item) => item.id).toList();
    final moved = ids.removeAt(from);
    ids.insert(to, moved);
    await ref.read(clearJournalRepositoryProvider).reorderValues(ids);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ValueItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ClearColors.surface,
        title: Text(
          '删除这一条',
          style: TextStyle(color: ClearColors.text, fontSize: 15),
        ),
        content: Text(
          '「${item.content}」会从清单里移走。',
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
    await ref.read(clearJournalRepositoryProvider).deleteValue(item.id);
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
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
          Text(
            '你真正重视的是什么？',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: ClearColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '只能写 ${ValuesPage.maxItems} 件，所以必须取舍——不是收集愿望，是排序。\n'
            '这份清单不参加任何评比，也不会有人为它点赞。',
            style: TextStyle(
              color: ClearColors.textMuted,
              fontSize: 13,
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Text(
        '还没有写。\n从最不需要犹豫的那一件开始。',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: ClearColors.textMuted,
          fontSize: 13,
          height: 1.8,
        ),
      ),
    );
  }
}

class _ValueTile extends StatelessWidget {
  const _ValueTile({
    required this.index,
    required this.item,
    required this.onEdit,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final int index;
  final ValueItem item;
  final VoidCallback onEdit;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: ClearColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ClearColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ClearColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: ClearColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  item.content,
                  style: TextStyle(
                    color: ClearColors.text,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              color: ClearColors.surfaceHigh,
              icon: Icon(
                Icons.more_vert,
                size: 18,
                color: ClearColors.textFaint,
              ),
              onSelected: (value) => switch (value) {
                'up' => onMoveUp?.call(),
                'down' => onMoveDown?.call(),
                'delete' => onDelete(),
                _ => null,
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'up',
                  enabled: onMoveUp != null,
                  child: const Text('上移', style: TextStyle(fontSize: 13.5)),
                ),
                PopupMenuItem(
                  value: 'down',
                  enabled: onMoveDown != null,
                  child: const Text('下移', style: TextStyle(fontSize: 13.5)),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('移走', style: TextStyle(fontSize: 13.5)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FullNotice extends StatelessWidget {
  const _FullNotice({required this.onGo});

  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ClearColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ClearColors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '5 件都写完了。',
            style: TextStyle(
              color: ClearColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '清单写完不是结束——接下来看它有没有出现在你今天的时间里。',
            style: TextStyle(
              color: ClearColors.textMuted,
              fontSize: 12.5,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onGo,
            style: TextButton.styleFrom(foregroundColor: ClearColors.accent),
            child: const Text('去记一件真实行动 →'),
          ),
        ],
      ),
    );
  }
}

/// 输入对话框。
///
/// 做成 StatefulWidget 是为了让 controller 跟着对话框一起释放——
/// 在 `await showDialog` 之后手动 dispose，输入法的收起动画可能还在用它。
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.hint,
    this.initial = '',
  });

  final String title;
  final String hint;
  final String initial;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ClearColors.surface,
      title: Text(
        widget.title,
        style: TextStyle(color: ClearColors.text, fontSize: 15),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 30,
        maxLines: 1,
        style: TextStyle(color: ClearColors.text, fontSize: 14),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(color: ClearColors.textFaint, fontSize: 13),
          counterStyle: TextStyle(color: ClearColors.textFaint, fontSize: 11),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: ClearColors.divider),
          ),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: ClearColors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text('记下', style: TextStyle(color: ClearColors.accent)),
        ),
      ],
    );
  }
}
