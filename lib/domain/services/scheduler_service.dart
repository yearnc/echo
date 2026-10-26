import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/analysis_repository.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/plan_event_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../data/repositories/post_understanding_repository.dart';
import '../../data/repositories/post_voice_repository.dart';
import '../models/ai_persona.dart';
import '../models/pending_interaction.dart';
import '../models/plan_script.dart';
import '../models/post_voice.dart';
import '../models/voice_settings.dart';
import 'community_settings_controller.dart';
import 'content_generator.dart';
import 'notification_service.dart';
import 'tts_service.dart';
import 'voice_settings_controller.dart';

// 策划脚本只安排"这条帖子会收到什么回应"，所以这里没有"切模式""跳页面"的
// 入口：那些动作在拍摄时由人手动完成，不由脚本代劳。

/// 互动调度服务（规划书 §7.3 的"现实方案"）。
///
/// 安卓/iOS 的后台任务都不可靠，所以这里不赌系统调度，
/// 而是**发帖时就把将来要发生的事排好队写进数据库**，
/// 然后在冷启动、回前台、前台心跳时扫一次"到点的"，一次性兑现。
/// 这样即使进程被杀、手机重启，排期也不会丢——它们本来就存在磁盘上。
///
/// 有两条队列，语义不同：
/// - **随机排期**（`ai_interactions`）：普通发帖，0—48 小时摊开，人格随机来点赞/评论
/// - **策划排期**（`plan_events`）：勾了策划模式的帖子，按脚本的秒级时间点精确执行
class SchedulerService {
  SchedulerService({
    required this.interactions,
    required this.planEvents,
    required this.posts,
    required this.notifications,
    required this.analyses,
    required this.generator,
    this.voiceRepo,
    this.residents,
    this.understandings,
    this.readAiPeerLimit,
    this.readSendImagesDirectly,
    this.voice,
    this.readVoiceSettings,
    this.notify,
    this.scheduleNotification,
    this.cancelScheduledNotification,
    Random? random,
  }) : _random = random ?? Random();

  final InteractionRepository interactions;
  final PlanEventRepository planEvents;
  final PostRepository posts;
  final NotificationRepository notifications;
  final AnalysisRepository analyses;

  /// 每帖的临时网民（v3.0）。可空：老测试和策划模式只认识固定住民。
  final PostVoiceRepository? voiceRepo;

  /// 固定住民。策划脚本可以点名让某位固定住民来评论，
  /// 这条事件执行时要给 TA 在本帖建一个 voice 快照。
  final CustomResidentRepository? residents;

  /// 帖子解析结果（AI 接 AI 时带上，接得更准）。
  final PostUnderstandingRepository? understandings;

  /// 每帖 AI 接 AI 的上限；不传就是默认 2。
  final int Function()? readAiPeerLimit;

  /// 帖子图片原图直发还是先总结（设置项）。
  final bool Function()? readSendImagesDirectly;

  /// 住民说话的嗓子（B8）。可空：没有它就全发文字，社区照常运转。
  final TtsService? voice;

  /// 语音开关。关掉之后不再生成新的语音评论，历史语音照常能播。
  final VoiceSettings Function()? readVoiceSettings;

  /// 往系统通知栏推一条（B10）。可空，而且**前台不接**：
  /// 用户正开着 APP 时，应用内的红点与列表已经够了，
  /// 再弹一条系统通知是重复打扰。只有后台补发那条路才接它。
  final void Function(String key, String title, String body)? notify;

  /// 把一条**将来**的互动交给系统闹钟（B10 修订）。
  ///
  /// 与 [notify] 的分工：那个是"现在就弹"，这个是"到点替我弹"。
  /// 后者才是 APP 关着时唯一靠得住的路——WorkManager 在国产 ROM 上
  /// 随时会被省电策略掐掉，而排期本来就在磁盘上，没有理由不交给系统。
  final void Function(String key, DateTime at, String title, String body)?
  scheduleNotification;

  /// 互动提前被兑现时，把对应的预约撤掉，避免同一条提醒弹两次。
  final void Function(String key)? cancelScheduledNotification;

