import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/media/media_service.dart';
import '../../data/repositories/plan_script_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../domain/models/echo_settings.dart';
import '../../domain/models/plan_script.dart';
import '../../domain/services/mode_controller.dart';
import '../../domain/services/scheduler_service.dart';

/// 发布页（规划书 §6.1）。
///
/// 阶段 A 只做发布本身：文字、图片、话题，以及回响模式下那组
/// "你能决定别人怎么回应你"的旋钮（回复频率 / 点赞量 / 拟人程度）。
/// 这组旋钮放在发布页而不是深层设置里，是刻意的——它让"我在安排反馈"这件事
/// 在每一次发帖时都被看见一次。
class ComposePage extends ConsumerStatefulWidget {
  const ComposePage({super.key});

  @override
  ConsumerState<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends ConsumerState<ComposePage> {
  final TextEditingController _controller = TextEditingController();
  String _topic = '日常';
  String _density = '中';
  String _likeLevel = '中';
  int _humanLevel = 3;
  bool _publishing = false;

  /// 策划模式：勾上之后不再随机排期，改按选中的脚本执行。
  bool _planMode = false;
  PlanScript? _script;

  /// 脚本选择弹窗是否已经开着（防止连点叠出好几层）。
  bool _sheetOpen = false;

  /// 已附图（`file:` 引用，已复制进 APP 私有目录）
  final List<String> _imageRefs = [];

  static const List<String> _topics = ['日常', '随手拍', '学习', '运动', '深夜', '吐槽'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(modeControllerProvider);
    final isEcho = mode.isEcho;
    // 在这里订阅脚本列表：一是让 stream 及时发值，二是点「选择」时能立刻用上，
    // 不用等一次异步往返（那一下会让人以为按钮坏了）。
    final scripts =
        ref.watch(planScriptsProvider).value ?? const <PlanScript>[];

    return Container(
      color: isEcho ? EchoColors.bg : ClearColors.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            isEcho ? '发布' : '记录',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: isEcho ? EchoColors.text : ClearColors.text,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isEcho ? '说点什么，会有人回应你的。' : '写下一件今天真实发生的事。',
            style: TextStyle(
              color: isEcho ? EchoColors.textMuted : ClearColors.textMuted,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 7,
            minLines: 5,
            style: TextStyle(
              color: isEcho ? EchoColors.text : ClearColors.text,
              height: 1.6,
            ),
            decoration: InputDecoration(
              hintText: isEcho ? '今天想说什么…' : '今天真实发生的一件小事…',
              fillColor: isEcho ? EchoColors.surfaceHigh : ClearColors.surface,
            ),
          ),
          const SizedBox(height: 12),
          _AttachRow(
            images: _imageRefs,
            isEcho: isEcho,
            onPick: _pickImage,
            onRemove: _removeImage,
          ),
          const SizedBox(height: 18),
          if (isEcho) ...[
            const _SectionLabel('策划模式'),
            _PlanModeCard(
              enabled: _planMode,
              script: _script,
              onToggle: (value) => _togglePlanMode(value, scripts),
              onPick: () => _pickScript(scripts),
              onManage: () => context.push(RoutePaths.scripts),
            ),
            const SizedBox(height: 20),
            if (!_planMode) ...[
              const _SectionLabel('你希望它被怎么对待'),
              _SettingRow(
                label: '回复频率',
                value: _density,
                options: const ['低', '中', '高', '自动'],
                onChanged: (v) => setState(() => _density = v),
              ),
              _SettingRow(
                label: '点赞量',
                value: _likeLevel,
                options: const ['低', '中', '高', '自动'],
                onChanged: (v) => setState(() => _likeLevel = v),
              ),
              _SettingRow(
                label: '拟人程度',
                value: '$_humanLevel 档',
                options: const ['1', '2', '3', '4', '5'],
                onChanged: (v) => setState(() => _humanLevel = int.parse(v)),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: EchoColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: EchoColors.divider),
                ),
                child: Text(
                  '这些设置只影响 AI 生成内容的表现形式。反馈会在 0—48 小时内随机出现。',
                  style: TextStyle(
                    color: EchoColors.textFaint,
                    fontSize: 11.5,
                    height: 1.6,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const _SectionLabel('话题'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final topic in _topics)
                  _ChoiceChip(
                    label: '#$topic',
                    selected: _topic == topic,
                    onTap: () => setState(() => _topic = topic),
                  ),
              ],
            ),
          ] else
            const _ClearModeNote(),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _publishing ? null : _publish,
              style: isEcho
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: ClearColors.primary,
                    ),
              child: Text(_publishing ? '保存中…' : (isEcho ? '发布' : '记录')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final imageRef = await ref.read(mediaServiceProvider).pickFromGallery();
      if (imageRef == null || !mounted) return;
      setState(() => _imageRefs.add(imageRef));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('选图失败：$error')));
    }
  }

  Future<void> _removeImage(String imageRef) async {
    setState(() => _imageRefs.remove(imageRef));
    await ref.read(mediaServiceProvider).deleteByRef(imageRef);
  }

  Future<void> _togglePlanMode(bool value, List<PlanScript> scripts) async {
    if (!value) {
      setState(() => _planMode = false);
      return;
    }

    setState(() => _planMode = true);
    if (_script != null) return;

    // 打开策划模式就先把脚本选上，省得用户面对一个空选择框
    if (scripts.isNotEmpty) {
      _applyScript(scripts.first, withContent: false);
      return;
    }

    // 刚启动那一瞬间列表可能还没到，等一次
    final loaded = await ref.read(planScriptsProvider.future);
    if (!mounted || loaded.isEmpty) return;
    _applyScript(loaded.first, withContent: false);
  }

  /// 选中脚本：把它的开局内容填进编辑区（用户仍然可以改）。
  void _applyScript(PlanScript script, {bool withContent = true}) {
    setState(() {
      _script = script;
      if (!withContent) return;
      if (script.postContent.isNotEmpty) _controller.text = script.postContent;
      if (script.topicName != null) _topic = script.topicName!;
      if (script.postImages.isNotEmpty) {
        _imageRefs
          ..clear()
          ..addAll(script.postImages);
      }
    });
  }

  Future<void> _pickScript(List<PlanScript> scripts) async {
    // 防手快：连点会叠出一摞 bottom sheet
    if (_sheetOpen) return;
    _sheetOpen = true;

    // 绝大多数时候列表已经在手上，直接弹；只有刚启动那一帧还没读到才等一下
    final available = scripts.isNotEmpty
        ? scripts
        : await ref.read(planScriptsProvider.future);

    if (!mounted) {
      _sheetOpen = false;
      return;
    }
    if (available.isEmpty) {
      _sheetOpen = false;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('还没有脚本，去「管理脚本」新建一个吧')));
      return;
    }

    final picked = await showModalBottomSheet<PlanScript>(
      context: context,
      backgroundColor: EchoColors.surface,
      builder: (_) => _ScriptSheet(scripts: available, currentId: _script?.id),
    );
    _sheetOpen = false;

    if (picked == null || !mounted) return;
    _applyScript(picked);
  }

  Future<void> _publish() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先写点什么吧')));
      return;
    }

    setState(() => _publishing = true);
    final isEcho = ref.read(modeControllerProvider).isEcho;
    final script = isEcho && _planMode ? _script : null;

    try {
      final postId = await ref
          .read(postRepositoryProvider)
          .create(
            content: text,
            images: List.of(_imageRefs),
            topicName: isEcho ? _topic : null,
            // 回响模式的帖子进入 echo 作用域；清醒模式的记录进入 clear
            scope: isEcho ? 'echo' : 'clear',
            allowAiReply: isEcho,
            replyDensity: isEcho ? _density : null,
            likeLevel: isEcho ? _likeLevel : null,
            humanLevel: isEcho ? _humanLevel : null,
          );

      // 回响模式：发帖的同时就把将来的互动排好队（离线也不会丢）
      if (isEcho) {
        final scheduler = ref.read(schedulerServiceProvider);
        if (script != null) {
          // 策划模式：按脚本的秒级时间点精确排期
          await scheduler.planFromScript(postId: postId, script: script);
        } else {
          await scheduler.planForPost(
            postId: postId,
            settings: EchoSettings(
              density: ReplyDensity.fromLabel(_density),
              likeLevel: LikeLevel.fromLabel(_likeLevel),
              humanLevel: HumanLevel.fromValue(_humanLevel),
            ),
          );
        }
      }

      if (!mounted) return;
      _controller.clear();
      setState(() {
        _imageRefs.clear();
        _publishing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // 只说"发布成功"就够了：反馈什么时候来是机制，不是用户此刻需要读的东西
          content: Text(isEcho ? '发布成功' : '已记录。'),
        ),
      );
      context.go(isEcho ? RoutePaths.feed : RoutePaths.records);
    } catch (error) {
      if (!mounted) return;
      setState(() => _publishing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }
}

