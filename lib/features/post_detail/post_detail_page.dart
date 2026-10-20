import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/addiction_repository.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../data/repositories/post_voice_repository.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../../domain/models/post.dart';
import '../../domain/models/post_voice.dart';
import '../../domain/services/addiction_guard.dart';
import '../../domain/services/comment_reply_service.dart';
import '../../domain/services/comment_thread.dart';
import '../../domain/services/mode_controller.dart';
import '../../domain/services/voice_playback.dart';
import '../shared_widgets/comment_tile.dart';
import '../shared_widgets/like_button.dart';
import '../shared_widgets/post_image.dart';
import '../shared_widgets/user_avatar.dart';
import '../shell/app_shell.dart';

/// 帖子详情 + 评论区（规划书 §3.5）。
///
/// 评论区在回响模式里是"逐条延迟出现"的（阶段 B 由调度器驱动），
/// 阶段 A 直接按预置顺序铺开——但每条评论的入场动画保留，
/// 因为那种"一条条冒出来"的节奏正是异化体验的一部分。
class PostDetailPage extends ConsumerStatefulWidget {
  const PostDetailPage({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends ConsumerState<PostDetailPage> {
  /// 正在回谁；两个都为空就是普通发言。
  String? _replyToId;
  String? _replyToName;

  /// 正在回的那条评论本身。住民要靠它接住你那句话（B7）——
  /// 光有 id 不够，他还得知道你回的是哪一句。
  PostComment? _replyTarget;

  /// 进来时评论区有几条。用它判断这期间"等到没有"。
  int? _commentsOnEntry;

  Timer? _waitTimer;

  /// 评论区先取最近 20 条，点“加载更多”每次多 20 条。
  int _commentLimit = 20;

  /// 评论排序：规划书定的默认是「最新」，用户可以自己切「热度」。
  _CommentOrder _order = _CommentOrder.latest;

  /// 页面销毁时不能再碰 ref（ConsumerState 已经被判为 unmounted），
  /// 所以在 initState 里先把"停播放"这个动作存下来。
  Future<void> Function()? _stopPlayback;

  /// 盯多久算"等了一会儿"。八秒是个大概：短于它，多半只是在读帖子。
  static const Duration _waitThreshold = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    // 首帧之后再记：showSnackBar 需要一个已经挂到树上的 context
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordView());
    _waitTimer = Timer(_waitThreshold, _noteWaitIfNothingCame);
    if (ref.exists(voicePlaybackProvider)) {
      _stopPlayback = ref.read(voicePlaybackProvider.notifier).stop;
    }
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    // 播放器是全应用单例，页面走了它不会自己停——退出帖子页还响着，
    // 就是这里少了一句话。没播过就别把它建出来（AudioPlayer 也有开销）。
    final stop = _stopPlayback;
    if (stop != null) unawaited(stop());
    super.dispose();
  }

  /// 亮屏等待：点进来、盯了一会儿，评论区一条新的都没有（B9）。
  ///
  /// 防沉迷看的"查看反馈次数"是**动作**，这个是**动作的结果**——
  /// 微电影第二幕里主角盯着屏幕那几秒，指的就是它。
  ///
  /// 只记一次，不弹窗、不打断：这件事的价值在于用户以后能在看板上
  /// 自己看见它，而不是在被记录的那一刻被说教。
  void _noteWaitIfNothingCame() {
    if (!mounted || _commentsOnEntry == null) return;
    if (!ref.read(modeControllerProvider).isEcho) return;

    final current = ref.read(commentsProvider(widget.postId)).value?.length;
    if (current == null || current > _commentsOnEntry!) return;

    ref
        .read(addictionRepositoryProvider)
        .logEvent(AddictionEventType.screenWait);
  }

  /// 打开详情页 = 查看了一次反馈。这是防沉迷提醒的判定依据（规划书 §6.9）：
  /// 真正值得留意的信号不是"用了多久"，而是"多频繁地回来看有没有人理我"。
  Future<void> _recordView() async {
    if (!mounted) return;
    // 清醒模式里没有反馈可看，不该计入
    if (!ref.read(modeControllerProvider).isEcho) return;

    final guard = ref.read(addictionGuardProvider);
    await guard.recordView(widget.postId);
    final warning = await guard.evaluate();
    if (warning == null || !mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(warning)));
  }