  /// 住民说什么话由它出：配了模型就是模型写的，没配就是预置台词。
  final ContentGenerator generator;

  final Random _random;

  /// APP 切到后台时调用：把还没到点的评论重新交给系统闹钟。
  ///
  /// 为什么不在前台一直挂着预约：APP 开着的时候，通知该走应用内那张列表，
  /// 系统通知是打扰；所以回到前台会把预约全撤掉，切到后台再按库里
  /// 剩下的队列重新排一遍。这样"开着不弹、关着能收到"两边都成立。
  Future<void> rescheduleNotifications() async {
    final schedule = scheduleNotification;
    if (schedule == null) return;

    try {
      final pending = await interactions.pendingComments();
      if (pending.isEmpty) return;

      // 住民自己动态底下的评论不是"回应你"，不该叫醒你的手机
      final peers = await posts.residentAuthorsOf(
        pending.map((item) => item.postId).toSet(),
      );
      final voiceMap =
          await voiceRepo?.byIds(pending.map((item) => item.personaId)) ??
          const {};
      final nameById = {
        for (final v in voiceMap.values) v.id: v.name,
      };
      final now = DateTime.now();

      for (final item in pending) {
        if (peers.containsKey(item.postId)) continue;
        if (!item.scheduledAt.isAfter(now)) continue;
        schedule(
          'n_${item.id}',
          item.scheduledAt,
          '${nameById[item.personaId] ?? '社区住民'} 评论了你的帖子',
          '你有一条社区互动通知',
        );
      }
    } catch (error) {
      // 预约失败不影响 APP 本身，冷启动补发那条老路还在
      debugPrint('[通知] 这次没排上预约：$error');
    }
  }

