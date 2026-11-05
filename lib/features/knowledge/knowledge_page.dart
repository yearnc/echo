import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/knowledge_repository.dart';
import '../../domain/models/knowledge.dart';

/// 知识库管理（v4.11）。
///
/// 这一页只做三件事：看见有哪些册子、新建一本、点进去改。
/// 独立库和共享库分开展示——它们的"给谁看"不是同一种问题，
/// 混在一个列表里很容易改错人。
class KnowledgePage extends ConsumerWidget {
  const KnowledgePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(knowledgeRepositoryProvider);
    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          '知识库',
          style: TextStyle(color: EchoColors.text, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: '新建知识库',
            icon: Icon(Icons.add, color: EchoColors.text),
            onPressed: () => _create(context, ref),
          ),
        ],
      ),
      body: StreamBuilder<List<KnowledgeBase>>(
        stream: repository.watchBases(),
        builder: (context, snapshot) {
          final bases = snapshot.data ?? const <KnowledgeBase>[];
          if (snapshot.connectionState == ConnectionState.waiting &&
              bases.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final independent = [
            for (final base in bases)
              if (base.scope == KnowledgeScope.independent) base,
          ];
          final shared = [
            for (final base in bases)
              if (base.scope == KnowledgeScope.shared) base,
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              Text(
                '临时网民每人大致带一本册子，说的话就不一样；'
                '固定住民只看到索引，需要细节时自己查。',
                style: TextStyle(
                  color: EchoColors.textFaint,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 18),
              _Section(
                title: '独立知识库',
                empty: '还没有独立知识库。给某类网民或某位住民单独建一本。',
                bases: independent,
                onTap: (base) => context.push(RoutePaths.knowledgeEdit(base.id)),
              ),
              const SizedBox(height: 22),
              _Section(
                title: '共享知识库',
                empty: '还没有共享知识库。可以同时给全体网民、全体住民看。',
                bases: shared,
                onTap: (base) => context.push(RoutePaths.knowledgeEdit(base.id)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final kind = await showModalBottomSheet<_NewKind>(
      context: context,
      backgroundColor: EchoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            for (final option in _NewKind.values)
              ListTile(
                leading: Icon(option.icon, color: EchoColors.textMuted),
                title: Text(
                  option.label,
                  style: TextStyle(color: EchoColors.text, fontSize: 14),
                ),
                subtitle: Text(
                  option.hint,
                  style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
                ),
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (kind == null || !context.mounted) return;

    final name = await _askName(context, kind);
    if (name == null || !context.mounted) return;

    final repository = ref.read(knowledgeRepositoryProvider);
    var residentId = '';
    if (kind == _NewKind.resident) {
      final residents = await ref.read(customResidentRepositoryProvider).all();
      if (residents.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('先在设置里建一位固定住民，再回来建这本')),
        );
        return;
      }
      residentId = residents.first.id;
    }

    final id = await repository.createBase(
      name: name,
      scope: kind.scope,
      ownerKind: kind.ownerKind,
      ownerResidentId: residentId,
    );
    if (!context.mounted) return;
    await context.push(RoutePaths.knowledgeEdit(id));
  }

  Future<String?> _askName(BuildContext context, _NewKind kind) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(kind.label),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '比如：游戏圈、职场、热门梗'),
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return null;
    return result;
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.empty,
    required this.bases,
    required this.onTap,
  });

  final String title;
  final String empty;
  final List<KnowledgeBase> bases;
  final ValueChanged<KnowledgeBase> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: EchoColors.textFaint,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (bases.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: EchoColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: EchoColors.divider),
            ),
            child: Text(
              empty,
              style: TextStyle(
                color: EchoColors.textFaint,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: EchoColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: EchoColors.divider),
            ),
            child: Column(
              children: [
                for (var i = 0; i < bases.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: EchoColors.divider),
                  _BaseRow(base: bases[i], onTap: () => onTap(bases[i])),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _BaseRow extends StatelessWidget {
  const _BaseRow({required this.base, required this.onTap});

  final KnowledgeBase base;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final updated = base.lastUpdatedAt > 0
        ? '更新于 ${RelativeTime.format(DateTime.fromMillisecondsSinceEpoch(base.lastUpdatedAt))}'
        : (base.builtin ? '还没更新过' : '还没写过条目');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(
              base.builtin ? Icons.auto_awesome_outlined : Icons.menu_book_outlined,
              size: 19,
              color: EchoColors.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          base.name,
                          style: TextStyle(
                            color: EchoColors.text,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (base.builtin) ...[
                        const SizedBox(width: 6),
                        _Tag(text: '内置'),
                      ],
                      if (base.autoUpdate) ...[
                        const SizedBox(width: 6),
                        _Tag(text: '每周更新'),
                      ],
                      if (!base.enabled) ...[
                        const SizedBox(width: 6),
                        _Tag(text: '已停用'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    base.description.trim().isEmpty
                        ? '（没有说明）'
                        : base.description.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    updated,
                    style: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: EchoColors.textFaint),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: EchoColors.surfaceHigh,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(color: EchoColors.textFaint, fontSize: 9.5),
      ),
    );
  }
}

enum _NewKind {
  transient(
    '独立 · 只服务临时网民',
    '换一本册子，评论区就换一种口气',
    Icons.people_outline,
    KnowledgeScope.independent,
    KnowledgeOwnerKind.transient,
  ),
  resident(
    '独立 · 只服务固定住民',
    '只给某一位住民看，别人不知道',
    Icons.person_outline,
    KnowledgeScope.independent,
    KnowledgeOwnerKind.resident,
  ),
  shared(
    '共享',
    '自己选给谁看：全体网民、全体住民或指定住民',
    Icons.public_outlined,
    KnowledgeScope.shared,
    KnowledgeOwnerKind.transient,
  );

  const _NewKind(
    this.label,
    this.hint,
    this.icon,
    this.scope,
    this.ownerKind,
  );

  final String label;
  final String hint;
  final IconData icon;
  final KnowledgeScope scope;
  final KnowledgeOwnerKind ownerKind;
}
