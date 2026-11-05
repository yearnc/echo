import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/knowledge_repository.dart';
import '../../domain/models/custom_resident.dart';
import '../../domain/models/knowledge.dart';
import '../../domain/services/knowledge_update_service.dart';
import '../../domain/services/knowledge_service.dart';

/// 一本知识库的编辑页。
///
/// 名称、给谁看、条目三块分开写：改名字不该顺手改权限，
/// 加一条梗也不该把整本库重新保存一遍。
class KnowledgeEditPage extends ConsumerWidget {
  const KnowledgeEditPage({super.key, required this.baseId});

  final String baseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(knowledgeRepositoryProvider);
    return FutureBuilder<KnowledgeBase?>(
      future: repository.findBase(baseId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: EchoColors.bg,
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final base = snapshot.data;
        if (base == null) {
          return Scaffold(
            backgroundColor: EchoColors.bg,
            appBar: AppBar(
              backgroundColor: EchoColors.surface,
              iconTheme: IconThemeData(color: EchoColors.text),
            ),
            body: Center(
              child: Text(
                '这本知识库已经不在了',
                style: TextStyle(color: EchoColors.textFaint),
              ),
            ),
          );
        }
        return _KnowledgeEditor(base: base);
      },
    );
  }
}

class _KnowledgeEditor extends ConsumerStatefulWidget {
  const _KnowledgeEditor({required this.base});

  final KnowledgeBase base;

  @override
  ConsumerState<_KnowledgeEditor> createState() => _KnowledgeEditorState();
}

