import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/media/media_service.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/model_config_repository.dart';
import '../../data/repositories/resident_memory_repository.dart';
import '../../domain/models/custom_resident.dart';
import '../../domain/models/model_config.dart';
import '../../domain/services/resident_wake_service.dart';
import '../shared_widgets/user_avatar.dart';

/// 固定住民的完整编辑页。
///
/// 参考酒馆角色卡的分层：基本 / 人设 / 说话 / 行为。
/// 头像从相册导入，不再从内置池里挑。
class CustomResidentEditorPage extends ConsumerStatefulWidget {
  const CustomResidentEditorPage({super.key, this.residentId});

  final String? residentId;

  @override
  ConsumerState<CustomResidentEditorPage> createState() =>
      _CustomResidentEditorPageState();
}

class _CustomResidentEditorPageState
    extends ConsumerState<CustomResidentEditorPage> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _description = TextEditingController();
  final _languageStyle = TextEditingController();
  final _tone = TextEditingController();
  final _exampleDialogue = TextEditingController();
  final _extraInstructions = TextEditingController();
  final _tags = TextEditingController();
  final _memoryLimit = TextEditingController(text: '400');

  String _avatar = '';
  String _modelConfigId = '';
  bool _memory = true;
  bool _alwaysShow = true;
  bool _loading = false;
  bool _saving = false;
  DateTime? _createdAt;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final id = widget.residentId;
    if (id != null) {
      _loading = true;
      _load(id);
    }
  }

  Future<void> _load(String id) async {
    final resident = await ref
        .read(customResidentRepositoryProvider)
        .findById(id);
    if (!mounted) return;
    if (resident == null) {
      setState(() => _loading = false);
      return;
    }
    _name.text = resident.name;
    _bio.text = resident.bio;
    // 旧数据里性格/场景是分开的，编辑页统一并成一段人设。
    _description.text = [
      resident.description,
      resident.personality,
      resident.scenario,
    ].where((part) => part.trim().isNotEmpty).join('\n\n');
    _languageStyle.text = resident.languageStyle;
    _tone.text = resident.tone;
    _exampleDialogue.text = resident.exampleDialogue;
    _extraInstructions.text = resident.extraInstructions;
    _tags.text = resident.tags.join('，');
    _avatar = resident.avatarAsset;
    _modelConfigId = resident.modelConfigId;
    _memory = resident.memoryEnabled;
    _alwaysShow = resident.alwaysShow;
    _memoryLimit.text = resident.memoryLimit?.toString() ?? '';
    _createdAt = resident.createdAt;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _bio,
      _description,
      _languageStyle,
      _tone,
      _exampleDialogue,
      _extraInstructions,
      _tags,
      _memoryLimit,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await ref.read(mediaServiceProvider).pickFromGallery();
    if (picked == null || !mounted) return;
    setState(() => _avatar = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '给 TA 起个名字吧');
      return;
    }

    setState(() {
      _saving = true;
      _nameError = null;
    });

    final limitText = _memoryLimit.text.trim();
    final newLimit = limitText.isEmpty ? null : int.tryParse(limitText);

    // 调低上限：先把"会归档几条"说清楚，别让用户以为记忆被删了。
    final id = widget.residentId;
    if (id != null && newLimit != null) {
      final memories = ref.read(residentMemoryRepositoryProvider);
      final current = await memories.count(id);
      if (current > newLimit) {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('调低记忆上限？'),
            content: Text(
              '当前有 $current 条，将把 ${current - newLimit} 条较早的记忆移入归档。'
              '归档不会删除，之后可以在记忆页手动恢复。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('确认'),
              ),
            ],
          ),
        );
        if (ok != true) {
          if (mounted) setState(() => _saving = false);
          return;
        }
      }
    }

    final resident = CustomResident(
      id: widget.residentId ?? CustomResidentRepository.newId(),
      name: name,
      avatarAsset: _avatar,
      bio: _bio.text.trim(),
      description: _description.text.trim(),
      // 三块人设合并成一段后，旧的两个字段不再由编辑页写入。
      personality: '',
      scenario: '',
      languageStyle: _languageStyle.text.trim(),
      tone: _tone.text.trim(),
      // 开场白这个设置已经去掉：第一句话由住民醒来后自己说。
      firstMessage: '',
      exampleDialogue: _exampleDialogue.text.trim(),
      extraInstructions: _extraInstructions.text.trim(),
      tags: _tags.text
          .split(RegExp(r'[,，\s]+'))
          .where((tag) => tag.trim().isNotEmpty)
          .toList(growable: false),
      memoryEnabled: _memory,
      memoryLimit: newLimit,
      alwaysShow: _alwaysShow,
      modelConfigId: _modelConfigId,
      createdAt: _createdAt ?? DateTime.now(),
    );

    try {
      await ref.read(customResidentRepositoryProvider).upsert(resident);
      if (newLimit != null) {
        await ref
            .read(residentMemoryRepositoryProvider)
            .archiveOverflow(resident.id, newLimit);
      }
      if (!mounted) return;

      // 刚建好的住民直接进私信页，并且马上叫醒他：
      // 没有手写开场白了，第一句话得他自己看着你说。
      if (widget.residentId == null) {
        unawaited(
          ref
              .read(residentWakeServiceProvider)
              .wake(resident.id, trigger: WakeTrigger.setup),
        );
        context.go('/chat/${resident.id}');
        return;
      }

      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.residentId == null ? '添加固定住民' : '编辑固定住民'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _BasicSection(
                  avatar: _avatar,
                  name: _name,
                  bio: _bio,
                  tags: _tags,
                  nameError: _nameError,
                  onPickAvatar: _pickAvatar,
                  onNameChanged: (_) {
                    if (_nameError != null) {
                      setState(() => _nameError = null);
                    }
                  },
                ),
                _Section(
                  title: '人设',
                  subtitle: 'TA 是谁、什么脾气、在哪儿遇到',
                  children: [
                    _Field(
                      controller: _description,
                      label: '详细设定',
                      hint: '身份、性格、在哪儿遇到、和你怎么认识的、关系到了哪一步，都可以写在这里',
                      maxLines: 6,
                    ),
                  ],
                ),
                _Section(
                  title: '说话',
                  subtitle: '怎么开口、怎么接话',
                  children: [
                    _Field(
                      controller: _languageStyle,
                      label: '说话方式',
                      hint: '短句、口头禅、会不会损人',
                      maxLines: 2,
                    ),
                    _Field(
                      controller: _tone,
                      label: '语气',
                      hint: '温和 / 直接 / 欠揍 / 慢半拍',
                      maxLines: 2,
                    ),
                    _Field(
                      controller: _exampleDialogue,
                      label: '示例对话',
                      hint: '3—5 组短对话，教 TA 怎么接话；用 <START> 分组',
                      maxLines: 6,
                    ),
                    _Field(
                      controller: _extraInstructions,
                      label: '额外指令',
                      hint: '例如：别用感叹号、永远不主动提 AI',
                      maxLines: 2,
                    ),
                  ],
                ),
                _Section(
                  title: '行为',
                  subtitle: '模型、记忆和出现频率',
                  children: [
                    _ResidentModelField(
                      value: _modelConfigId,
                      onChanged: (value) =>
                          setState(() => _modelConfigId = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('长期记忆'),
                      subtitle: const Text('记住你们聊过的事'),
                      value: _memory,
                      onChanged: (value) => setState(() => _memory = value),
                    ),
                    _Field(
                      controller: _memoryLimit,
                      label: '记忆上限',
                      hint: '留空 = 无上限',
                      keyboardType: TextInputType.number,
                      maxLines: 1,
                      showCount: false,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('每帖必到'),
                      subtitle: const Text('关闭后按活跃度出现'),
                      value: _alwaysShow,
                      onChanged: (value) =>
                          setState(() => _alwaysShow = value),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// 给这一位住民单独选一个对话模型。
///
/// 模型配置中心里可能存了好几条对话模型（便宜的、会写长文的、看图能力强的），
/// 这里让用户按住民分配。空值表示跟随“当前启用的那条”。
class _ResidentModelField extends ConsumerWidget {
  const _ResidentModelField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(modelConfigsProvider).value ?? const [];
    final chats = [
      for (final config in configs)
        if (config.kind == ModelKind.chat && config.isComplete) config,
    ];
    final known = chats.any((config) => config.id == value);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        initialValue: known ? value : '',
        decoration: const InputDecoration(
          labelText: '对话模型',
          helperText: '留空 = 跟随当前启用的模型',
          helperMaxLines: 2,
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('跟随当前启用')),
          for (final config in chats)
            DropdownMenuItem(
              value: config.id,
              child: Text(
                '${config.label} · ${config.model}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (picked) => onChanged(picked ?? ''),
      ),
    );
  }
}

class _BasicSection extends StatelessWidget {
  const _BasicSection({
    required this.avatar,
    required this.name,
    required this.bio,
    required this.tags,
    required this.nameError,
    required this.onPickAvatar,
    required this.onNameChanged,
  });

  final String avatar;
  final TextEditingController name;
  final TextEditingController bio;
  final TextEditingController tags;
  final String? nameError;
  final VoidCallback onPickAvatar;
  final ValueChanged<String> onNameChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: onPickAvatar,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      UserAvatar(
                        name: name.text,
                        avatarRef: avatar.isEmpty ? null : avatar,
                        size: 72,
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_library_outlined,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: name,
                    onChanged: onNameChanged,
                    decoration: InputDecoration(
                      labelText: '昵称',
                      hintText: '例如：小满',
                      errorText: nameError,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Field(
              controller: bio,
              label: '一句话简介',
              hint: '列表里显示：住楼下，爱拍照',
              maxLines: 1,
            ),
            _Field(
              controller: tags,
              label: '标签',
              hint: '游戏搭子、夜猫子、爱吐槽（逗号分隔，不发给模型）',
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.showCount = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              alignLabelWithHint: maxLines > 1,
            ),
          ),
          if (showCount)
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Text(
                  '${value.text.runes.length} 字',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
