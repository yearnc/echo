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
import '../../domain/services/audience_service.dart';
import '../../domain/services/community_settings_controller.dart';
import '../../domain/services/content_moderator.dart';
import '../../domain/services/mode_controller.dart';
import '../../domain/services/model_gateway.dart';
import '../../domain/services/scheduler_service.dart';
import '../../domain/services/voice_recorder.dart';
import '../shared_widgets/image_source_sheet.dart';

/// 发布页（规划书 §6.1）。
///
/// 页面主体只留"我要说什么"：文字、图片、话题。
/// 策划模式与回复频率 / 点赞量 / 拟人程度收进右上角的小按钮——
/// 它们偏技术，一直摆在正文旁边会把人从表达里拽出来；
/// 但排期仍然是发帖这一刻决定的，只是不必一直看得见。
class ComposePage extends ConsumerStatefulWidget {
  const ComposePage({super.key});

  @override
  ConsumerState<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends ConsumerState<ComposePage> {
  final TextEditingController _controller = TextEditingController();
  String _topic = '日常';
  String _density = '自动';
  String _likeLevel = '自动';
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

  /// 用语音说这条帖子（v4.0）：录下来的 wav 与识别出的文字。
  /// 正文仍然可编辑，这个字段只负责“发出去时标成语音”。
  final VoiceRecorder _recorder = VoiceRecorder();
  String? _voicePath;
  int? _voiceDurationMs;
  bool _recording = false;
  bool _voiceBusy = false;
  int _recordSeconds = 0;
  Timer? _recordTicker;

  static const List<String> _topics = ['日常', '随手拍', '学习', '运动', '深夜', '吐槽'];

  @override
  void dispose() {
    _recordTicker?.cancel();
    unawaited(_recorder.dispose());
    // 录了语音但没发布就离开：音频不该留在私有目录里。
    final voice = _voicePath;
    if (voice != null) {
      unawaited(const MediaService().deleteByRef(voice));
    }
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEcho ? '发布' : '记录',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: isEcho ? EchoColors.text : ClearColors.text,
                            fontSize: 24,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEcho ? '说点什么，会有人回应你的。' : '写下一件今天真实发生的事。',
                      style: TextStyle(
                        color: isEcho
                            ? EchoColors.textMuted
                            : ClearColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isEcho)
                _TuningButton(
                  planning: _planMode,
                  onTap: () => _openTuning(scripts),
                ),
            ],
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
            recording: _recording,
            voiceSeconds: _recordSeconds,
            voiceBusy: _voiceBusy,
            voiceDurationMs: _voiceDurationMs,
            hasVoice: _voicePath != null,
            onVoiceTap: _toggleVoice,
            onRemoveVoice: _removeVoice,
          ),
          const SizedBox(height: 18),
          if (isEcho) ...[
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

  /// 点一下开始录，再点一下结束：发布页比私信更需要“看着能操作”，
  /// 不必像聊天那样一直按着。
  Future<void> _toggleVoice() async {
    if (_voiceBusy) return;
    if (!_recording) {
      final ok = await _recorder.start();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有麦克风权限，去系统设置里打开再试')),
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordSeconds = 0;
      });
      _recordTicker?.cancel();
      _recordTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordSeconds++);
        if (_recordSeconds >= VoiceRecorder.maxDuration.inSeconds) {
          unawaited(_toggleVoice());
        }
      });
      return;
    }

    _recordTicker?.cancel();
    final recorded = await _recorder.stop();
    if (!mounted) return;
    setState(() => _recording = false);
    if (recorded == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('按住时间太短了')));
      return;
    }

    setState(() => _voiceBusy = true);
    try {
      final media = ref.read(mediaServiceProvider);
      final target = await media.newVoiceFile();
      await File(recorded.path).copy(target.path);
      final result = await ref
          .read(asrServiceProvider)
          .transcribeWav(target.path);
      if (!mounted) return;

      final current = _controller.text.trim();
      final next = current.isEmpty ? result.text : '$current\n${result.text}';
      _controller.text = next;
      _controller.selection = TextSelection.collapsed(offset: next.length);
      // 换一段语音时把上一段文件清掉，别留孤儿。
      final previous = _voicePath;
      setState(() {
        _voicePath = 'file:${target.path}';
        _voiceDurationMs = result.durationMs;
      });
      if (previous != null && previous != _voicePath) {
        unawaited(media.deleteByRef(previous));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('没识别出来：$error')));
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<void> _removeVoice() async {
    final path = _voicePath;
    if (path == null) return;
    setState(() {
      _voicePath = null;
      _voiceDurationMs = null;
    });
    await ref.read(mediaServiceProvider).deleteByRef(path);
  }

  Future<void> _pickImage() async {
    try {
      final imageRef = await pickImageWithSource(context, ref);
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

  /// 发布选项：策划模式 + 三个旋钮。
  ///
  /// 它们都偏"技术"，摆在正文旁边会一直把人从"我要说什么"里拽出来。
  /// 所以收进右上角一个小按钮，默认值给"自动"，不打扰。
  Future<void> _openTuning(List<PlanScript> scripts) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: EchoColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetBodyContext, setSheetState) {
          // 值存在页面 state 里，弹层也要跟着重建一次
          void sync(VoidCallback change) {
            setSheetState(change);
            setState(change);
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                6,
                16,
                16 + MediaQuery.of(sheetBodyContext).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '发布选项',
                        style: TextStyle(
                          color: EchoColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _PlanModeCard(
                    enabled: _planMode,
                    script: _script,
                    onToggle: (value) async {
                      await _togglePlanMode(value, scripts);
                      if (sheetBodyContext.mounted) setSheetState(() {});
                    },
                    onPick: () async {
                      await _pickScript(scripts);
                      if (sheetBodyContext.mounted) setSheetState(() {});
                    },
                    onManage: () {
                      Navigator.of(sheetContext).pop();
                      context.push(RoutePaths.scripts);
                    },
                  ),
                  if (!_planMode) ...[
                    const SizedBox(height: 18),
                    _SettingRow(
                      label: '回复频率',
                      value: _density,
                      options: const ['低', '中', '高', '自动'],
                      onChanged: (v) => sync(() => _density = v),
                    ),
                    _SettingRow(
                      label: '点赞量',
                      value: _likeLevel,
                      options: const ['低', '中', '高', '自动'],
                      onChanged: (v) => sync(() => _likeLevel = v),
                    ),
                    _SettingRow(
                      label: '拟人程度',
                      value: '$_humanLevel 档',
                      options: const ['1', '2', '3', '4', '5'],
                      onChanged: (v) =>
                          sync(() => _humanLevel = int.parse(v)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '只影响 AI 内容的表现形式。',
                      style: TextStyle(
                        color: EchoColors.textFaint,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
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
            // 这条是用语音说的：正文是转写稿，原始音频留着给帖子播放。
            speechBy: _voicePath != null ? 'me' : '',
            voicePath: _voicePath ?? '',
            speechDurationMs: _voiceDurationMs,
          );

      // 回响模式：帖子先落地，反馈在后台慢慢来。
      if (isEcho) {
        final scheduler = ref.read(schedulerServiceProvider);
        if (script != null) {
          // 策划模式：按脚本的秒级时间点精确排期。脚本是本地数据，很快。
          await scheduler.planFromScript(postId: postId, script: script);
        } else {
          // 随机发帖：解析 + 凑人可能要几秒到十几秒。用户没道理站在发布页等，
          // 所以**不 await**——帖子已经发出去了，网民在后台陆续到。
          // 提前把 provider 读出来：闭包执行时页面可能已经卸载。
          final community = ref.read(communitySettingsProvider);
          final audience = ref.read(audienceServiceProvider);
          final density = ReplyDensity.fromLabel(_density);
          unawaited(() async {
            try {
              await audience.prepare(
                postId: postId,
                density: density,
                allowLurk: community.allowLurk,
              );
            } catch (error) {
              debugPrint('[发布] 后台凑人失败：$error');
            }
          }());
        }
      }

      if (!mounted) return;
      _controller.clear();
      setState(() {
        _imageRefs.clear();
        _voicePath = null;
        _voiceDurationMs = null;
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
        '这条帖子照常发布，回应会由内置示例生成。\n\n'
        '填上模型之后，评论和动态才会真的由 AI 生成。API Key 只存在本机。',
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

class _AttachRow extends StatelessWidget {
  const _AttachRow({
    required this.images,
    required this.isEcho,
    required this.onPick,
    required this.onRemove,
    required this.recording,
    required this.voiceSeconds,
    required this.voiceBusy,
    required this.voiceDurationMs,
    required this.hasVoice,
    required this.onVoiceTap,
    required this.onRemoveVoice,
  });

  final List<String> images;
  final bool isEcho;
  final VoidCallback onPick;
  final ValueChanged<String> onRemove;
  final bool recording;
  final int voiceSeconds;
  final bool voiceBusy;
  final int? voiceDurationMs;
  final bool hasVoice;
  final VoidCallback onVoiceTap;
  final VoidCallback onRemoveVoice;

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
          // 语音帖：录完把识别稿填进正文，这里只显示“这段是语音”。
          InkWell(
            onTap: voiceBusy ? null : onVoiceTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: hasVoice ? 112 : 68,
              height: 68,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: recording
                    ? (isEcho ? EchoColors.primary : ClearColors.primary)
                          .withValues(alpha: 0.12)
                    : surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: recording
                      ? (isEcho ? EchoColors.primary : ClearColors.primary)
                      : divider,
                ),
              ),
              child: voiceBusy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isEcho ? EchoColors.primary : ClearColors.primary,
                      ),
                    )
                  : hasVoice
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.graphic_eq, size: 16, color: muted),
                        const SizedBox(width: 5),
                        Text(
                          '语音 ${((voiceDurationMs ?? 0) / 1000).round()}s',
                          style: TextStyle(color: muted, fontSize: 11.5),
                        ),
                        IconButton(
                          onPressed: onRemoveVoice,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close, size: 14, color: muted),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          recording ? Icons.stop_circle_outlined : Icons.mic_none,
                          color: muted,
                          size: 22,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          recording
                              ? '${voiceSeconds}s · 点停'
                              : '语音',
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
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

/// 右上角那个小按钮：把技术选项收起来，不抢正文的注意力。
class _TuningButton extends StatelessWidget {
  const _TuningButton({required this.planning, required this.onTap});

  final bool planning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '发布选项',
      child: Material(
        color: EchoColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: planning
                ? EchoColors.primary.withValues(alpha: 0.45)
                : EchoColors.divider,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.tune,
                  size: 18,
                  color: planning ? EchoColors.primary : EchoColors.textMuted,
                ),
                if (planning)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: EchoColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
              '精确到发帖后第几秒：谁点赞、谁评论；评论者以固定住民或临时网友的身份出现',
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
