import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_texts.dart';
import '../../core/theme/app_colors.dart';
import '../../data/demo/demo_script_repository.dart';
import '../../domain/models/demo_script.dart';
import '../../domain/models/post.dart';
import '../../domain/services/mode_controller.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';
import '../shared_widgets/comment_tile.dart';
import '../shared_widgets/permanent_notice_banner.dart';
import '../shared_widgets/post_image.dart';
import '../shared_widgets/user_avatar.dart';
import 'demo_timeline.dart';

/// 演示模式的"舞台"。
///
/// 它不是在播放一段视频，而是**用真实的界面组件**重演一次时间轴——
/// 所以镜头里看到的信息流、评论区、统计数字，和用户平时看到的是同一套代码。
/// 拍摄时随时能暂停、单步、重播，这正是"稳定、零成本、可重复"的落点。
class DemoPlayerPage extends ConsumerStatefulWidget {
  const DemoPlayerPage({super.key, required this.actId});

  final String actId;

  @override
  ConsumerState<DemoPlayerPage> createState() => _DemoPlayerPageState();
}

class _DemoPlayerPageState extends ConsumerState<DemoPlayerPage> {
  static const Duration _tick = Duration(milliseconds: 80);

  Timer? _timer;
  DemoScript? _script;
  DemoPostSpec? _stagePost;
  DemoTimeline? _timeline;

  int _elapsedMs = 0;
  bool _playing = false;
  bool _finished = false;
  String? _likeDelta;

  /// 是否显示"导演界面"（进度条、排练标签、解说字幕）。
  ///
  /// 一按播放就自动收起来——镜头里的 APP 必须长得像真的。
  /// 点一下画面可以随时叫回来（看进度、切单步）。
  bool _showDirectingUi = true;

  final _Stage _stage = _Stage();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(demoScriptRepositoryProvider);
    final script = await repo.loadById(widget.actId);

    // 第三幕复用第一幕的帖子——"同一张照片"是这一幕的关键
    DemoPostSpec? post = script.post;
    if (post == null && script.postRef != null) {
      final refScript = await repo.loadById(script.postRef!);
      post = refScript.post;
    }