  /// 切换评论排序。两个选项就够：想看新的，或者想看大家认同的。
  Future<void> _pickCommentOrder() async {
    final picked = await showModalBottomSheet<_CommentOrder>(
      context: context,
      backgroundColor: EchoColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            for (final option in _CommentOrder.values)
              ListTile(
                dense: true,
                title: Text(
                  option.label,
                  style: TextStyle(color: EchoColors.text, fontSize: 14),
                ),
                subtitle: Text(
                  option.hint,
                  style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
                ),
                trailing: option == _order
                    ? Icon(Icons.check, size: 18, color: EchoColors.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(option),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == _order) return;
    setState(() => _order = picked);
  }

  /// 开始回某一条。住民显示住民的名字，我自己的评论显示我的名字。
  void _startReply(PostComment comment) {
    final personaId = comment.personaId;
    final voices =
        ref.read(postVoicesProvider(widget.postId)).value ??
        const <PostVoice>[];
    String? voiceName;
    if (personaId != null) {
      for (final voice in voices) {
        if (voice.id == personaId) {
          voiceName = voice.name;
          break;
        }
      }
    }

    setState(() {
      _replyToId = comment.id;
      _replyTarget = comment;
      _replyToName = personaId == null
          ? (ref.read(userProfileProvider).value?.displayName ??
                AppTexts.defaultNickname)
          : (voiceName ?? ref.read(personaNameProvider(personaId)));
    });
  }

  void _clearReply() {
    if (_replyToId == null && _replyToName == null) return;
    setState(() {
      _replyToId = null;
      _replyToName = null;
      _replyTarget = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(modeControllerProvider);
    final postAsync = ref.watch(postByIdProvider(widget.postId));
    final comments =
        ref
            .watch(
              pagedCommentsProvider((
                postId: widget.postId,
                limit: _commentLimit,
              )),
            )
            .value ??
        const <PostComment>[];
    final voiceList =
        ref.watch(postVoicesProvider(widget.postId)).value ??
        const <PostVoice>[];
    final voiceById = {for (final voice in voiceList) voice.id: voice};
    // 第一次拿到评论数就是"进门时的样子"，之后来的都算新到的。
    _commentsOnEntry ??= comments.length;

    // 必须是 Scaffold：这个页面不在底部导航骨架里（独立路由），
    // 没有 Material 祖先的话，页面里所有文字都会继承 Flutter 兜底文本样式
    // （app.dart 的 _errorTextStyle，带黄色双下划线），
    // 表现为"点进帖子后到处是横线"。
    return Scaffold(
      backgroundColor: EchoColors.bg,
      body: ComplianceFooter(
        mode: mode,
        child: postAsync.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: EchoColors.primary),
          ),
          error: (error, _) => Center(
            child: Text(
              '帖子加载失败：$error',
              style: TextStyle(color: EchoColors.like, fontSize: 12),
            ),
          ),
          data: (post) => post == null
              ? Center(
                  child: Text(
                    '帖子不存在',
                    style: TextStyle(color: EchoColors.textMuted),
                  ),
                )
              : Column(
                  children: [
                    _TopBar(topicName: post.topicName),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          _PostBody(post: post),
                          const SizedBox(height: 18),
                          _CommentsHeader(
                            count: comments.length,
                            order: _order,
                            onTap: _pickCommentOrder,
                          ),
                          const SizedBox(height: 10),
                          if (mode.isClear)
                            const _ClearModeHint()
                          else if (comments.isEmpty)
                            const _NoCommentsYet()
                          else
                            // 平铺的评论先组装成能读的对话：回复跟在自己回的那条
                            // 下面、缩进一层（B7）。数据库里它们本来就是平的。
                            _CommentThreadList(
                              comments: comments,
                              voiceById: voiceById,
                              onReply: _startReply,
                              order: _order,
                            ),
                            if (comments.length >= _commentLimit)
                              Center(
                                child: TextButton(
                                  onPressed: () => setState(
                                    () => _commentLimit += 20,
                                  ),
                                  child: const Text('加载更多评论'),
                                ),
                              ),
                        ],
                      ),
                    ),
                    // 输入框只给回响模式：清醒模式里没有"社区"这回事，
                    // 记录是写给自己的
                    if (mode.isEcho)
                      _CommentComposer(
                        postId: post.id,
                        replyToId: _replyToId,
                        replyToName: _replyToName,
                        replyTarget: _replyTarget,
                        onDone: _clearReply,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// 说一句话。
///
/// 之前评论区只有住民在说话，想回一句都没地方回——社区得是双向的，
/// 不然"被看见"这件事只是单向的表演。
class _CommentComposer extends ConsumerStatefulWidget {
  const _CommentComposer({
    required this.postId,
    this.replyToId,
    this.replyToName,
    this.replyTarget,
    this.onDone,
  });

  final String postId;

  /// 非空表示这条是回给某一条的。
  final String? replyToId;
  final String? replyToName;

  /// 被回的那条评论本身。住民（B7）靠它接住你这句话。
  final PostComment? replyTarget;

  /// 发完之后通知外面把"正在回复"清掉。
  final VoidCallback? onDone;

  @override
  ConsumerState<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends ConsumerState<_CommentComposer> {
  final TextEditingController _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await ref
          .read(interactionRepositoryProvider)
          .addMyComment(
            postId: widget.postId,
            content: text,
            parentId: widget.replyToId,
            replyToName: widget.replyToName,
          );

      // 接住你那句话（B7）：排一句追问，他过几分钟回来。
      // 不 await——它是"他那边的事"，跟你这句话发出去没有关系。
      final target = widget.replyTarget;
      if (target != null) {
        unawaited(
          ref
              .read(commentReplyServiceProvider)
              .maybeFollowUp(
                postId: widget.postId,
                parent: target,
                myReply: text,
              ),
        );
      }
      if (!mounted) return;
      _ctrl.clear();
      widget.onDone?.call();
      setState(() => _sending = false);
      FocusScope.of(context).unfocus();
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('没能发出去：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EchoColors.surface,
        border: Border(top: BorderSide(color: EchoColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((widget.replyToName ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '正在回复 ${widget.replyToName}',
                        style: TextStyle(
                          color: EchoColors.primary,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onDone,
                      child: Text(
                        '取消',
                        style: TextStyle(
                          color: EchoColors.textFaint,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: TextStyle(color: EchoColors.text, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: (widget.replyToName ?? '').isEmpty
                            ? '说点什么…'
                            : '回复 ${widget.replyToName}…',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    color: EchoColors.primary,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 回响模式下评论不是立刻出现的，所以空评论区留一句"还在路上"，而不是"暂无评论"。
///
/// 这里此前还写着"反馈会在接下来的 0—48 小时里陆续出现"——那是把调度机制
/// 念给用户听。画面里该有的是"这个帖子还很安静"，不是一个排期表在报工期。
class _NoCommentsYet extends StatelessWidget {
  const _NoCommentsYet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(Icons.hourglass_empty, size: 22, color: EchoColors.textFaint),
          SizedBox(height: 10),
          Text(
            '还没有人路过这里。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: EchoColors.textFaint,
              fontSize: 12,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.topicName});

  final String? topicName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: EchoColors.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back, color: EchoColors.text),
          ),
          Expanded(
            child: Text(
              topicName ?? '帖子',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: EchoColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostBody extends ConsumerWidget {
  const _PostBody({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 谁发的：固定住民 / 旧住民显示本人，用户自己发的才显示"我"
    final resident = post.authorResidentId == null
        ? null
        : ref.watch(customResidentByIdProvider(post.authorResidentId!));
    final author = post.authorPersonaId == null
        ? null
        : ref.watch(personaByIdProvider(post.authorPersonaId!));
    final me = ref.watch(userProfileProvider).value;
    final name = resident?.name ??
        author?.name ??
        me?.displayName ??
        AppTexts.defaultNickname;
    final avatarRef =
        resident?.avatarAsset ?? author?.avatar ?? me?.avatarOrNull;
    final openAuthor = author == null
        ? null
        : () => context.push(RoutePaths.resident(author.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: openAuthor,
              child: UserAvatar(
                name: name,
                avatarRef: avatarRef,
                size: 40,
                showRing: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: openAuthor,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: EchoColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      RelativeTime.format(post.createdAt),
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: EchoColors.textFaint),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          post.content,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: EchoColors.text),
        ),
        if (post.hasImages) ...[
          const SizedBox(height: 12),
          PostImage(ref: post.images.first, height: 240),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            // 这里本来就有一颗心，只是它一直是死的（实心，看着像"已赞"）。
            // 换成信息流卡片用的那个组件，它自己会跟着状态变空/变实。
            LikeButton(post: post),
            const SizedBox(width: 18),
            Icon(
              Icons.mode_comment_outlined,
              size: 17,
              color: EchoColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              '${post.commentCount}',
              style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
            ),
            const SizedBox(width: 18),
            _ViewersBadge(postId: post.id),
          ],
        ),
      ],
    );
  }
}

/// 帖子底下的“看过”：数字 + 点开名单。
class _ViewersBadge extends ConsumerWidget {
  const _ViewersBadge({required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(postViewCountProvider(postId)).value ?? 0;
    return GestureDetector(
      onTap: count == 0 ? null : () => _showViewers(context, ref, postId),
      child: Row(
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 17,
            color: EchoColors.textMuted,
          ),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

Future<void> _showViewers(
  BuildContext context,
  WidgetRef ref,
  String postId,
) async {
  final viewers = await ref.read(postVoiceRepositoryProvider).viewers(postId);
  final interacted = await ref
      .read(interactionRepositoryProvider)
      .interactedPersonaIds(postId);
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: EchoColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => SafeArea(
      child: SizedBox(
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Text(
                '看过这条帖子的人 · ${viewers.length}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: EchoColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                itemCount: viewers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final viewer = viewers[index];
                  final acted = interacted.contains(viewer.voice.id);
                  return Row(
                    children: [
                      UserAvatar(
                        name: viewer.voice.name,
                        avatarRef: viewer.voice.avatarAsset,
                        size: 32,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              viewer.voice.name,
                              style: TextStyle(
                                color: EchoColors.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${RelativeTime.short(viewer.lastViewedAt)} · '
                              '${acted ? '互动过' : '只看过'}',
                              style: TextStyle(
                                color: EchoColors.textFaint,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 评论排序。
enum _CommentOrder {
  latest('最新', '刚说的话排在前面'),
  hot('热度', '赞多的排在前面');

  const _CommentOrder(this.label, this.hint);

  final String label;
  final String hint;
}

/// 评论区：默认只露两条回复，多的折起来（C3 的“展开评论”）。
class _CommentThreadList extends StatefulWidget {
  const _CommentThreadList({
    required this.comments,
    required this.voiceById,
    required this.onReply,
    this.order = _CommentOrder.latest,
  });

  final List<PostComment> comments;
  final Map<String, PostVoice> voiceById;
  final void Function(PostComment) onReply;
  final _CommentOrder order;

  @override
  State<_CommentThreadList> createState() => _CommentThreadListState();
}

class _CommentThreadListState extends State<_CommentThreadList> {
  static const int _visibleReplies = 2;
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final items = CommentThreads.build(widget.comments);
    final threads = <_CommentThread>[];
    for (final item in items) {
      if (!item.isReply || threads.isEmpty) {
        threads.add(_CommentThread(root: item.comment));
      } else {
        threads.last.replies.add(item.comment);
      }
    }

    // 排的是**顶层评论**；楼中楼始终按说话顺序跟在它父亲下面——
    // 把回复也按热度重排，一段对话就读不通了。
    threads.sort((a, b) {
      if (widget.order == _CommentOrder.hot) {
        final byLikes = b.root.likeCount.compareTo(a.root.likeCount);
        if (byLikes != 0) return byLikes;
      }
      return b.root.createdAt.compareTo(a.root.createdAt);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final thread in threads) ...[
          CommentTile(
            comment: thread.root,
            onReply: () => widget.onReply(thread.root),
            voice: _voiceOf(thread.root),
          ),
          for (final reply in thread.replies.take(
            _expanded.contains(thread.root.id)
                ? thread.replies.length
                : _visibleReplies,
          ))
            CommentTile(
              comment: reply,
              isReply: true,
              onReply: () => widget.onReply(reply),
              voice: _voiceOf(reply),
            ),
          if (thread.replies.length > _visibleReplies)
            Padding(
              padding: const EdgeInsets.only(left: 14, bottom: 12),
              child: GestureDetector(
                onTap: () => setState(() {
                  final id = thread.root.id;
                  if (!_expanded.add(id)) _expanded.remove(id);
                }),
                child: Text(
                  _expanded.contains(thread.root.id)
                      ? '收起回复'
                      : '展开 ${thread.replies.length - _visibleReplies} 条回复',
                  style: TextStyle(
                    color: EchoColors.primary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  PostVoice? _voiceOf(PostComment comment) {
    final personaId = comment.personaId;
    return personaId == null ? null : widget.voiceById[personaId];
  }
}

class _CommentThread {
  _CommentThread({required this.root});

  final PostComment root;
  final List<PostComment> replies = [];
}

class _CommentsHeader extends StatelessWidget {
  const _CommentsHeader({
    required this.count,
    required this.order,
    required this.onTap,
  });

  final int count;
  final _CommentOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '评论 $count',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(color: EchoColors.text, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '按${order.label}',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: EchoColors.textMuted),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 14,
                  color: EchoColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ClearModeHint extends StatelessWidget {
  const _ClearModeHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Text(
        '清醒模式下不显示虚拟评论。\n切到「分析」可以看到这条内容的客观分析结果。',
        style: TextStyle(
          color: EchoColors.textMuted,
          height: 1.6,
          fontSize: 13,
        ),
      ),
    );
  }
}