class _AttachRow extends StatelessWidget {
  const _AttachRow({
    required this.images,
    required this.isEcho,
    required this.onPick,
    required this.onRemove,
  });

  final List<String> images;
  final bool isEcho;
  final VoidCallback onPick;
  final ValueChanged<String> onRemove;

  static const int _maxImages = 9;

  @override
  Widget build(BuildContext context) {
    final surface = isEcho ? EchoColors.surface : ClearColors.surface;
    final divider = isEcho ? EchoColors.divider : ClearColors.divider;
    final muted = isEcho ? EchoColors.textMuted : ClearColors.textMuted;

    return SizedBox(
      height: 68,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          InkWell(
            onTap: images.length >= _maxImages ? null : onPick,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: divider),
              ),
              child: Icon(
                Icons.add_photo_alternate_outlined,
                color: images.length >= _maxImages ? divider : muted,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          for (final ref in images)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Thumbnail(
                ref: ref,
                divider: divider,
                onRemove: () => onRemove(ref),
              ),
            ),
          if (images.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Center(
                child: Text(
                  '最多 $_maxImages 张图',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.ref,
    required this.divider,
    required this.onRemove,
  });

  final String ref;
  final Color divider;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final file = ref.startsWith('file:') ? File(ref.substring(5)) : null;

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 68,
            height: 68,
            child: file == null || !file.existsSync()
                ? Container(color: divider)
                : Image.file(file, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          right: 2,
          top: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
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

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? EchoColors.primary.withValues(alpha: 0.16)
              : EchoColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? EchoColors.primary.withValues(alpha: 0.5)
                : EchoColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: selected ? EchoColors.primary : EchoColors.textMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 7,
              children: [
                for (final option in options)
                  GestureDetector(
                    onTap: () => onChanged(option),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: value.startsWith(option)
                            ? EchoColors.primary.withValues(alpha: 0.18)
                            : EchoColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: value.startsWith(option)
                              ? EchoColors.primary.withValues(alpha: 0.5)
                              : EchoColors.divider,
                        ),
                      ),
                      child: Text(
                        option,
                        style: TextStyle(
                          fontSize: 12,
                          color: value.startsWith(option)
                              ? EchoColors.primary
                              : EchoColors.textMuted,
                        ),
                      ),
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

class _ClearModeNote extends StatelessWidget {
  const _ClearModeNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ClearColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ClearColors.divider),
      ),
      child: Text(
        '清醒模式下不会生成任何虚拟反馈。如果想看看内容的客观分析，可以在发布后进入「分析」页。',
        style: TextStyle(
          color: ClearColors.textMuted,
          fontSize: 12,
          height: 1.6,
        ),
      ),
    );
  }
}

