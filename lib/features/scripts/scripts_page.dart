import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/plan_script_repository.dart';
import '../../data/seed/builtin_plan_scripts.dart';
import '../../domain/models/plan_script.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';

/// 策划脚本管理页。
///
/// 脚本是"可保留的资产"：内置三幕 + 用户自建都在这里，能改名、能编辑、
/// 能复制一份再改、能删。内置脚本不允许删除，免得手滑之后找不回三幕。
class ScriptsPage extends ConsumerWidget {
  const ScriptsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scripts = ref.watch(planScriptsProvider);

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          '策划脚本',
          style: TextStyle(color: EchoColors.text, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: '重置内置脚本',
            icon: const Icon(Icons.restore),
            onPressed: () => _restoreBuiltIns(context, ref),
          ),
          IconButton(
            tooltip: '新建脚本',
            icon: const Icon(Icons.add),
            onPressed: () => _create(context, ref),
          ),
        ],
      ),
      bottomNavigationBar: const SafeArea(child: AiDisclaimerBar()),
      body: scripts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            '读取失败：$error',
            style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5),
          ),
        ),
        data: (list) => list.isEmpty
            ? _EmptyState(onCreate: () => _create(context, ref))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: list.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: EchoColors.divider),
                itemBuilder: (context, index) =>
                    _ScriptTile(script: list[index]),
              ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final script = PlanScript(
      id: PlanScriptRepository.newId(),
      name: '新脚本',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await ref.read(planScriptRepositoryProvider).save(script);
    if (!context.mounted) return;
    context.push(RoutePaths.scriptEdit(script.id));
  }

  /// 内置脚本删了也能找回来——所以删除不该有心理负担。
  ///
  /// 顺带把改动过的内置脚本刷新回出厂版本：脚本定义会随功能一起长，
  /// 老库里那份不会自己更新。已经下线的内置脚本（比如第三幕）也会在这一步
  /// 被清掉，所以这是一次真删，先弹确认说清楚。
  ///
  /// 自己复制的副本不受影响。
  Future<void> _restoreBuiltIns(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EchoColors.surface,
        title: Text(
          '重置内置脚本',
          style: TextStyle(color: EchoColors.text, fontSize: 15),
        ),
        content: Text(
          '内置脚本会被还原成出厂版本（包括你直接改过的内容）。\n'
          '已经下线的内置脚本会一起清掉；你自己复制出来的副本不受影响。',
          style: TextStyle(
            color: EchoColors.textMuted,
            fontSize: 13,
            height: 1.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: TextStyle(color: EchoColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('重置', style: TextStyle(color: EchoColors.primary)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final builtIns = await BuiltinPlanScripts.load();
    final result = await ref
        .read(planScriptRepositoryProvider)
        .restoreBuiltIns(builtIns);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_restoreMessage(result))));
  }

  /// 报"动了什么"而不是"做完了"：刷新了几个、下线了几个，一眼能对上。
  static String _restoreMessage(({int written, int removed}) result) {
    final parts = [
      if (result.written > 0) '刷新 ${result.written} 个',
      if (result.removed > 0) '下线 ${result.removed} 个',
    ];
    return parts.isEmpty ? '内置脚本已是最新，没有要动的' : '内置脚本：${parts.join('、')}';
  }
}

class _ScriptTile extends ConsumerWidget {
  const _ScriptTile({required this.script});

  final PlanScript script;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = script.postContent.replaceAll('\n', ' ');
    final summary = preview.isEmpty
        ? '没有开局内容'
        : (preview.length > 24 ? '${preview.substring(0, 24)}…' : preview);

    return ListTile(
      onTap: () => context.push(RoutePaths.scriptEdit(script.id)),
      title: Row(
        children: [
          if (script.isBuiltIn) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: EchoColors.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '内置',
                style: TextStyle(color: EchoColors.primary, fontSize: 10),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              script.name,
              style: TextStyle(color: EchoColors.text, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          '${script.steps.length} 个事件 · $summary',
          style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '复制',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.copy_outlined,
              size: 17,
              color: EchoColors.textMuted,
            ),
            onPressed: () => _duplicate(context, ref),
          ),
          IconButton(
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.delete_outline,
              size: 17,
              color: EchoColors.textMuted,
            ),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _duplicate(BuildContext context, WidgetRef ref) async {
    final copy = script.copyWith(
      id: PlanScriptRepository.newId(),
      name: '${script.name} 副本',
      isBuiltIn: false,
      createdAt: 0,
    );
    await ref.read(planScriptRepositoryProvider).save(copy);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EchoColors.surface,
        title: Text(
          '删除脚本',
          style: TextStyle(color: EchoColors.text, fontSize: 15),
        ),
        content: Text(
          script.isBuiltIn
              ? '「${script.name}」是内置脚本。删掉之后可以用右上角的「恢复内置脚本」找回来，'
                    '已经发出去的帖子不受影响。'
              : '「${script.name}」将被删除，已经发出去的帖子不受影响。',
          style: TextStyle(
            color: EchoColors.textMuted,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: TextStyle(color: EchoColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('删除', style: TextStyle(color: EchoColors.like)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(planScriptRepositoryProvider).delete(script.id);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '还没有脚本\n新建一个，写下"发帖后第几秒发生什么"。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: EchoColors.textMuted,
              fontSize: 13,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onCreate, child: const Text('新建脚本')),
        ],
      ),
    );
  }
}