class _KnowledgeEditorState extends ConsumerState<_KnowledgeEditor> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late KnowledgeOwnerKind _ownerKind;
  late String _ownerResidentId;
  late bool _autoUpdate;

  bool _transientAll = false;
  bool _residentAll = false;
  final Set<String> _residentTargets = {};

  bool _loaded = false;
  bool _saving = false;
  bool _updating = false;

  /// 流只建一次：每次 build 都 `watchAll()` 会重新订阅，列表会闪。
  late final Stream<List<CustomResident>> _residents;
  late final Stream<List<KnowledgeEntry>> _entries;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.base.name);
    _description = TextEditingController(text: widget.base.description);
    _ownerKind = widget.base.ownerKind;
    _ownerResidentId = widget.base.ownerResidentId;
    _autoUpdate = widget.base.autoUpdate;
    _residents = ref.read(customResidentRepositoryProvider).watchAll();
    _entries = ref
        .read(knowledgeRepositoryProvider)
        .watchEntries(widget.base.id);
    _loadTargets();
  }

  Future<void> _loadTargets() async {
    if (widget.base.isShared) {
      final targets = await ref
          .read(knowledgeRepositoryProvider)
          .listTargets(widget.base.id);
      for (final target in targets) {
        switch (target.kind) {
          case KnowledgeTargetKind.transientAll:
            _transientAll = true;
          case KnowledgeTargetKind.residentAll:
            _residentAll = true;
          case KnowledgeTargetKind.resident:
            _residentTargets.add(target.targetId);
        }
      }
    } else if (widget.base.ownerKind == KnowledgeOwnerKind.resident &&
        widget.base.ownerResidentId.isEmpty) {
      final residents = await ref.read(customResidentRepositoryProvider).all();
      if (residents.isNotEmpty) _ownerResidentId = residents.first.id;
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    // 刚切到「固定住民」但还没选人时，落到第一位，避免保存出一本没人看得到的库。
    var ownerResidentId = _ownerResidentId;
    if (!widget.base.isShared &&
        _ownerKind == KnowledgeOwnerKind.resident &&
        ownerResidentId.isEmpty) {
      final residents = await ref.read(customResidentRepositoryProvider).all();
      if (residents.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('还没有固定住民，先建一位再选')),
        );
        return;
      }
      ownerResidentId = residents.first.id;
      if (mounted) setState(() => _ownerResidentId = ownerResidentId);
    }

    setState(() => _saving = true);
    final repository = ref.read(knowledgeRepositoryProvider);
    try {
      await repository.updateBase(
        widget.base.copyWith(
          name: _name.text.trim(),
          description: _description.text.trim(),
          ownerKind: _ownerKind,
          ownerResidentId: ownerResidentId,
          autoUpdate: _autoUpdate,
        ),
      );
      if (widget.base.isShared) {
        await repository.setTargets(widget.base.id, [
          if (_transientAll)
            KnowledgeTarget(
              baseId: widget.base.id,
              kind: KnowledgeTargetKind.transientAll,
            ),
          if (_residentAll)
            KnowledgeTarget(
              baseId: widget.base.id,
              kind: KnowledgeTargetKind.residentAll,
            ),
          for (final id in _residentTargets)
            KnowledgeTarget(
              baseId: widget.base.id,
              kind: KnowledgeTargetKind.resident,
              targetId: id,
            ),
        ]);
      }
      ref.read(knowledgeServiceProvider).invalidate(baseId: widget.base.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _updateTrendNow() async {
    if (_updating) return;
    setState(() => _updating = true);
    final report = await ref
        .read(knowledgeUpdateServiceProvider)
        .maybeRun(force: true);
    if (!mounted) return;
    setState(() => _updating = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(report.message)));
  }

  Future<void> _deleteBase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这本知识库？'),
        content: const Text('里面的条目会一起删掉；已经生成的评论不会变。'),
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
    if (confirmed != true) return;
    final removed = await ref
        .read(knowledgeRepositoryProvider)
        .deleteBase(widget.base.id);
    if (!mounted) return;
    if (removed) {
      context.pop();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('内置知识库不能删除')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final residents = _residents;
    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          widget.base.isShared ? '共享知识库' : '独立知识库',
          style: TextStyle(color: EchoColors.text, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
          PopupMenuButton<String>(
            color: EchoColors.surfaceHigh,
            onSelected: (value) {
              if (value == 'delete') _deleteBase();
            },
            itemBuilder: (context) => [
              if (!widget.base.builtin)
                const PopupMenuItem(value: 'delete', child: Text('删除这本')),
            ],
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                _Label('名称'),
                TextField(
                  controller: _name,
                  style: TextStyle(color: EchoColors.text),
                  decoration: _decoration('比如：游戏圈、职场'),
                ),
                const SizedBox(height: 14),
                _Label('说明'),
                TextField(
                  controller: _description,
                  maxLines: 3,
                  style: TextStyle(color: EchoColors.text),
                  decoration: _decoration(
                    widget.base.isShared
                        ? '会作为“这本书的视角”注入提示词'
                        : '这些内容是用来干什么的',
                  ),
                ),
                const SizedBox(height: 22),
                if (!widget.base.isShared) ...[
                  _Label('给谁看'),
                  _radio(
                    title: '只服务临时网民',
                    subtitle: '换一本册子，评论区就换一种口气',
                    selected: _ownerKind == KnowledgeOwnerKind.transient,
                    onTap: () => setState(
                      () => _ownerKind = KnowledgeOwnerKind.transient,
                    ),
                  ),
                  _radio(
                    title: '只服务某位固定住民',
                    subtitle: '别的住民看不到',
                    selected: _ownerKind == KnowledgeOwnerKind.resident,
                    onTap: () => setState(
                      () => _ownerKind = KnowledgeOwnerKind.resident,
                    ),
                  ),
                  if (_ownerKind == KnowledgeOwnerKind.resident)
                    StreamBuilder<List<CustomResident>>(
                      stream: residents,
                      builder: (context, snapshot) {
                        final list = snapshot.data ?? const <CustomResident>[];
                        if (list.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '还没有固定住民，先去设置里建一位。',
                              style: TextStyle(
                                color: EchoColors.textFaint,
                                fontSize: 12,
                              ),
                            ),
                          );
                        }
                        final valid = list.any(
                          (item) => item.id == _ownerResidentId,
                        );
                        return DropdownButtonFormField<String>(
                          initialValue: valid ? _ownerResidentId : list.first.id,
                          dropdownColor: EchoColors.surfaceHigh,
                          decoration: _decoration('选择住民'),
                          items: [
                            for (final resident in list)
                              DropdownMenuItem(
                                value: resident.id,
                                child: Text(resident.name),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _ownerResidentId = value);
                            }
                          },
                        );
                      },
                    ),
                ] else ...[
                  _Label('给谁看'),
                  _switch(
                    title: '全体临时网民',
                    subtitle: '生成评论时按人轮换这本册子',
                    value: _transientAll,
                    onChanged: (value) =>
                        setState(() => _transientAll = value),
                  ),
                  _switch(
                    title: '全体固定住民',
                    subtitle: '所有住民都能查、都能写',
                    value: _residentAll,
                    onChanged: (value) => setState(() => _residentAll = value),
                  ),
                  StreamBuilder<List<CustomResident>>(
                    stream: residents,
                    builder: (context, snapshot) {
                      final list = snapshot.data ?? const <CustomResident>[];
                      if (list.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          Text(
                            '指定住民',
                            style: TextStyle(
                              color: EchoColors.textFaint,
                              fontSize: 11,
                            ),
                          ),
                          for (final resident in list)
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                resident.name,
                                style: TextStyle(
                                  color: EchoColors.text,
                                  fontSize: 13,
                                ),
                              ),
                              value: _residentTargets.contains(resident.id),
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _residentTargets.add(resident.id);
                                  } else {
                                    _residentTargets.remove(resident.id);
                                  }
                                });
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
                const SizedBox(height: 22),
                if (widget.base.builtin || widget.base.autoUpdate) ...[
                  _Label('自动更新'),
                  _switch(
                    title: '每周自动更新',
                    subtitle: '用联网搜索找最近的梗，失败时保留旧内容',
                    value: _autoUpdate,
                    onChanged: (value) => setState(() => _autoUpdate = value),
                  ),
                  if (widget.base.builtin)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        onPressed: _updating ? null : _updateTrendNow,
                        icon: _updating
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        label: Text(_updating ? '更新中…' : '立即更新'),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text(
                      '条目',
                      style: TextStyle(
                        color: EchoColors.textFaint,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _editEntry(context, null),
                      icon: const Icon(Icons.add, size: 17),
                      label: const Text('加一条'),
                    ),
                  ],
                ),
                StreamBuilder<List<KnowledgeEntry>>(
                  stream: _entries,
                  builder: (context, snapshot) {
                    final entries = snapshot.data ?? const <KnowledgeEntry>[];
                    if (entries.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: EchoColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: EchoColors.divider),
                        ),
                        child: Text(
                          widget.base.builtin
                              ? '还是空的。点「立即更新」让系统去网上找，或者自己加。'
                              : '还没有条目。',
                          style: TextStyle(
                            color: EchoColors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(
                        color: EchoColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: EchoColors.divider),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < entries.length; i++) ...[
                            if (i > 0)
                              Divider(height: 1, color: EchoColors.divider),
                            _entryRow(context, entries[i]),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _entryRow(BuildContext context, KnowledgeEntry entry) {
    final expired = entry.expiredAt(DateTime.now());
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      title: Row(
        children: [
          Flexible(
            child: Text(
              entry.title,
              style: TextStyle(color: EchoColors.text, fontSize: 14),
            ),
          ),
          if (expired) ...[
            const SizedBox(width: 6),
            Text(
              '已过期',
              style: TextStyle(color: EchoColors.textFaint, fontSize: 10),
            ),
          ],
        ],
      ),
      subtitle: entry.summary.trim().isEmpty
          ? null
          : Text(
              entry.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
            ),
      onTap: () => _editEntry(context, entry),
      trailing: IconButton(
        tooltip: '删除',
        icon: Icon(
          Icons.delete_outline,
          size: 18,
          color: EchoColors.textFaint,
        ),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text('删除「${entry.title}」？'),
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
          await ref.read(knowledgeRepositoryProvider).deleteEntry(entry.id);
          ref
              .read(knowledgeServiceProvider)
              .invalidate(baseId: widget.base.id);
        },
      ),
    );
  }

  Future<void> _editEntry(
    BuildContext context,
    KnowledgeEntry? entry,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EchoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _EntryEditor(
          baseId: widget.base.id,
          entry: entry,
          onSaved: () => ref
              .read(knowledgeServiceProvider)
              .invalidate(baseId: widget.base.id),
        ),
      ),
    );
  }

  Widget _radio({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        size: 20,
        color: selected ? EchoColors.primary : EchoColors.textFaint,
      ),
      title: Text(title, style: TextStyle(color: EchoColors.text, fontSize: 13)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
      ),
      onTap: onTap,
    );
  }

  Widget _switch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: TextStyle(color: EchoColors.text, fontSize: 13)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: EchoColors.textFaint, fontSize: 12.5),
    filled: true,
    fillColor: EchoColors.surface,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: EchoColors.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: EchoColors.primary),
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 7),
      child: Text(
        text,
        style: TextStyle(
          color: EchoColors.textFaint,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 单条知识的编辑表单。examples 一行一条——比让用户写 JSON 现实得多。
class _EntryEditor extends ConsumerStatefulWidget {
  const _EntryEditor({
    required this.baseId,
    required this.entry,
    required this.onSaved,
  });

  final String baseId;
  final KnowledgeEntry? entry;
  final VoidCallback onSaved;

  @override
  ConsumerState<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends ConsumerState<_EntryEditor> {
  late final TextEditingController _title;
  late final TextEditingController _summary;
  late final TextEditingController _content;
  late final TextEditingController _examples;
  late final TextEditingController _tags;
  late final TextEditingController _sourceTitle;
  late final TextEditingController _sourceUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _title = TextEditingController(text: entry?.title ?? '');
    _summary = TextEditingController(text: entry?.summary ?? '');
    _content = TextEditingController(text: entry?.content ?? '');
    _examples = TextEditingController(text: entry?.examples.join('\n') ?? '');
    _tags = TextEditingController(text: entry?.tags.join('，') ?? '');
    _sourceTitle = TextEditingController(text: entry?.sourceTitle ?? '');
    _sourceUrl = TextEditingController(text: entry?.sourceUrl ?? '');
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _summary,
      _content,
      _examples,
      _tags,
      _sourceTitle,
      _sourceUrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先给它起个名字')));
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = KnowledgeEntry(
      id: widget.entry?.id ?? '',
      baseId: widget.baseId,
      title: _title.text.trim(),
      summary: _summary.text.trim(),
      content: _content.text.trim(),
      examples: [
        for (final line in _examples.text.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ],
      tags: [
        for (final tag in _tags.text.split(RegExp(r'[,，\s]+')))
          if (tag.trim().isNotEmpty) tag.trim(),
      ],
      sourceTitle: _sourceTitle.text.trim(),
      sourceUrl: _sourceUrl.text.trim(),
      verifiedAt: widget.entry?.verifiedAt == 0 || widget.entry == null
          ? now
          : widget.entry!.verifiedAt,
      // 人工改过就算重新确认：不再按旧的抓取时间过期。
      expiresAt: 0,
      createdAt: widget.entry?.createdAt ?? now,
    );
    await ref.read(knowledgeRepositoryProvider).upsertEntry(entry);
    widget.onSaved();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.entry == null ? '加一条知识' : '改一条知识',
              style: TextStyle(
                color: EchoColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              style: TextStyle(color: EchoColors.text),
              decoration: _dec('名称，比如：xx梗 / 某个行话'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _summary,
              style: TextStyle(color: EchoColors.text),
              decoration: _dec('一句话：什么意思、什么时候能用'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _content,
              maxLines: 5,
              style: TextStyle(color: EchoColors.text),
              decoration: _dec('来源、用处，讲清楚'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _examples,
              maxLines: 3,
              style: TextStyle(color: EchoColors.text),
              decoration: _dec('例句，一行一条（两三条就够）'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tags,
              style: TextStyle(color: EchoColors.text),
              decoration: _dec('标签，用逗号隔开'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sourceTitle,
                    style: TextStyle(color: EchoColors.text),
                    decoration: _dec('来源名称'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _sourceUrl,
                    style: TextStyle(color: EchoColors.text),
                    decoration: _dec('来源链接'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: EchoColors.textFaint, fontSize: 12.5),
    filled: true,
    fillColor: EchoColors.surfaceHigh,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: EchoColors.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: EchoColors.primary),
    ),
  );
}