/// 发布页的「策划模式」开关与脚本入口。
///
/// 打开它，这条帖子就不走随机排期，而是按脚本里写好的秒数逐条执行；
/// 关掉它，那三个旋钮（回复频率/点赞量/拟人程度）才重新生效。
class _PlanModeCard extends StatelessWidget {
  const _PlanModeCard({
    required this.enabled,
    required this.script,
    required this.onToggle,
    required this.onPick,
    required this.onManage,
  });

  final bool enabled;
  final PlanScript? script;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPick;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled
              ? EchoColors.primary.withValues(alpha: 0.5)
              : EchoColors.divider,
        ),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: onToggle,
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(
              '按脚本安排互动',
              style: TextStyle(color: EchoColors.text, fontSize: 13.5),
            ),
            subtitle: Text(
              '精确到发帖后第几秒：谁点赞、谁评论',
              style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
            ),
          ),
          if (enabled) ...[
            Divider(height: 1, color: EchoColors.divider),
            InkWell(
              onTap: onPick,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                child: Row(
                  children: [
                    Icon(
                      Icons.theater_comedy_outlined,
                      size: 16,
                      color: EchoColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        script?.name ?? '选一个脚本',
                        style: TextStyle(
                          color: script == null
                              ? EchoColors.textMuted
                              : EchoColors.text,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '选择',
                      style: TextStyle(color: EchoColors.primary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: EchoColors.divider),
            InkWell(
              onTap: onManage,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 11, 12, 11),
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 16, color: EchoColors.textMuted),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '管理脚本',
                        style: TextStyle(color: EchoColors.text, fontSize: 13),
                      ),
                    ),
                    Text(
                      '编辑',
                      style: TextStyle(
                        color: EchoColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 脚本选择弹窗。
class _ScriptSheet extends StatelessWidget {
  const _ScriptSheet({required this.scripts, required this.currentId});

  final List<PlanScript> scripts;
  final String? currentId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '选择脚本',
              style: TextStyle(
                color: EchoColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: scripts.length,
              itemBuilder: (context, index) {
                final script = scripts[index];
                final selected = script.id == currentId;
                return ListTile(
                  dense: true,
                  title: Text(
                    script.name,
                    style: TextStyle(
                      color: selected ? EchoColors.primary : EchoColors.text,
                      fontSize: 13.5,
                    ),
                  ),
                  subtitle: Text(
                    '${script.steps.length} 个事件${script.isBuiltIn ? ' · 内置' : ''}',
                    style: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                  trailing: selected
                      ? Icon(Icons.check, size: 18, color: EchoColors.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(script),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