    if (!mounted) return;
    setState(() {
      _script = script;
      _stagePost = post;
      _timeline = DemoTimeline(script.steps);
    });
  }

  // ── 播放控制 ────────────────────────────────────────────────

  void _play() {
    if (_timeline == null || _timeline!.isFinished) return;
    setState(() {
      _playing = true;
      _finished = false;
      // 一开拍就把导演界面收起来
      _showDirectingUi = false;
    });
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) {
      _elapsedMs += _tick.inMilliseconds;
      final due = _timeline!.advanceTo(_elapsedMs);
      if (due.isEmpty) return;
      setState(() {
        for (final step in due) {
          _applyStep(step);
        }
      });
      if (_timeline!.isFinished) {
        // 演完这一幕时不要把界面弹回来——不然一条过到尾的镜头就毁了
        _stopTimer();
        setState(() => _finished = true);
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// 手动暂停：这是排练行为，把导演界面还回来。
  void _pause() {
    _stopTimer();
    if (mounted) {
      setState(() {
        _playing = false;
        _showDirectingUi = true;
      });
    }
  }

  /// 单步：放出一个动作并把时钟对齐到它的时间点。
  void _stepOnce() {
    if (_timeline == null) return;
    if (_playing) _pause();
    final step = _timeline!.stepOnce();
    if (step == null) return;
    setState(() {
      _elapsedMs = step.atMs;
      _applyStep(step);
      _finished = _timeline!.isFinished;
    });
  }

  void _reset() {
    _pause();
    ref.read(modeControllerProvider.notifier).toEcho();
    setState(() {
      _timeline?.reset();
      _elapsedMs = 0;
      _finished = false;
      _likeDelta = null;
      _stage.reset();
    });
  }

  // ── 时间轴动作 → 舞台状态 ────────────────────────────────────

  void _applyStep(DemoStep step) {
    switch (step.type) {
      case 'stats':
        _stage.likes = step.likes ?? _stage.likes;
        _stage.commentCount = step.comments ?? _stage.commentCount;
      case 'like_burst':
        final delta = step.delta ?? 0;
        _stage.likes += delta;
        _likeDelta = '+$delta';
      case 'comment':
        _stage.visibleComments.add(step);
        _stage.commentCount = _stage.visibleComments.length;
      case 'hot':
        _stage.hotLabel = step.label;
        _stage.hotRank = step.rank;
      case 'overlay':
        _stage.overlay = step.text;
      case 'notification':
        _stage.notificationTitle = step.title;
        _stage.notificationBody = step.body;
      case 'settings_hint':
        _stage.settingsHint = step.text;
      case 'confirm_dialog':
        _stage.confirmTitle = step.title;
        _stage.confirmBody = step.body;
        _stage.confirmAction = step.confirmText;
      case 'mode':
        _stage.confirmTitle = null;
        _stage.notificationTitle = null;
        final controller = ref.read(modeControllerProvider.notifier);
        if (step.toMode == 'clear') {
          controller.toClear();
        } else {
          controller.toEcho();
        }
      case 'notice':
        _stage.notice = step.text;
      case 'rebuild_guide':
        _stage.rebuildGuide = step.text;
      case 'analysis':
        _stage.analysis = step.analysis;
      case 'caption_suggestion':
        _stage.captionHint = step.hint;
        _stage.captions = List.of(step.captions);
      case 'open_values':
      case 'open_actions':
        _stage.promptTitle = step.title;
        _stage.promptBody = step.prompt;
      case 'weekly_report_preview':
        _stage.weeklyReport = step.text;
      case 'end_card':
        _stage.endCard = step.text;
      default:
        break;
    }
  }

  // ── 构建 ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(modeControllerProvider);
    final script = _script;

    final showDirecting = _showDirectingUi;

    return Scaffold(
      backgroundColor: mode.isEcho ? EchoColors.bg : ClearColors.bg,
      // 拍摄模式下连 AppBar 也收起来。
      // 镜头里的 APP 必须长得像真的——"第一幕：建立幻觉"这种排练标签不能入镜，
      // 进度条更是穿帮（项目作者 2026-09-11 的判断）。
      appBar: showDirecting
          ? AppBar(
              title: Text(script?.title ?? '演示模式'),
              leading: IconButton(
                onPressed: () {
                  _pause();
                  Navigator.of(context).maybePop();
                },
                icon: const Icon(Icons.arrow_back),
              ),
            )
          : null,
      body: script == null || _timeline == null
          ? const Center(child: CircularProgressIndicator(color: EchoColors.primary))
          // 点一下画面就能把导演界面叫回来（再看一眼进度/切单步）
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showDirectingUi = !_showDirectingUi),
              child: Column(
                children: [
                  if (mode.isClear) const PermanentNoticeBanner(),
                  if (showDirecting)
                    _ControlBar(
                      isEcho: mode.isEcho,
                      playing: _playing,
                      finished: _finished,
                      progress: _timeline!.progressAt(_elapsedMs),
                      elapsedMs: _elapsedMs,
                      totalMs: script.effectiveDurationMs,
                      stepLabel: '${_timeline!.cursor}/${_timeline!.total}',
                      onPlay: _playing ? _pause : _play,
                      onStep: _stepOnce,
                      onReset: _reset,
                    ),
                  Expanded(child: _buildStage(mode.isEcho, showDirecting)),
                  if (mode.isEcho) const AiDisclaimerBar(),
                ],
              ),
            ),
    );
  }

  Widget _buildStage(bool isEcho, bool showDirecting) {
    final post = _stagePost;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, showDirecting ? 12 : 20, 16, 28),
      children: [
        // 副标题、设置提示、解说字幕、结尾字幕——这些是**导演用的注释**，
        // 拍摄时全部隐藏：故事要靠演员的动作演出来，不是靠屏幕上的字讲出来。
        if (showDirecting)
          Text(
            _script!.subtitle,
            style: TextStyle(
            color: isEcho ? EchoColors.textMuted : ClearColors.textMuted,
            fontSize: 12.5,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 14),
        if (_stage.notificationTitle != null) ...[
          _NotificationCard(
            isEcho: isEcho,
            title: _stage.notificationTitle!,
            body: _stage.notificationBody,
          ),
          const SizedBox(height: 12),
        ],
        if (showDirecting && _stage.settingsHint != null) ...[
          _HintStrip(isEcho: isEcho, text: _stage.settingsHint!, icon: Icons.tune),
          const SizedBox(height: 12),
        ],
        if (post != null)
          _StagePostCard(
            isEcho: isEcho,
            post: post,
            likes: _stage.likes,
            commentCount: _stage.commentCount,
            hotLabel: _stage.hotLabel,
            likeDelta: _likeDelta,
          ),
        if (_stage.captions.isNotEmpty) ...[
          const SizedBox(height: 14),
          _CaptionSuggestions(
            hint: _stage.captionHint ?? 'AI 为你推荐了几条文案',
            captions: _stage.captions,
          ),
        ],
        if (showDirecting && _stage.overlay != null) ...[
          const SizedBox(height: 14),
          _HintStrip(
            isEcho: isEcho,
            text: _stage.overlay!,
            icon: Icons.psychology_alt_outlined,
          ),
        ],
        if (_stage.confirmTitle != null) ...[
          const SizedBox(height: 14),
          _ConfirmCard(
            isEcho: isEcho,
            title: _stage.confirmTitle!,
            body: _stage.confirmBody,
            action: _stage.confirmAction,
          ),
        ],
        if (_stage.notice != null) ...[
          const SizedBox(height: 14),
          _NoticeCard(text: _stage.notice!),
        ],
        if (_stage.rebuildGuide != null) ...[
          const SizedBox(height: 12),
          _HintStrip(
            isEcho: isEcho,
            text: _stage.rebuildGuide!,
            icon: Icons.spa_outlined,
          ),
        ],
        if (_stage.analysis != null) ...[
          const SizedBox(height: 14),
          _AnalysisCard(analysis: _stage.analysis!),
        ],
        if (_stage.promptTitle != null) ...[
          const SizedBox(height: 14),
          _PromptCard(title: _stage.promptTitle!, body: _stage.promptBody),
        ],
        if (_stage.weeklyReport != null) ...[
          const SizedBox(height: 14),
          _HintStrip(
            isEcho: isEcho,
            text: _stage.weeklyReport!,
            icon: Icons.summarize_outlined,
          ),
        ],
        if (_stage.visibleComments.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                '评论 ${_stage.visibleComments.length}',
                style: TextStyle(
                  color: isEcho ? EchoColors.text : ClearColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text('按热度',
                  style: TextStyle(
                    color: isEcho ? EchoColors.textFaint : ClearColors.textFaint,
                    fontSize: 11,
                  )),
            ],
          ),
          const SizedBox(height: 12),
          for (final step in _stage.visibleComments)
            CommentTile(
              comment: _commentFrom(step),
              createdAtOverride: DateTime.now(),
              highlighted: step.highlight,
            ),
        ],
        if (showDirecting && _stage.endCard != null) ...[
          const SizedBox(height: 20),
          _EndCard(text: _stage.endCard!),
        ],
      ],
    );
  }

  /// 把脚本里的一个 comment 动作转成评论模型，交给真实组件渲染。
  PostComment _commentFrom(DemoStep step) {
    final index = _stage.visibleComments.indexOf(step);
    return PostComment(
      id: 'demo_${step.personaId}_$index',
      postId: _stagePost?.id ?? 'demo',
      personaId: step.personaId ?? 'persona_001',
      content: step.content,
      mediaType: switch (step.mediaType) {
        'voice' => CommentMedia.voice,
        'image' => CommentMedia.image,
        'emoji' => CommentMedia.emoji,
        _ => CommentMedia.text,
      },
      voiceAsset: step.voiceAsset,
      transcript: step.transcript,
      voiceDurationMs: step.voiceDurationMs,
      createdAt: DateTime.now(),
      likeCount: 0,
    );
  }
}

