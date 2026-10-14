import 'dart:async';
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
import '../../domain/models/moderation_result.dart';
import '../../domain/models/plan_script.dart';
import '../../domain/services/asr_service.dart';
import '../../domain/services/content_moderator.dart';
import '../../domain/services/mode_controller.dart';
import '../../domain/services/model_gateway.dart';
import '../../domain/services/scheduler_service.dart';
import '../../domain/services/voice_recorder.dart';

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

  /// 非 null 就是在忙，内容是按钮上显示的字。
  ///
  /// 用一个字符串而不是 bool：发布这条路上有两段实打实的等待（审核可能要走一次
  /// 模型往返、保存要落库排期），让用户盯着同一个"保存中…"发呆好几秒不像话。
  String? _busy;

  /// 策划模式：勾上之后不再随机排期，改按选中的脚本执行。
  bool _planMode = false;
  PlanScript? _script;

  /// 脚本选择弹窗是否已经开着（防止连点叠出好几层）。
  bool _sheetOpen = false;

  /// 已附图（`file:` 引用，已复制进 APP 私有目录）
  final List<String> _imageRefs = [];

  /// 正在按住录音。
  bool _recording = false;

  /// 录音已经结束、正在转文字。
  bool _transcribing = false;

  static const List<String> _topics = ['日常', '随手拍', '学习', '运动', '深夜', '吐槽'];

  /// 按住说话：开始录音（B8）。
  Future<void> _startVoice() async {
    if (_transcribing) return;
    final started = await ref.read(voiceRecorderProvider).start();
    if (!mounted) return;
    if (!started) {
      _hint('没拿到麦克风权限，或者这台设备没有可用的麦克风');
      return;
    }
    setState(() => _recording = true);
  }

  /// 松手：停下来，把这段话转成文字（B8）。
  ///
  /// 识别在本机做，录音不离开这台设备。
  Future<void> _stopVoice() async {
    if (!_recording) return;
    setState(() {
      _recording = false;
      _transcribing = true;
    });

    try {
      final path = await ref.read(voiceRecorderProvider).stop();
      if (path == null) return;

      final text = await ref.read(asrServiceProvider).transcribe(path);
      if (!mounted) return;

      if (text == null) {
        _hint('语音输入用不了：识别模型没装，或者引擎起不来');
        return;
      }
      if (text.isEmpty) {
        _hint('没听清，再说一次？');
        return;
      }

      // 接着说：已经有字就接在后面，不覆盖用户自己敲的内容。
      final existing = _controller.text.trim();
      _controller.text = existing.isEmpty ? text : '$existing $text';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    } catch (error) {
      debugPrint('[语音] 这次输入没成：$error');
      if (mounted) _hint('语音输入这次没成，再试一次');
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  void _hint(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

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
          const SizedBox(height: 10),
          _VoiceInputBar(
            isEcho: isEcho,
            recording: _recording,
            transcribing: _transcribing,
            onStart: _startVoice,
            onEnd: _stopVoice,
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
              onPressed: _busy == null ? _publish : null,
              style: isEcho
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: ClearColors.primary,
                    ),
              child: Text(_busy ?? (isEcho ? '发布' : '记录')),
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

    final isEcho = ref.read(modeControllerProvider).isEcho;
    // 策划模式的互动来自离线脚本、不经过模型，所以下面那条"还没配模型"的提醒
    // 对它不适用——脚本帖不依赖任何 API。
    final script = isEcho && _planMode ? _script : null;

    try {
      // ── ① 有没有接上模型：审核和"要不要提醒去配"用的是同一次查询 ──
      setState(() => _busy = '检查内容…');
      final activeModel = await ref.read(modelGatewayProvider).activeConfig();
      if (!mounted) return;

      // ── ② 审核：本地词表是确定命中，直接拦；模型是概率判断，一律留确认的出口 ──
      final moderation = await ref
          .read(contentModeratorProvider)
          .check(text: text, withModel: activeModel);
      if (!mounted) return;

      if (moderation.isBlocked && !moderation.fromModel) {
        setState(() => _busy = null);
        await _showBlocked(moderation);
        return;
      }
      if (moderation.verdict != ModerationVerdict.pass) {
        final proceed = await _confirmModeration(moderation);
        if (!mounted) return;
        if (proceed != true) {
          setState(() => _busy = null);
          return;
        }
      }

      // ── ③ 回响模式的回应要靠模型生成，没配就先问一句要不要去配 ──
      if (isEcho && script == null && activeModel == null) {
        final goSetup = await _askModelSetup();
        if (!mounted) return;
        if (goSetup == true) {
          // 内容留在编辑区：配完模型回来接着发，不用重写一遍
          setState(() => _busy = null);
          context.push(RoutePaths.models);
          return;
        }
      }

      // ── ④ 落库 + 排期 ──
      setState(() => _busy = isEcho ? '发布中…' : '保存中…');
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
          // 排期那一步已经用预置台词填好内容了。配了模型的话，让它在后台
          // 把还没到点的评论换成人写的——**不 await**：写五六条要好几秒，
          // 用户没道理站在发布页等，而排期本身早就落库了。
          unawaited(scheduler.upgradeCommentsWithModel(postId));
        }
      }

      if (!mounted) return;
      _controller.clear();
      setState(() {
        _imageRefs.clear();
        _busy = null;
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
      setState(() => _busy = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  /// 本地词表命中：只有"返回修改"一个出口。
  ///
  /// 只有这种情况不给申诉——词表里的每一个都是没有歧义的词，命中就是真的写了。
  /// 模型给的 block 不走这里，走 [\_confirmModeration]：那是概率判断，得有翻案的机会。
  ///
  /// 界面刻意不回显命中的那几个字。用户不需要知道自己是撞上了哪两个字，
  /// 需要知道的是这条不能发、以及能回去改。
  Future<void> _showBlocked(ModerationResult result) {
    final lines = <String>[
      if (result.reason.isNotEmpty) result.reason,
      if (result.categories.isNotEmpty)
        '涉及：${result.categories.map(moderationCategoryLabel).join('、')}',
    ];

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: EchoColors.surface,
        title: Text(
          '这条内容不能发布',
          style: TextStyle(color: EchoColors.text, fontSize: 15.5),
        ),
        content: Text(
          lines.isEmpty ? '内容不符合社区规范。' : lines.join('\n'),
          style: TextStyle(
            color: EchoColors.textMuted,
            fontSize: 13,
            height: 1.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              '返回修改',
              style: TextStyle(color: EchoColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  /// 审核提示后的确认。
  ///
  /// review 要给这个出口，是因为模型判定一定有假阳性；模型给的 block 同样要给，
  /// 理由一样——"这句话到底是什么意思"只有写它的人说得清。真正不给出口的只有
  /// 本地词表那些没有歧义的词。
  Future<bool?> _confirmModeration(ModerationResult result) => _ask(
    title: result.isBlocked ? '审核没通过' : '再确认一下',
    body: result.reason.isEmpty
        ? '这条内容可能不太适合公开在社区里，确认之后再发布。'
        : result.reason,
    confirmLabel: '仍然发布',
    cancelLabel: '返回修改',
  );

  /// 还没配模型就发帖。
  ///
  /// 提醒的落点是"你现在拿到的是什么"（示例内容），不是"你少配了一样东西"——
  /// 前者是用户能拿来判断的信息，后者是在催他做一件他可能并不想做的事。
  Future<bool?> _askModelSetup() => _ask(
    title: '还没有配置 AI 服务',
    body:
        '这条帖子照常发布，回应会由内置的示例内容生成。\n\n'
        '填上你自己的模型之后，评论和动态才会真的由 AI 生成。'
        'API Key 只存在这台设备上，不会传到别处。',
    confirmLabel: '去配置',
    cancelLabel: '先这样发布',
  );

  Future<bool?> _ask({
    required String title,
    required String body,
    required String confirmLabel,
    required String cancelLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: EchoColors.surface,
        title: Text(
          title,
          style: TextStyle(color: EchoColors.text, fontSize: 15.5),
        ),
        content: Text(
          body,
          style: TextStyle(
            color: EchoColors.textMuted,
            fontSize: 13,
            height: 1.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              cancelLabel,
              style: TextStyle(color: EchoColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: TextStyle(color: EchoColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 按住说话：录一段话，松手转成文字（B8）。
///
/// 识别用的是随包发布的离线模型，**录音不离开这台设备**——
/// 这一点值得在按钮下面写出来：用户对着麦克风说的话，
/// 凭什么要经过别人的服务器。
class _VoiceInputBar extends StatelessWidget {
  const _VoiceInputBar({
    required this.isEcho,
    required this.recording,
    required this.transcribing,
    required this.onStart,
    required this.onEnd,
  });

  final bool isEcho;
  final bool recording;
  final bool transcribing;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final accent = isEcho ? EchoColors.accent : ClearColors.accent;
    final surface = isEcho ? EchoColors.surface : ClearColors.surface;
    final divider = isEcho ? EchoColors.divider : ClearColors.divider;
    final muted = isEcho ? EchoColors.textMuted : ClearColors.textMuted;

    final label = switch ((recording, transcribing)) {
      (true, _) => '松开就转成文字',
      (_, true) => '正在听…',
      _ => '按住说话',
    };

    return GestureDetector(
      // 长按才算"按住说话"：普通点击不会误触发，
      // 手指划出去（想滚动页面）也会取消。
      onLongPressStart: (_) => onStart(),
      onLongPressEnd: (_) => onEnd(),
      onLongPressCancel: onEnd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: recording ? accent.withValues(alpha: 0.16) : surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: recording ? accent : divider),
        ),
        child: Row(
          children: [
            Icon(
              recording ? Icons.mic : Icons.mic_none,
              size: 18,
              color: recording ? accent : muted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: recording ? accent : muted,
                fontSize: 12.5,
              ),
            ),
            const Spacer(),
            Text(
              '在本机转文字',
              style: TextStyle(
                color: isEcho ? EchoColors.textFaint : ClearColors.textFaint,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
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
    // 用 Material 打底而不是 Container：里面的 SwitchListTile 本质是 ListTile，
    // 它把背景与水波纹画在最近的 Material 上。外面套一层带背景色的 DecoratedBox，
    // 水波纹就永远看不见——Flutter 会直接抛断言提醒这件事。
    return Material(
      color: EchoColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
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