  /// 策划模式发帖时调用：按脚本把事件排成**秒级**队列。
  ///
  /// `at` 支持 `"30"`（第 30 秒）与 `"30~90"`（区间内随机取一个时刻），
  /// 区间在排期时就算成确定的时间点——这样队列里存的是绝对时间，
  /// 每次心跳只需要比较大小，不必重算。
  Future<int> planFromScript({
    required String postId,
    required PlanScript script,
    Random? random,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rng = random ?? Random();

    final events = <PlannedPlanEvent>[];
    for (final step in script.steps) {
      if (!step.isValid) continue;
      events.add(PlannedPlanEvent(step: step, atMs: now + step.resolveMs(rng)));
    }
    events.sort((a, b) => a.atMs.compareTo(b.atMs));

    await planEvents.insertAll(
      postId: postId,
      scriptId: script.id,
      events: events,
    );
    return events.length;
  }

  /// 冷启动 / 回前台 / 心跳时调用：把到期的随机排期兑现成真实互动与通知。
  Future<int> flushDue() async {
    final due = await interactions.duePending(DateTime.now());
    if (due.isEmpty) return 0;

    final voiceMap =
        await voiceRepo?.byIds(due.map((item) => item.personaId)) ??
        const {};
    final nameById = {
      for (final v in voiceMap.values) v.id: v.name,
    };

    // 这些帖子里哪些是住民自己发的。住民动态下面也会来人——那是社区
    // 自己的动静，不是"有人回应了你"，所以照样记数、不通知用户。
    final peersPosts = await posts.residentAuthorsOf(
      due.map((item) => item.postId).toSet(),
    );

    for (final item in due) {
      await interactions.markExecuted(item.id);
      // 已经由前台兑现了，把系统里那条预约撤掉，别过一会儿又弹一次。
      cancelScheduledNotification?.call('n_${item.id}');

      // 用户把「网友互相接话」关了：已经排在队列里的 AI 接 AI 也不兑现，
      // 不然开关关了之后还会零星冒出一两句。
      if (item.isPeerReply && (readAiPeerLimit?.call() ?? 2) <= 0) {
        continue;
      }

      // 浏览事件：到点才留痕，不计数、不通知、不推进关系。
      if (item.type == 'view') {
        await voiceRepo?.recordView(
          postId: item.postId,
          voiceId: item.personaId,
          at: item.scheduledAt,
        );
        continue;
      }

      final name = nameById[item.personaId] ?? '社区住民';
      final isMyPost = !peersPosts.containsKey(item.postId);

      if (item.isLike) {
        await posts.addCounters(item.postId, likes: item.likeBatch);
        if (!isMyPost) continue;
        // 同一条帖子的赞合并成一行（“某某等 N 人赞了你的帖子”），
        // 不要每来一个人就插一条。
        final likeTitle = await notifications.mergeLike(
          postId: item.postId,
          actorName: name,
          count: item.likeBatch,
          at: item.scheduledAt,
        );
        // 锁屏上不会露内容（渠道设了 secret），所以正文写具体点没关系。
        notify?.call('n_group_like_${item.postId}', likeTitle, '你有一条社区互动通知');
      } else if (item.isComment) {
        final content = (item.content ?? '').trim();
        // 内容没写出来的评论不该兑现：不计评论数、不发通知、不推进关系。
        // 正常情况下 `upgradeCommentsWithModel` 已经把它们取消了，这里只是
        // 兜住"取消之前就被心跳扫到"的那一瞬。
        if (content.isEmpty) continue;

        await posts.addCounters(item.postId, comments: 1);
        if (!isMyPost) continue;
        // AI 接 AI 的话只在应用内出现，不叫醒手机，也不加红点。
        if (!item.isPeerReply) {
          // 表情包评论的 content 是文件路径，别把它铺到通知正文里。
          final preview = item.mediaType == 'image' ? '[表情包]' : content;
          await notifications.insert(
            id: 'n_${item.id}',
            postId: item.postId,
            type: 'comment',
            title: '$name 评论了你的帖子',
            body: preview,
            at: item.scheduledAt,
          );
          notify?.call('n_${item.id}', '$name 评论了你的帖子', preview);
        }

        // 合成语音（B8）。这一步跑在后台：语音要多等一两秒才出得来，
        // 冷启动没道理停在这儿等一段音频——评论先以文字露面，
        // 音频好了再换成语音条。
        unawaited(
          _maybeAttachVoice(
            item: item,
            persona: voiceMap[item.personaId]?.toPersona(),
            // 固定住民在每条帖子里都有一个 voice 快照，但嗓子要认人，
            // 不能认这个一帖一换的快照 id，否则同一个人每条帖子换声。
            speakerId: voiceMap[item.personaId]?.residentId,
          ),
        );

        // 顺便点个赞：评论区里“看到了、顺手赞一下”比每句都回更常见。
        unawaited(_maybeLikeComment(item: item));

        // 楼上这句话可能被另一个网友接住。只在顶层评论上接，
        // 不往楼中楼里继续叠；数量由设置里的“AI 互评上限”卡住。
        if (!item.isPeerReply && item.parentId == null) {
          unawaited(
            _maybeSchedulePeerReply(
              item: item,
              name: name,
              voiceMap: voiceMap,
            ),
          );
        }
      }

    }

    return due.length;
  }

  /// 脚本里写的这段语音素材在不在包里（B8）。
  ///
  /// 只认 `asset:` 一种：`file:` 与网络地址的可用性得问播放器，
  /// 而这里想回答的只是"仓库里到底有没有这段演示音频"。
  Future<bool> _voiceAssetAvailable(String? ref) async {
    if (ref == null || ref.isEmpty) return false;
    if (!ref.startsWith('asset:')) return true;
    try {
      await rootBundle.load(ref.substring('asset:'.length));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 把刚兑现的一条评论变成语音（B8）。
  ///
  /// 整段兜到底：它跑在后台，抛出去就是没人接的异常。而它可能失败的
  /// 理由有一堆——没放模型、引擎起不来、磁盘写不动——那些情况下
  /// 评论区保持纯文字就好，这不是塌天的事。
  Future<void> _maybeAttachVoice({
    required PendingInteraction item,
    required AiPersona? persona,
    String? speakerId,
  }) async {
    final speech = voice;
    if (speech == null || persona == null) return;
    // 临时网民还没定音色：先发文字，别拿默认嗓子冒充某个人。
    if (persona.voiceModel.isEmpty) return;
    if (!(readVoiceSettings?.call().enabled ?? true)) return;

    // 固定住民是不是发语音，交给它自己在唤醒里用工具决定；
    // 平台不替它掷这个骰子。
    final snapshot = await voiceRepo?.findById(item.personaId);
    if (snapshot?.residentId != null) return;

    final content = (item.content ?? '').trim();
    if (content.isEmpty) return;
    if (_random.nextDouble() > _voiceChance(persona)) return;

    try {
      final existing = await interactions.countVoicesForPost(item.postId);
      if (existing >= maxVoicesPerPost) return;

      final clip = await speech.speak(
        text: content,
        personaId: speakerId ?? persona.id,
        voiceModel: persona.voiceModel,
      );
      if (clip == null) return;

      await interactions.attachVoice(
        id: item.id,
        voicePath: clip.ref,
        transcript: clip.transcript,
        durationMs: clip.durationMs,
      );
    } catch (error) {
      debugPrint('[语音] 这条评论没能变成语音：$error');
    }
  }

  /// 一条评论变成语音的概率。语气标签只做很小的区分。
  static double _voiceChance(AiPersona persona) {
    final model = persona.voiceModel;
    if (model.contains('lazy') || model.contains('quiet')) return 0.34;
    if (model.contains('warm') || model.contains('soft')) return 0.22;
    return 0.16;
  }

  /// 一条帖子下面最多留几条语音。
  static const int maxVoicesPerPost = 2;

  /// AI 给评论点赞：每条最多 2 个，不通知、不写关系。
  Future<void> _maybeLikeComment({
    required PendingInteraction item,
  }) async {
    try {
      final repo = voiceRepo;
      if (repo == null) return;
      if (item.type != 'comment') return;
      if (_random.nextDouble() > 0.6) return;

      final existing = await interactions.countAiCommentLikes(item.id);
      if (existing >= 2) return;

      final all = await repo.byPost(item.postId);
      final others = [
        for (final voice in all)
          if (voice.isEphemeral && voice.id != item.personaId) voice,
      ]..shuffle(_random);
      if (others.isEmpty) return;

      final take = (1 + _random.nextInt(2)).clamp(0, 2 - existing);
      for (var i = 0; i < take && i < others.length; i++) {
        await interactions.addAiCommentLike(
          commentId: item.id,
          voiceId: others[i].id,
        );
      }
    } catch (error) {
      debugPrint('[围观] 这次的赞没点上：$error');
    }
  }

  /// AI 接 AI：评论区里另一个网友看到楼上这句话，可能接一句。
  ///
  /// 三条约束：只接顶层评论（不往楼中楼里叠）、每帖总数受设置限制、
  /// 同一对账号在同一条评论下只接一次。接不上就算了——不塞台词。
  Future<void> _maybeSchedulePeerReply({
    required PendingInteraction item,
    required String name,
    required Map<String, PostVoice> voiceMap,
  }) async {
    try {
      final limit = readAiPeerLimit?.call() ?? 2;
      if (limit <= 0) return;
      if (_random.nextDouble() > 0.55) return;

      final content = (item.content ?? '').trim();
      if (content.isEmpty) return;

      final count = await interactions.countPeerReplies(item.postId);
      if (count >= limit) return;

      final all = await voiceRepo?.byPost(item.postId) ?? const <PostVoice>[];
      final others = [
        for (final voice in all)
          if (voice.isEphemeral && voice.id != item.personaId) voice,
      ];
      if (others.isEmpty) return;

      final other = others[_random.nextInt(others.length)];
      if (await interactions.hasPeerReply(
        parentId: item.id,
        personaId: other.id,
      )) {
        return;
      }

      final post = await posts.findById(item.postId);
      if (post == null) return;

      final line = await generator.peerReply(
        thread: PeerReplyThread(
          persona: other.toPersona(),
          post: post,
          targetName: voiceMap[item.personaId]?.name ?? name,
          targetContent: content,
          understanding: await understandings?.find(item.postId),
        ),
      );
      final text = (line ?? '').trim();
      if (text.isEmpty) return;

      await interactions.insertFollowUp(
        postId: item.postId,
        personaId: other.id,
        content: text,
        parentId: item.id,
        replyToName: voiceMap[item.personaId]?.name ?? name,
        scheduledAt: DateTime.now().add(
          Duration(minutes: 1 + _random.nextInt(6)),
        ),
        source: 'peer_reply',
      );
    } catch (error) {
      // 接不上就接不上：评论区少一次来回，不是塌天的事
      debugPrint('[围观] 这次没接上 AI 的话：$error');
    }
  }

  /// 兑现到点的策划事件。
  ///
  /// 评论会额外写一条已完成的互动（评论区用的还是同一套查询），
  /// 点赞与"设定数据"直接改帖子计数，切模式与分析各自走自己的通道。
  Future<int> flushPlanEvents() async {
    final due = await planEvents.duePending(DateTime.now());
    if (due.isEmpty) return 0;

    for (final event in due) {
      await planEvents.markExecuted(event.id);

      switch (event.type) {
        case PlanStepType.comment:
          final personaId = event.personaId;
          if (personaId == null) break;

          // 新版评论区只认“这条帖子里出现过的人”（post_voices）。
          // 旧脚本写的是内置住民 id，直接插进 ai_interactions 会让评论
          // 没有名字和头像。这里先给 TA 在本帖落一个身份快照：
          // - 固定住民 → custom voice，以后还能认回主页和记忆；
          // - 内置住民 → 临时网友，复用它的名字、头像和音色。
          final seat = await _planSeat(event.postId, personaId);

          // 脚本里写死的语音素材不一定在仓库里（演示音频常由素材方另行提供）。
          // 找不到那段音频就**现合成一条**：声音还是这位住民的固定音色，
          // 内容就是脚本给的台词——总比镜头里挂着一个点不响的播放键强。
          //
          // 这一条刻意用 await（不像随机排期那样后补）：策划模式是要被拍进
          // 片子的，画面里不能出现"文字先出来、两秒后变成语音条"的跳动。
          var mediaType = event.mediaType;
          var voicePath = event.voiceAsset;
          var transcript = event.transcript;
          var durationMs = event.voiceDurationMs;

          // 语音开关关掉时，脚本里的语音也退回文字。已经生成的语音条
          // 照常能播，这里管的只是"别再产生新语音"。
          final voiceEnabled = readVoiceSettings?.call().enabled ?? true;
          if (mediaType == 'voice' && !voiceEnabled) {
            mediaType = 'text';
            voicePath = null;
            transcript = null;
            durationMs = null;
          } else if (mediaType == 'voice' &&
              !await _voiceAssetAvailable(voicePath)) {
            final clip = await voice?.speak(
              text: event.content ?? '',
              personaId: seat.voiceId,
              voiceModel: seat.voiceModel,
            );
            if (clip == null) {
              // 合成不出来就退回文字：脚本安排的是"收到一句回应"，
              // 那个回应本身比它用什么形式送到更重要。
              mediaType = 'text';
              voicePath = null;
              transcript = null;
              durationMs = null;
            } else {
              voicePath = clip.ref;
              transcript = clip.transcript;
              durationMs = clip.durationMs;
            }
          }

          await interactions.insertExecutedComment(
            id: 'evt_${event.id}',
            postId: event.postId,
            personaId: seat.voiceId,
            mediaType: mediaType,
            content: event.content,
            voicePath: voicePath,
            transcript: transcript,
            voiceDurationMs: durationMs,
          );
          await posts.addCounters(event.postId, comments: 1);
          await notifications.insert(
            id: 'n_${event.id}',
            postId: event.postId,
            type: 'comment',
            title: '${seat.name} 评论了你的帖子',
            body: event.content ?? '',
          );

        case PlanStepType.likeBurst:
          final delta = event.delta ?? 0;
          if (delta <= 0) break;
          await posts.addCounters(event.postId, likes: delta);
          await notifications.insert(
            id: 'n_${event.id}',
            postId: event.postId,
            type: 'like',
            title: delta > 1 ? '有 $delta 人赞了你的帖子' : '有人赞了你的帖子',
            body: '你有一条社区互动通知',
          );

        case PlanStepType.stats:
          await posts.setCounters(
            event.postId,
            likes: event.likes,
            comments: event.comments,
          );

        case PlanStepType.analysis:
          final raw = event.analysisJson;
          if (raw == null || raw.isEmpty) break;
          await analyses.insertFromPlan(
            postId: event.postId,
            analysis: PlanAnalysis.fromJson(
              jsonDecode(raw) as Map<String, dynamic>,
            ),
          );
      }
    }

    return due.length;
  }

  /// 策划事件里的评论者，在这条帖子里是谁。
  ///
  /// 旧住民下线之后，脚本只认固定住民；找不到就退回一个没有身份的名字。
  Future<_PlanSeat> _planSeat(String postId, String residentId) async {
    final repo = voiceRepo;
    final custom = await residents?.findById(residentId);
    if (custom == null || repo == null) {
      return _PlanSeat(
        voiceId: residentId,
        name: custom?.name ?? '社区住民',
        voiceModel: custom?.toPersona().voiceModel ?? '',
      );
    }

    final voiceId = 'voice_${custom.id}_$postId';
    if (await repo.findById(voiceId) == null) {
      await repo.insertAll([
        PostVoice(
          id: voiceId,
          postId: postId,
          kind: PostVoiceKind.custom,
          residentId: custom.id,
          name: custom.name,
          avatarAsset: custom.avatarAsset,
          bio: custom.bio,
          languageStyle: custom.languageStyle,
          tone: custom.tone,
          model: custom.toPersona().voiceModel,
          createdAt: DateTime.now(),
        ),
      ]);
    }
    return _PlanSeat(
      voiceId: voiceId,
      name: custom.name,
      voiceModel: custom.toPersona().voiceModel,
    );
  }

  /// 还剩多少条随机排期没到点（调试与"预告"用）。
  Future<int> pendingCount() => interactions.countPending();

  /// 还剩多少条策划事件没执行（心跳靠它决定要不要跑秒级）。
  Future<int> pendingPlanCount() => planEvents.countPending();
}

/// 策划事件里“这条评论由谁来说”的落点。
class _PlanSeat {
  const _PlanSeat({
    required this.voiceId,
    required this.name,
    required this.voiceModel,
  });

  final String voiceId;
  final String name;
  final String voiceModel;
}

final schedulerServiceProvider = Provider<SchedulerService>(
  (ref) => SchedulerService(
    interactions: ref.watch(interactionRepositoryProvider),
    planEvents: ref.watch(planEventRepositoryProvider),
    posts: ref.watch(postRepositoryProvider),
    notifications: ref.watch(notificationRepositoryProvider),
    analyses: ref.watch(analysisRepositoryProvider),
    generator: ref.watch(contentSourceProvider),
    voiceRepo: ref.watch(postVoiceRepositoryProvider),
    residents: ref.watch(customResidentRepositoryProvider),
    understandings: ref.watch(postUnderstandingRepositoryProvider),
    readAiPeerLimit: () =>
        ref.read(communitySettingsProvider).aiPeerInteractionLimit,
    readSendImagesDirectly: () =>
        ref.read(communitySettingsProvider).sendPostImagesDirectly,
    voice: ref.watch(ttsServiceProvider),
    readVoiceSettings: () => ref.read(voiceSettingsControllerProvider),
    // 只有后台补发才推通知栏（B10）：前台那条路上，应用内的红点已经够了。
    notify: ref.watch(inBackgroundTaskProvider)
        ? (key, title, body) => ref
              .read(systemNotificationProvider)
              .show(key: key, title: title, body: body)
        : null,
    scheduleNotification: (key, at, title, body) => ref
        .read(systemNotificationProvider)
        .schedule(key: key, at: at, title: title, body: body),
    cancelScheduledNotification: (key) =>
        ref.read(systemNotificationProvider).cancelScheduled(key),
  ),
);