/// 舞台状态的容器。纯数据 + 重置，方便"重播"时一键回到开场。
class _Stage {
  int likes = 0;
  int commentCount = 0;
  final List<DemoStep> visibleComments = [];
  String? hotLabel;
  int? hotRank;
  String? overlay;
  String? settingsHint;
  String? notificationTitle;
  String? notificationBody;
  String? confirmTitle;
  String? confirmBody;
  String? confirmAction;
  String? notice;
  String? rebuildGuide;
  String? weeklyReport;
  String? captionHint;
  String? promptTitle;
  String? promptBody;
  String? endCard;
  List<String> captions = [];
  DemoAnalysis? analysis;

  void reset() {
    likes = 0;
    commentCount = 0;
    visibleComments.clear();
    hotLabel = null;
    hotRank = null;
    overlay = null;
    settingsHint = null;
    notificationTitle = null;
    notificationBody = null;
    confirmTitle = null;
    confirmBody = null;
    confirmAction = null;
    notice = null;
    rebuildGuide = null;
    weeklyReport = null;
    captionHint = null;
    promptTitle = null;
    promptBody = null;
    endCard = null;
    captions = [];
    analysis = null;
  }
}

// ── 播放控制条 ────────────────────────────────────────────────

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.isEcho,
    required this.playing,
    required this.finished,
    required this.progress,
    required this.elapsedMs,
    required this.totalMs,
    required this.stepLabel,
    required this.onPlay,
    required this.onStep,
    required this.onReset,
  });

  /// 第三幕会中途切到清醒模式，控件得跟着换配色，
  /// 否则浅色底上会出现一堆低对比度的深色文字。
  final bool isEcho;
  final bool playing;
  final bool finished;
  final double progress;
  final int elapsedMs;
  final int totalMs;
  final String stepLabel;
  final VoidCallback onPlay;
  final VoidCallback onStep;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final divider = isEcho ? EchoColors.divider : ClearColors.divider;
    final track = isEcho ? EchoColors.overlay : ClearColors.overlay;
    final accent = isEcho ? EchoColors.accent : ClearColors.accent;
    final primary = isEcho ? EchoColors.primary : ClearColors.primary;
    final muted = isEcho ? EchoColors.textMuted : ClearColors.textMuted;
    final faint = isEcho ? EchoColors.textFaint : ClearColors.textFaint;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: track,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: finished ? null : onPlay,
                icon: Icon(
                  playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  size: 30,
                  color: finished ? faint : primary,
                ),
                tooltip: playing ? '暂停' : '播放',
              ),
              IconButton(
                onPressed: finished ? null : onStep,
                icon: Icon(Icons.skip_next, size: 22, color: muted),
                tooltip: '单步',
              ),
              IconButton(
                onPressed: onReset,
                icon: Icon(Icons.replay, size: 20, color: muted),
                tooltip: '重置',
              ),
              const Spacer(),
              Text(
                '${(elapsedMs / 1000).toStringAsFixed(0)}s / ${(totalMs / 1000).toStringAsFixed(0)}s  ·  $stepLabel',
                style: TextStyle(color: faint, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 舞台零件 ─────────────────────────────────────────────────

class _StagePostCard extends StatelessWidget {
  const _StagePostCard({
    required this.isEcho,
    required this.post,
    required this.likes,
    required this.commentCount,
    required this.hotLabel,
    required this.likeDelta,
  });

  final bool isEcho;
  final DemoPostSpec post;
  final int likes;
  final int commentCount;
  final String? hotLabel;
  final String? likeDelta;

  @override
  Widget build(BuildContext context) {
    final surface = isEcho ? EchoColors.surface : ClearColors.surface;
    final surfaceHigh = isEcho ? EchoColors.surfaceHigh : ClearColors.surfaceHigh;
    final divider = isEcho ? EchoColors.divider : ClearColors.divider;
    final text = isEcho ? EchoColors.text : ClearColors.text;
    final faint = isEcho ? EchoColors.textFaint : ClearColors.textFaint;
    final muted = isEcho ? EchoColors.textMuted : ClearColors.textMuted;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                name: AppTexts.defaultNickname,
                size: 38,
                showRing: isEcho,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppTexts.defaultNickname,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: text,
                              fontWeight: FontWeight.w600,
                            )),
                    const SizedBox(height: 2),
                    Text('${post.topicName ?? '日常'} · 刚刚',
                        style: TextStyle(color: faint, fontSize: 11)),
                  ],
                ),
              ),
              // 清醒模式下连"热"都不该存在——热度是外部评价的产物
              if (isEcho && hotLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: EchoColors.hot.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_fire_department,
                          size: 12, color: EchoColors.hot),
                      const SizedBox(width: 3),
                      Text(hotLabel!,
                          style: const TextStyle(
                            color: EchoColors.hot,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          )),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(post.content,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: text)),
          if (post.images.isNotEmpty) ...[
            const SizedBox(height: 10),
            PostImage(ref: post.images.first),
          ],
          const SizedBox(height: 12),
          if (isEcho)
            Row(
              children: [
                const Icon(Icons.favorite, size: 17, color: EchoColors.like),
                const SizedBox(width: 5),
                _AnimatedCount(value: likes, color: EchoColors.like),
                if (likeDelta != null) ...[
                  const SizedBox(width: 6),
                  Text(likeDelta!,
                      style: const TextStyle(
                        color: EchoColors.like,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      )),
                ],
                const SizedBox(width: 18),
                const Icon(Icons.mode_comment_outlined,
                    size: 17, color: EchoColors.textMuted),
                const SizedBox(width: 5),
                _AnimatedCount(value: commentCount, color: EchoColors.textMuted),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: surfaceHigh,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility_off_outlined, size: 13, color: muted),
                  const SizedBox(width: 6),
                  Text('点赞数与评论数已隐藏',
                      style: TextStyle(color: muted, fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 数字变化时做一次轻微跳动，模拟"还在涨"的观感。
class _AnimatedCount extends StatelessWidget {
  const _AnimatedCount({required this.value, required this.color});

  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Text(
        '$value',
        key: ValueKey(value),
        style: TextStyle(color: color, fontSize: 13),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.isEcho,
    required this.title,
    this.body,
  });

  final bool isEcho;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final surfaceHigh = isEcho ? EchoColors.surfaceHigh : ClearColors.surfaceHigh;
    final primary = isEcho ? EchoColors.primary : ClearColors.primary;
    final text = isEcho ? EchoColors.text : ClearColors.text;
    final faint = isEcho ? EchoColors.textFaint : ClearColors.textFaint;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined, size: 17, color: primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                if (body != null) ...[
                  const SizedBox(height: 2),
                  Text(body!,
                      style: TextStyle(color: faint, fontSize: 11.5)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HintStrip extends StatelessWidget {
  const _HintStrip({
    required this.isEcho,
    required this.text,
    required this.icon,
  });

  final bool isEcho;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final overlay = isEcho ? EchoColors.overlay : ClearColors.overlay;
    final divider = isEcho ? EchoColors.divider : ClearColors.divider;
    final accent = isEcho ? EchoColors.accent : ClearColors.accent;
    final text0 = isEcho ? EchoColors.text : ClearColors.text;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: overlay.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: divider),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: text0, fontSize: 12.5, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _CaptionSuggestions extends StatelessWidget {
  const _CaptionSuggestions({required this.hint, required this.captions});

  final String hint;
  final List<String> captions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 15, color: EchoColors.accent),
              const SizedBox(width: 8),
              Text(hint,
                  style: const TextStyle(
                      color: EchoColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < captions.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${i + 1}. ${captions[i]}',
                style: const TextStyle(
                    color: EchoColors.text, fontSize: 13, height: 1.6),
              ),
            ),
          const SizedBox(height: 4),
          const Text('一键使用后，它会成为你的文案。',
              style: TextStyle(color: EchoColors.textFaint, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({
    required this.isEcho,
    required this.title,
    this.body,
    this.action,
  });

  final bool isEcho;
  final String title;
  final String? body;
  final String? action;

  @override
  Widget build(BuildContext context) {
    final surfaceHigh = isEcho ? EchoColors.surfaceHigh : ClearColors.surfaceHigh;
    final primary = isEcho ? EchoColors.primary : ClearColors.primary;
    final text = isEcho ? EchoColors.text : ClearColors.text;
    final muted = isEcho ? EchoColors.textMuted : ClearColors.textMuted;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: text, fontSize: 14, fontWeight: FontWeight.w600)),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!,
                style: TextStyle(color: muted, fontSize: 12.5, height: 1.6)),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(action ?? '确定',
                  style: TextStyle(
                      color: primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ClearColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: ClearColors.accent, width: 3)),
      ),
      child: Text(text,
          style: const TextStyle(
              color: ClearColors.text, fontSize: 12.5, height: 1.6)),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.analysis});

  final DemoAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final entries = analysis.entries;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: ClearColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ClearColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_outlined, size: 16, color: ClearColors.primary),
              const SizedBox(width: 8),
              Text('客观分析',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: ClearColors.text,
                        fontWeight: FontWeight.w600,
                      )),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < entries.length; i++) ...[
            Text('${i + 1}. ${entries[i].key}',
                style: const TextStyle(
                    color: ClearColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(entries[i].value,
                style: const TextStyle(
                    color: ClearColors.textMuted, fontSize: 12.5, height: 1.7)),
            if (i != entries.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.title, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ClearColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ClearColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: ClearColors.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!,
                style: const TextStyle(
                    color: ClearColors.textMuted, fontSize: 12.5, height: 1.6)),
          ],
        ],
      ),
    );
  }
}

class _EndCard extends StatelessWidget {
  const _EndCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF231C42), Color(0xFF141026)],
        ),
        border: Border.all(color: EchoColors.primary.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: EchoColors.text,
          fontSize: 14.5,
          height: 1.9,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
