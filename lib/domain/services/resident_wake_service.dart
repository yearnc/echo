import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/media/media_service.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../data/repositories/post_voice_repository.dart';
import '../../data/repositories/private_message_repository.dart';
import '../../data/repositories/resident_inbox_repository.dart';
import '../../data/repositories/resident_wake_log_repository.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../models/custom_resident.dart';
import '../models/model_config.dart';
import '../models/post.dart';
import '../models/private_message.dart';
import '../models/resident_inbox.dart';
import '../models/resident_wake_log.dart';
import 'action_registry.dart';
import 'comment_reply_service.dart';
import 'content_generator.dart';
import 'dm_voice_service.dart';
import 'model_gateway.dart';
import 'resident_activity_controller.dart';
import 'tts_service.dart';
import 'resident_tool_session.dart';

enum WakeTrigger {
  /// 用户刚发了私信/评论，马上叫醒。
  userAction,

  /// 心跳周期性看一眼。
  heartbeat,

  /// 刚创建好这个住民，让他先开口。
  setup,

  /// 系统后台任务（WorkManager）叫醒。只处理收件箱里已有的待办，
  /// 不主动发帖、不主动私信——后台的时间预算和网络都不该拿来“创作”。
  background,
}

/// 唤醒式交互（v3.3）。
///
/// 以前固定住民是被"排期"驱动的：世界 tick 到点让它发帖，私信队列到点
/// 让它回一句，评论回复另开一条链路。它们彼此不知道对方存在，所以会出现
/// "帖子里不回你、私信里却回得很勤"这种分裂。
///
/// 现在统一成：**醒来 → 看收件箱 → 用工具决定回谁、怎么回、或者不回**。
/// 没有待办时，才允许它自己发帖、刷帖子、点赞、主动发私信。
class ResidentWakeService {
  ResidentWakeService({
    required this.db,
    required this.residents,
    required this.inbox,
    required this.gateway,
    required this.session,
    required this.actions,
    required this.posts,
    required this.voices,
    required this.interactions,
    required this.notifications,
    required this.profiles,
    required this.messages,
    required this.media,
    required this.commentReplies,
    required this.wakeLogs,
    this.dmVoice,
    this.activityDone,
  });

  final AppDatabase db;
  final CustomResidentRepository residents;
  final ResidentInboxRepository inbox;
  final ModelGateway gateway;
  final ResidentToolSession session;
  final ActionRegistry actions;
  final PostRepository posts;
  final PostVoiceRepository voices;
  final InteractionRepository interactions;
  final NotificationRepository notifications;
  final UserProfileRepository profiles;
  final PrivateMessageRepository messages;
  final MediaService media;
  final CommentReplyService commentReplies;

  /// 每次醒来的记录，以及“给未来的自己留言”（v3.9）。
  final ResidentWakeLogRepository wakeLogs;

  /// 私信回复可以变成语音条（可空：测试或关掉语音时保持文字）。
  final DmVoiceService? dmVoice;

  /// 一轮结束后收掉聊天页上的“正在思考…”。
  final void Function(String residentId)? activityDone;

  /// 同一个人不要被同时叫醒两次（用户点发送 + 心跳撞在一起）。
  final Set<String> _running = {};

  /// 正在醒着的时候又来了用户消息：这一轮结束后立刻再醒一次，
  /// 不要等下一个 30 秒心跳（更不能等 15 分钟冷却）。
  final Set<String> _rerun = {};

  /// 一轮 wakeAll 没跑完时，下一拍心跳不要再叠一轮。
  bool _wakingAll = false;

  /// 心跳唤醒的水位：每人每 15 分钟最多一次。
  final Map<String, DateTime> _lastWake = {};

  /// 没有待办时，主动找点事做的间隔。
  static const Duration idleGap = Duration(minutes: 90);

  /// 心跳唤醒的最小间隔。
  static const Duration heartbeatGap = Duration(minutes: 15);

  /// 文生图单独的超时。发出去的帖子必须图文完整，所以这里等得起；
  /// 90 秒是画一张图的正常上限，超过就退回纯文字，不把帖子卡死。
  static const Duration imageTimeout = Duration(seconds: 90);

  /// 一次唤醒最多发几段私信。
  static const int maxDmSegments = 3;

  /// 所有固定住民都看一眼（心跳用）。
  Future<int> wakeAll({WakeTrigger trigger = WakeTrigger.heartbeat}) async {
    if (_wakingAll) return 0;
    _wakingAll = true;
    try {
      final pool = await residents.all();
      var handled = 0;
      for (final resident in pool) {
        handled += await wake(resident.id, trigger: trigger);
      }
      return handled;
    } finally {
      _wakingAll = false;
    }
  }

  /// 后台任务用：只叫醒**真的有待办**的人，而且限制人数。
  ///
  /// WorkManager 一轮只有有限的执行时间，串行叫醒六个人、每人再跑最多
  /// 20 秒模型，很容易在这一轮里跑不完。没待办的人本来也不该被后台吵醒。
  /// 有人的话先回，没人说话的人也轮一轮（v41）：后台不再只“补待办”，
  /// 否则 APP 长期不开时，固定住民读不到新帖、也没机会自己发帖子。
  /// 除了语音，后台能用完整的一套工具。
  Future<int> wakePending({int maxResidents = 3}) async {
    final pool = await residents.all();
    if (pool.isEmpty) return 0;

    // 先看每个人手里有没有待办、上次醒是什么时候，再统一排队。
    // 以前是按住民创建顺序取前三个——前三个总有事的话，排在后面的
    // 在后台永远轮不到（只有用户打开 APP 才会被 wakeAll 叫醒）。
    final oldestPendingAt = <String, DateTime?>{};
    final lastWakeAt = <String, DateTime?>{};
    for (final resident in pool) {
      await inbox.sync(resident.id);
      final pending = await inbox.pending(resident.id);
      oldestPendingAt[resident.id] = pending.isEmpty
          ? null
          : pending.first.createdAt;
      lastWakeAt[resident.id] = await _idleAt(resident.id);
    }

    final order = backgroundOrder(
      ids: [for (final resident in pool) resident.id],
      lastWakeAt: lastWakeAt,
      oldestPendingAt: oldestPendingAt,
      idleGap: idleGap,
      now: DateTime.now(),
    );

    var woken = 0;
    for (final id in order.take(maxResidents)) {
      woken += await wake(id, trigger: WakeTrigger.background);
    }
    return woken;
  }

  /// 后台唤醒的优先级：有待办的先（最早没处理的更急），
  /// 再按“最久没醒”排（从没醒过的排最前）；没到空闲间隔的不参与。
  @visibleForTesting
  static List<String> backgroundOrder({
    required List<String> ids,
    required Map<String, DateTime?> lastWakeAt,
    required Map<String, DateTime?> oldestPendingAt,
    required Duration idleGap,
    required DateTime now,
  }) {
    final candidates = <String>[];
    for (final id in ids) {
      if (oldestPendingAt[id] != null) {
        candidates.add(id);
        continue;
      }
      final last = lastWakeAt[id];
      if (last == null || now.difference(last) >= idleGap) {
        candidates.add(id);
      }
    }

    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    candidates.sort((a, b) {
      final aPending = oldestPendingAt[a];
      final bPending = oldestPendingAt[b];
      // 有待办的永远排在“只是闲着”的前面。
      if ((aPending != null) != (bPending != null)) {
        return aPending != null ? -1 : 1;
      }
      if (aPending != null && bPending != null) {
        final byPending = aPending.compareTo(bPending);
        if (byPending != 0) return byPending;
      }
      final byLast = (lastWakeAt[a] ?? epoch).compareTo(lastWakeAt[b] ?? epoch);
      if (byLast != 0) return byLast;
      // 时间完全一样时按 id 定序，保证结果稳定、测试不抖。
      return a.compareTo(b);
    });
    return candidates;
  }

  Future<bool> _idleDue(String residentId) async {
    final idleAt = await _idleAt(residentId);
    return idleAt == null || DateTime.now().difference(idleAt) >= idleGap;
  }

  /// “上一次醒来”的水位必须落盘：只放内存的话，每次冷启动都算
  /// 从来没有醒过，所有住民会一起被叫醒。
  static String _idleKey(String residentId) => 'wake.idleAt.$residentId';

  Future<DateTime?> _idleAt(String residentId) async {
    final query = db.select(db.appSettings)
      ..where((t) => t.key.equals(_idleKey(residentId)));
    final row = await query.getSingleOrNull();
    final raw = int.tryParse(row?.value ?? '');
    return raw == null ? null : DateTime.fromMillisecondsSinceEpoch(raw);
  }

  /// 设置页里的「固定住民动态」开关，默认关。唤醒时也要认它——
  /// 不认的话，用户关了开关，住民照样在信息流里发帖。
  Future<bool> _residentPostsAllowed() async {
    const key = 'community.allowResidentPosts';
    final query = db.select(db.appSettings)..where((t) => t.key.equals(key));
    final row = await query.getSingleOrNull();
    return row?.value == 'true';
  }

  Future<void> _touchIdle(String residentId) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _idleKey(residentId),
            value: DateTime.now().millisecondsSinceEpoch.toString(),
          ),
        );
  }

  Future<int> wake(
    String residentId, {
    WakeTrigger trigger = WakeTrigger.heartbeat,
  }) async {
    if (_running.contains(residentId)) {
      // 用户又发了一句：不能丢。等他这一轮收尾后马上再醒一次。
      if (trigger == WakeTrigger.userAction) _rerun.add(residentId);
      return 0;
    }
    _running.add(residentId);
    try {
      return await _wake(residentId, trigger);
    } finally {
      _running.remove(residentId);
      if (_rerun.remove(residentId)) {
        unawaited(wake(residentId, trigger: WakeTrigger.userAction));
      }
    }
  }

  Future<int> _wake(String residentId, WakeTrigger trigger) async {
    final last = _lastWake[residentId];
    final now = DateTime.now();
    if (trigger == WakeTrigger.heartbeat &&
        last != null &&
        now.difference(last) < heartbeatGap) {
      return 0;
    }

    final resident = await residents.findById(residentId);
    if (resident == null) return 0;

    await inbox.sync(residentId);
    final pending = await inbox.pending(residentId);

    // 没有待办时，只有 setup 和“好久没动静了”才值得醒一次；
    // 否则住户每 15 分钟醒一次，醒来又没事干，只是白花钱。
    // **用户主动发消息是例外**：他就在屏幕前等着，哪怕收件箱因为时序
    // 没整理出待办，也得让住民看一眼最近的对话。
    //
    // v41 起后台也不再只补待办：APP 长期不开时，固定住民也该有机会
    // 刷到新帖子、自己发一条。仍按 1.5 小时空闲间隔限流，不会每 15 分钟吵醒。
    if (pending.isEmpty &&
        (trigger == WakeTrigger.heartbeat ||
            trigger == WakeTrigger.background)) {
      if (!await _idleDue(residentId)) return 0;
      // 内存里的冷却只防同一进程内的心跳扎堆；落盘的水位防冷启动扎堆。
      if (last != null && now.difference(last) < heartbeatGap) {
        return 0;
      }
    }

    final config = await gateway.configFor(configId: resident.modelConfigId);
    if (config == null) {
      // 没配模型时待办必须留着：不能因为这次醒不成，就把消息标成已读。
      debugPrint('[唤醒] ${resident.name}：还没配置对话模型');
      return 0;
    }

    final wakeId = 'wake_${residentId}_${now.microsecondsSinceEpoch}';
    // 日志失败不该拦住这一轮：它只是回忆，不是业务。
    ResidentWakeLog? lastNote;
    try {
      await wakeLogs.start(
        id: wakeId,
        residentId: residentId,
        trigger: _triggerKey(trigger),
        at: now,
      );
      lastNote = await wakeLogs.lastNote(residentId, excludeId: wakeId);
    } catch (error) {
      debugPrint('[唤醒] 日志没记上：$error');
    }
    // 一次最多看二十条。不按“最多回三个人”硬性截断——
    // 积攒的评论该回就回；真的处理不完的留在收件箱，下次醒来继续。
    // 不能把没展示过的待办也标成“已读”，那等于替模型做了决定。
    final visible = pending.take(20).toList(growable: false);
    // 上一轮写好、还没发出去的段：用户中途又说话时它们已经被取消了，
    // 这里把原话交给住民，由它决定照发、改写还是算了。
    final unsent = await messages.pendingSegments(residentId);
    final toolkit = _WakeToolkit(
      service: this,
      resident: resident,
      wakeId: wakeId,
      pending: visible,
      now: now,
      // v41：后台也允许主动行为（发帖/评论/点赞/刷帖子/画图），
      // 只有语音因为耗时太长、后台预算不稳定而不开放。
      allowProactive: true,
      allowVoice: trigger != WakeTrigger.background,
    );

    try {
      final recent = await messages.recentTurns(residentId, limit: 10);
      final history = [
        for (final turn in recent)
          DirectTurn(
            fromMe: !turn.fromMe,
            text: switch (turn.mediaType) {
              'image' => turn.fromMe ? '' : '[发来一张图片]',
              'sticker' => '[表情包]',
              _ => turn.content,
            },
            caption: turn.caption,
            imageRef: turn.mediaType == 'image' && turn.fromMe
                ? turn.content
                : null,
            at: turn.createdAt,
          ),
      ];
      // 把它自己最近做过的事告诉它——这是信息，不是决定。
      // 要不要记进记忆、要不要接着说，由它自己判断。
      final ownActivity = await _recentOwnActivity(residentId);
      final said = await session.act(
        resident: resident,
        config: config,
        situation: _situation(
          resident,
          visible,
          trigger,
          ownActivity: ownActivity,
          unsent: unsent,
          lastNote: lastNote,
        ),
        toolkit: toolkit,
        at: now,
        history: history,
        allowProactive: true,
        allowVoice: toolkit.allowVoice,
      );

      // 模型没调工具、只回了一句话：当作私信发出去。
      // 这既兜住了不支持 tool calling 的模型，也兜住“它就是想直接说话”。
      if (said.trim().isNotEmpty && !toolkit.spokePrivately) {
        await toolkit.sendDm(said.trim(), 'fallback');
      }

      // 交给它看过的暂停段，如果它既没改写也没取消，就当作不要了——
      // 否则这些段会在每次醒来时反复出现。中途新暂停的段不在这里，
      // 留给下一轮处理。
      if (unsent.isNotEmpty) {
        await messages.expirePausedSegments(
          unsent.map((segment) => segment.id),
        );
      }

      // 这一轮结束了，剩下的都是“看过了但没回”。必须落一个 handled，
      // 否则下次醒来又是同一批，永远处理不完。
      if (!toolkit.finished) {
        await inbox.markHandled(
          visible.map((item) => item.id),
          decision: 'skipped',
          wakeId: wakeId,
        );
      }
      await toolkit.flushImage();
      _lastWake[residentId] = DateTime.now();
      await _touchIdle(residentId);
      return pending.length;
    } catch (error) {
      // 失败不标记：留着待办，下个心跳再试。
      debugPrint('[唤醒] ${resident.name} 这次没醒成：$error');
      await toolkit.flushImage();
      return 0;
    } finally {
      try {
        await wakeLogs.finish(wakeId, at: DateTime.now());
        // 留言已经进过这一轮的上下文，之后不再反复带上。
        if (lastNote != null) {
          await wakeLogs.markNoteDelivered(lastNote.id);
        }
      } catch (error) {
        debugPrint('[唤醒] 日志收尾没记上：$error');
      }
      activityDone?.call(residentId);
    }
  }

  static String _triggerKey(WakeTrigger trigger) => switch (trigger) {
    WakeTrigger.userAction => 'user_action',
    WakeTrigger.heartbeat => 'heartbeat',
    WakeTrigger.background => 'background',
    WakeTrigger.setup => 'setup',
  };

  String _situation(
    CustomResident resident,
    List<ResidentInboxItem> pending,
    WakeTrigger trigger, {
    String ownActivity = '',
    List<PendingSegment> unsent = const [],
    ResidentWakeLog? lastNote,
  }) {
    final String base;
    if (pending.isEmpty) {
      base = switch (trigger) {
        WakeTrigger.setup =>
          '你刚住进这里，还没有人跟你说话。你可以主动给对方发一条私信，'
              '像刚加了好友那样打个招呼；不想发也可以什么都不做。',
        WakeTrigger.userAction =>
          '对方刚给你发了消息，你还没回。翻一翻你们最近的私信，'
              '看看他说了什么、要不要接一句；也可以已读不回。',
        WakeTrigger.heartbeat =>
          '手机上没有新消息。你可以自己发条动态、刷一刷别人发的帖子、'
              '点个赞，或者给聊过的人发条私信；也可以就搁着。',
        WakeTrigger.background => '手机上没有新消息。',
      };
    } else {
      final buffer = StringBuffer()..writeln('你醒来看到这些还没处理：');
      for (final item in pending) {
        final when = ResidentToolSession.timeLabel(item.createdAt);
        final line = switch (item.kind) {
          ResidentInboxRepository.kindCommentOnPost =>
            '有人在你的帖子下评论：「${item.summary}」',
          ResidentInboxRepository.kindReplyToComment =>
            '有人回了你的评论：「${item.summary}」',
          ResidentInboxRepository.kindDm => '给你发了私信：「${item.summary}」',
          _ => '「${item.summary}」',
        };
        buffer.writeln('- [${item.id}] [$when] $line');
      }
      buffer.writeln();
      buffer.writeln(
        '评论类用 reply_inbox 回在评论下面；私信类用 send_dm 回。'
        '也可以只读不回：最后调用 finish。',
      );
      base = buffer.toString();
    }

    final parts = <String>[base.trimRight()];
    if (unsent.isNotEmpty) {
      final buffer = StringBuffer()
        ..writeln()
        ..writeln(
          '你上一轮还有 ${unsent.length} 段话没发出去——对方中途又说话了，'
          '平台先把它们暂停了。原话如下：',
        );
      for (final segment in unsent) {
        buffer.writeln(
          '- [${segment.id}] 第 ${segment.index + 1} 段（原定 '
          '${ResidentToolSession.timeLabel(segment.at)}）：「${segment.preview}」',
        );
      }
      buffer.writeln(
        '要不要照发、要不要改写、还是算了，都由你决定：'
        'send_dm 可以重新说一句；rewrite_pending_segment 改掉某一段；'
        'cancel_pending_segment 取消某一段。',
      );
      parts.add(buffer.toString().trimRight());
    }
    if (lastNote != null && lastNote.hasNote) {
      parts.add(
        '上一次醒来时（${ResidentToolSession.timeLabel(lastNote.noteAt ?? lastNote.wokeAt)}）'
        '你给现在的自己留了一句话：\n「${lastNote.note.trim()}」',
      );
    }
    if (ownActivity.trim().isNotEmpty) {
      parts.add(
        '你最近做过的事，以及它们的动静（只是给你信息；'
        '要不要在意、要不要记、要不要接着说，都由你）：\n$ownActivity',
      );
    }
    return parts.join('\n');
  }

  /// 它自己最近发过的动态，以及这些动态收到的赞/评论/浏览。
  ///
  /// 只读、只给信息：TA 可以因此高兴，也可以完全不在意；平台不替它
  /// 生成“被赞了”的情绪，也不把这件事塞进收件箱要求回应。
  Future<String> _recentOwnActivity(String residentId) async {
    try {
      final list = await posts.watchByResident(residentId).first;
      if (list.isEmpty) return '';
      final lines = <String>[];
      for (final post in list.take(3)) {
        var views = 0;
        try {
          views = await voices.viewCount(post.id);
        } catch (error) {
          debugPrint('[唤醒] 这条动态的浏览量没读到：$error');
        }
        lines.add(
          '- ${_shortWhen(post.createdAt)} 发过动态：${_clip(post.content, 60)}'
          '（赞 ${post.likeCount} · 评论 ${post.commentCount} · 看过 $views）',
        );
      }
      return lines.join('\n');
    } catch (error) {
      debugPrint('[唤醒] 这次没读到它自己的动态：$error');
      return '';
    }
  }

  static String _shortWhen(DateTime at) {
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '${at.month}月${at.day}日 $hh:$mm';
  }

  static String _clip(String text, int length) {
    final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length <= length) return clean;
    return '${clean.substring(0, length)}…';
  }

  /// 把一条评论回复排进发送队列。
  Future<ActionOutcome> _replyComment(
    ResidentInboxItem item,
    String content,
    String callId,
  ) async {
    final text = content.trim();
    if (text.isEmpty) {
      return const ActionOutcome(ok: false, message: '回复是空的');
    }
    final postId = item.postId;
    if (postId == null) {
      return const ActionOutcome(ok: false, message: '这条待办没有对应的帖子');
    }

    final resident = await residents.findById(item.residentId);
    if (resident == null) {
      return const ActionOutcome(ok: false, message: '住民不在了');
    }
    final voice = await commentReplies.ensureVoice(
      postId: postId,
      resident: resident,
    );
    if (voice == null) {
      return const ActionOutcome(ok: false, message: '没能在这条帖子里找到身份');
    }

    final me = (await profiles.load())?.displayName ?? '我';
    await interactions.insertFollowUp(
      postId: postId,
      personaId: voice.id,
      content: text,
      parentId: item.refId,
      replyToName: me,
      scheduledAt: DateTime.now().add(
        Duration(seconds: 20 + (callId.hashCode.abs() % 100)),
      ),
    );
    await inbox.markHandled([item.id], decision: 'replied');
    // 记忆不替它写：这条工具结果已经回到它手里，
    // 要不要记、记成什么，由它自己用 memory_write 决定。
    return const ActionOutcome(ok: true, message: '已排在评论下面');
  }

  Future<ActionOutcome> _sendDm(
    CustomResident resident,
    String content,
    String wakeId,
    String callId,
    int segment,
    Duration baseDelay,
    List<ResidentInboxItem> pending,
    Set<String> alreadyRepliedDm,
    int segmentGapSeconds, {
    bool asVoice = false,
  }) async {
    final text = content.trim();
    if (text.isEmpty) {
      return const ActionOutcome(ok: false, message: '消息是空的');
    }
    if (segment >= maxDmSegments) {
      return const ActionOutcome(ok: false, message: '一次醒来最多发三段');
    }
    final speech = dmVoice;
    final wantsVoice = asVoice;
    if (wantsVoice) {
      if (speech == null) {
        return const ActionOutcome(
          ok: false,
          message: '当前不能合成语音，改用 send_dm 发文字',
        );
      }
      if (!resident.voiceEnabled) {
        return const ActionOutcome(
          ok: false,
          message: '你还没有配置音色，改用 send_dm 发文字',
        );
      }
    }

    // 语音必须**先合成成功再落库**：不能让用户先看到一行文字，
    // 再悄悄变成语音。失败时把原因原样交回给模型，让它自己决定
    // 是改用文字、换句话再试，还是先解释一下。
    VoiceClip? clip;
    if (wantsVoice) {
      final result = await speech!.synthesize(resident: resident, text: text);
      if (result.clip == null) {
        return ActionOutcome(
          ok: false,
          message:
              '语音没合成出来：${result.error}。'
              '你可以先用 send_dm 发文字，或者换个说法再试一次。',
        );
      }
      clip = result.clip;
    }

    final at = DateTime.now().add(
      baseDelay + Duration(seconds: segment * segmentGapSeconds),
    );
    final outcome = await actions.sendDirectMessage(
      residentId: resident.id,
      content: text,
      at: at,
      idempotencyKey: 'dm:$wakeId:$callId',
      source: 'wake',
      mediaType: wantsVoice ? 'voice' : 'text',
      voicePath: clip?.ref ?? '',
      transcript: clip?.transcript ?? '',
      // v41：同一轮写出的段带同一个 group，用户可以中途打断。
      deliveryGroup: wakeId,
      deliveryIndex: segment,
    );
    if (!outcome.ok) return outcome;

    // 这一轮已经回了私信，就把私信待办标掉，别让下一轮又看到它。
    final dmIds = [
      for (final item in pending)
        if (item.kind == ResidentInboxRepository.kindDm &&
            alreadyRepliedDm.add(item.id))
          item.id,
    ];
    if (dmIds.isNotEmpty) {
      await inbox.markHandled(dmIds, decision: 'replied');
    }
    // 记忆不替它写：工具结果已经告诉它“发出去了”，
    // 要不要把这句话记进长期记忆，由它自己决定。
    return wantsVoice
        ? ActionOutcome(
            ok: true,
            message: '语音已经发出，转写稿也一起显示了',
            data: outcome.data,
          )
        : outcome;
  }

  Future<ActionOutcome> _createPost(
    CustomResident resident,
    String content,
    String? topic,
    String callId,
    Future<Uint8List?>? image,
  ) async {
    final text = content.trim();
    if (text.isEmpty) {
      return const ActionOutcome(ok: false, message: '动态是空的');
    }
    if (!await _residentPostsAllowed()) {
      return const ActionOutcome(ok: false, message: '用户关掉了“固定住民动态”，别发帖');
    }

    Uint8List? bytes;
    if (image != null) {
      try {
        // 发出去的帖子就是完整的：宁可多等这一会儿，也不发完再补图。
        bytes = await image.timeout(imageTimeout);
      } catch (error) {
        debugPrint('[唤醒] 配图没生成出来，这条发纯文字：$error');
      }
    }

    final outcome = await actions.createResidentPost(
      residentId: resident.id,
      content: text,
      topicName: topic,
      idempotencyKey: 'post:${resident.id}:$callId',
      source: 'wake',
    );
    if (!outcome.ok) return outcome;

    if (bytes != null) {
      final postId = outcome.data['postId'];
      if (postId is String) {
        try {
          final ref = await media.saveBytes(bytes);
          final attached = await posts.attachImages(postId, [ref]);
          if (attached == 0) await media.deleteByRef(ref);
        } catch (error) {
          debugPrint('[唤醒] 图存下来了但没挂上：$error');
        }
      }
    }

    // 记忆不替它写：动态已经发出，它可以在同一轮里自己用 memory_write 记。
    return outcome;
  }

  /// 住民“看过了”这条帖子：在帖子里落一个身份快照，再写一条浏览记录。
  ///
  /// v3.9 修正：刷帖**要留痕**。以前 browse_feed 是纯读，用户点开浏览量
  /// 名单找不到刚刷过、甚至刚点过赞的固定住民，看起来像数据丢了。
  /// 自己的帖子不算“看过自己”，跳过。
  Future<void> markSeen({
    required CustomResident resident,
    required Post post,
  }) async {
    if (post.authorResidentId == resident.id) return;
    try {
      final voice = await commentReplies.ensureVoice(
        postId: post.id,
        resident: resident,
      );
      if (voice == null) return;
      await voices.recordView(postId: post.id, voiceId: voice.id);
    } catch (error) {
      // 浏览记录失败不该拦住刷帖本身。
      debugPrint('[唤醒] ${resident.name} 的浏览没记上：$error');
    }
  }

  /// 刷帖返回的一条帖子：把作者、时间、话题和计数都摊开。
  ///
  /// 纯函数，不写库；浏览记录由 [markSeen] 负责。
  @visibleForTesting
  static Map<String, Object?> feedEntry(Post post, {String? authorName}) {
    return {
      'id': post.id,
      'author': post.authorResidentId == null ? '你' : (authorName ?? '已离开的住民'),
      'author_type': post.authorResidentId == null ? '用户' : '固定住民',
      'time': ResidentToolSession.timeLabel(post.createdAt),
      'topic': post.topicName ?? '',
      'content': post.content.length > 120
          ? '${post.content.substring(0, 120)}…'
          : post.content,
      'likes': post.likeCount,
      'comments': post.commentCount,
      'images': post.images.length,
    };
  }
}

/// 一次唤醒的工具实现。它知道每条待办背后的表，工具定义本身不知道。
class _WakeToolkit implements ResidentWakeToolkit {
  _WakeToolkit({
    required this.service,
    required this.resident,
    required this.wakeId,
    required this.pending,
    required this.now,
    required this.allowProactive,
    required this.allowVoice,
  });

  final ResidentWakeService service;
  final CustomResident resident;
  final String wakeId;
  final List<ResidentInboxItem> pending;
  final DateTime now;
  final bool allowProactive;

  /// 后台唤醒不给语音：合成一句话几十秒，后台预算扛不住。
  final bool allowVoice;

  bool finished = false;
  bool spokePrivately = false;
  int _dmSegments = 0;
  final Set<String> _repliedDm = {};
  Future<Uint8List?>? _image;

  Future<void> flushImage() async {
    final image = _image;
    _image = null;
    if (image == null) return;
    try {
      await image.timeout(ResidentWakeService.imageTimeout);
    } catch (_) {
      // 没用来配帖的图直接丢掉，不落盘。
    }
  }

  @override
  Future<ActionOutcome> replyInbox(
    String itemId,
    String content,
    String callId,
  ) async {
    ResidentInboxItem? item;
    for (final candidate in pending) {
      if (candidate.id == itemId) {
        item = candidate;
        break;
      }
    }
    if (item == null) {
      return const ActionOutcome(ok: false, message: '没有这条待办，先看清单里的 id');
    }
    if (item.kind == ResidentInboxRepository.kindDm) {
      return const ActionOutcome(ok: false, message: '私信请用 send_dm');
    }
    return service._replyComment(item, content, callId);
  }

  @override
  Future<ActionOutcome> sendDm(String content, String callId) async {
    final outcome = await service._sendDm(
      resident,
      content,
      wakeId,
      callId,
      _dmSegments,
      // 用户刚发来消息——他就在屏幕前等着。3 秒起步、每多一段再加 6 秒，
      // 像真人打一行字，又不会让人以为界面卡住了。
      const Duration(seconds: 3),
      pending,
      _repliedDm,
      6,
    );
    if (outcome.ok) {
      _dmSegments++;
      spokePrivately = true;
    }
    return outcome;
  }

  @override
  Future<ActionOutcome> sendVoice(String content, String callId) async {
    if (!allowVoice) {
      return const ActionOutcome(ok: false, message: '后台唤醒不发语音，改用 send_dm 发文字');
    }
    final outcome = await service._sendDm(
      resident,
      content,
      wakeId,
      callId,
      _dmSegments,
      const Duration(seconds: 3),
      pending,
      _repliedDm,
      6,
      asVoice: true,
    );
    if (outcome.ok) {
      _dmSegments++;
      spokePrivately = true;
    }
    return outcome;
  }

  @override
  Future<ActionOutcome> sendSticker(
    String stickerId,
    String tag,
    String callId,
  ) async {
    if (_dmSegments >= ResidentWakeService.maxDmSegments) {
      return const ActionOutcome(ok: false, message: '一次醒来最多发三段');
    }
    final chosen = await service.actions.chooseSticker(id: stickerId, tag: tag);
    if (!chosen.ok) return chosen;
    final path = chosen.data['path'];
    if (path is! String || path.isEmpty) {
      return const ActionOutcome(ok: false, message: '没有选中表情包');
    }

    final at = DateTime.now().add(
      const Duration(seconds: 3) + Duration(seconds: 6 * _dmSegments),
    );
    final outcome = await service.actions.sendStickerMessage(
      residentId: resident.id,
      stickerPath: path,
      at: at,
      idempotencyKey: 'sticker:${resident.id}:$callId',
      deliveryGroup: wakeId,
      deliveryIndex: _dmSegments,
    );
    if (!outcome.ok) return outcome;

    _dmSegments++;
    spokePrivately = true;
    final dmIds = [
      for (final item in pending)
        if (item.kind == ResidentInboxRepository.kindDm &&
            _repliedDm.add(item.id))
          item.id,
    ];
    if (dmIds.isNotEmpty) {
      await service.inbox.markHandled(dmIds, decision: 'replied');
    }
    return const ActionOutcome(ok: true, message: '表情包已发出');
  }

  @override
  Future<ActionOutcome> cancelPendingSegment(String segmentId) async {
    if (segmentId.trim().isEmpty) {
      return const ActionOutcome(ok: false, message: '没有给段 id');
    }
    final ok = await service.messages.cancelPendingSegment(segmentId.trim());
    return ok
        ? const ActionOutcome(ok: true, message: '这一段不发了')
        : const ActionOutcome(ok: false, message: '这段已经发出去了，或者不在待发队列里');
  }

  @override
  Future<ActionOutcome> rewritePendingSegment(
    String segmentId,
    String content,
  ) async {
    if (segmentId.trim().isEmpty) {
      return const ActionOutcome(ok: false, message: '没有给段 id');
    }
    final text = content.trim();
    if (text.isEmpty) {
      return const ActionOutcome(ok: false, message: '改写的内容是空的');
    }
    final ok = await service.messages.rewritePendingSegment(
      segmentId: segmentId.trim(),
      content: text,
    );
    return ok
        ? const ActionOutcome(ok: true, message: '这一段已经改成新的话')
        : const ActionOutcome(ok: false, message: '这段已经发出去了，或者不在待发队列里');
  }

  @override
  Future<ActionOutcome> finish() async {
    finished = true;
    await service.inbox.markHandled(
      pending.map((item) => item.id),
      decision: 'ignored',
      wakeId: wakeId,
    );
    return const ActionOutcome(ok: true, message: '已读不回');
  }

  @override
  Future<ActionOutcome> browseFeed() async {
    final recent = await service.posts.recentForAudience(limit: 6);
    if (recent.isEmpty) {
      return const ActionOutcome(ok: true, message: '最近没什么新帖子');
    }
    // 刷到就算看过：逐条落身份快照 + 浏览记录，
    // 这样用户点开浏览量名单能看到 TA 来过。
    for (final post in recent) {
      await service.markSeen(resident: resident, post: post);
    }
    // 作者名要查住民表；用户在信息流里没有 id，直接标成「你」。
    final names = <String, String>{};
    for (final post in recent) {
      final id = post.authorResidentId;
      if (id == null || names.containsKey(id)) continue;
      final author = await service.residents.findById(id);
      names[id] = author?.name ?? '已离开的住民';
    }
    return ActionOutcome(
      ok: true,
      data: {
        'posts': [
          for (final post in recent)
            ResidentWakeService.feedEntry(
              post,
              authorName: post.authorResidentId == null
                  ? null
                  : names[post.authorResidentId],
            ),
        ],
      },
    );
  }

  @override
  Future<ActionOutcome> commentPost(
    String postId,
    String content,
    String callId,
  ) async {
    final text = content.trim();
    if (text.isEmpty) {
      return const ActionOutcome(ok: false, message: '评论是空的');
    }
    final post = await service.posts.watchById(postId).first;
    if (post == null) {
      return const ActionOutcome(ok: false, message: '没有这条帖子');
    }
    if (post.authorResidentId == resident.id) {
      return const ActionOutcome(
        ok: false,
        message: '这是你自己的帖子，回评论请用 reply_inbox',
      );
    }

    final voice = await service.commentReplies.ensureVoice(
      postId: postId,
      resident: resident,
    );
    if (voice == null) {
      return const ActionOutcome(ok: false, message: '没能在这条帖子里找到身份');
    }
    // 留过言的人当然算看过，浏览名单里也要有 TA。
    await service.voices.recordView(postId: postId, voiceId: voice.id);

    await service.interactions.insertExecutedComment(
      id:
          'wake_comment_${resident.id}_'
          '${DateTime.now().microsecondsSinceEpoch}',
      postId: postId,
      personaId: voice.id,
      mediaType: 'text',
      content: text,
    );
    await service.posts.addCounters(postId, comments: 1);
    if (post.authorResidentId == null) {
      try {
        await service.notifications.insert(
          id:
              'n_wake_${resident.id}_'
              '${DateTime.now().microsecondsSinceEpoch}',
          postId: postId,
          type: 'comment',
          title: '${resident.name} 评论了你的帖子',
          body: text,
          at: DateTime.now(),
        );
      } catch (error) {
        debugPrint('[唤醒] 评论通知没写进去：$error');
      }
    }
    return const ActionOutcome(ok: true, message: '评论已发出');
  }

  @override
  Future<ActionOutcome> likePost(String postId, String callId) async {
    final post = await service.posts.watchById(postId).first;
    if (post == null) {
      return const ActionOutcome(ok: false, message: '没有这条帖子');
    }
    // 点过赞就是来过：先落身份快照和浏览记录，再记这一颗心。
    await service.markSeen(resident: resident, post: post);
    final outcome = await service.actions.likePost(
      residentId: resident.id,
      postId: postId,
      // 同一个人对同一条帖子只能点一次；跨唤醒也去重。
      idempotencyKey: 'like:${resident.id}:$postId',
    );
    return outcome;
  }

  @override
  Future<ActionOutcome> generateImage(String prompt, String callId) async {
    final clean = prompt.trim();
    if (clean.isEmpty) {
      return const ActionOutcome(ok: false, message: '画面描述是空的');
    }
    if (_image != null) {
      return const ActionOutcome(ok: false, message: '这一轮已经有一张图在画了');
    }
    final config = await service.gateway.activeConfig(kind: ModelKind.image);
    if (config == null) {
      return const ActionOutcome(ok: false, message: '还没配置文生图模型');
    }
    _image = service.gateway.generateImage(config: config, prompt: clean);
    return const ActionOutcome(ok: true, message: '已在后台开始画，继续做别的事；发动态时会带上这张图');
  }

  @override
  Future<ActionOutcome> checkWakeLog(int days) async {
    final span = days.clamp(1, 7);
    try {
      final today = await service.wakeLogs.today(resident.id);
      final recent = await service.wakeLogs.recent(resident.id, days: span);
      return ActionOutcome(
        ok: true,
        data: {
          'today_count': today.length,
          'today_times': [
            for (final log in today.reversed)
              ResidentToolSession.timeLabel(log.wokeAt),
          ],
          'days': span,
          'entries': [
            for (final log in recent)
              {
                'time': ResidentToolSession.timeLabel(log.wokeAt),
                'trigger': log.triggerLabel,
                'note': log.note,
              },
          ],
        },
      );
    } catch (error) {
      return ActionOutcome(ok: false, message: '日志读不出来：$error');
    }
  }

  @override
  Future<ActionOutcome> leaveNote(String content) async {
    final text = content.trim();
    if (text.isEmpty) {
      return const ActionOutcome(ok: false, message: '留言是空的');
    }
    final ok = await service.wakeLogs.setNote(wakeId, text);
    return ok
        ? const ActionOutcome(ok: true, message: '留好了，下一次醒来会先看到这句话')
        : const ActionOutcome(ok: false, message: '这次醒来没有日志可写');
  }

  @override
  Future<ActionOutcome> createPost(
    String content,
    String? topic,
    String callId,
  ) async {
    final outcome = await service._createPost(
      resident,
      content,
      topic,
      callId,
      _image,
    );
    if (outcome.ok) _image = null;
    return outcome;
  }
}

final residentWakeServiceProvider = Provider<ResidentWakeService>(
  (ref) => ResidentWakeService(
    db: ref.watch(databaseProvider),
    residents: ref.watch(customResidentRepositoryProvider),
    inbox: ref.watch(residentInboxRepositoryProvider),
    gateway: ref.watch(modelGatewayProvider),
    session: ref.watch(residentToolSessionProvider),
    actions: ref.watch(actionRegistryProvider),
    posts: ref.watch(postRepositoryProvider),
    voices: ref.watch(postVoiceRepositoryProvider),
    interactions: ref.watch(interactionRepositoryProvider),
    notifications: ref.watch(notificationRepositoryProvider),
    profiles: ref.watch(userProfileRepositoryProvider),
    messages: ref.watch(privateMessageRepositoryProvider),
    media: ref.watch(mediaServiceProvider),
    commentReplies: ref.watch(commentReplyServiceProvider),
    wakeLogs: ref.watch(residentWakeLogRepositoryProvider),
    dmVoice: ref.watch(dmVoiceServiceProvider),
    activityDone: (residentId) =>
        ref.read(residentActivityProvider.notifier).clear(residentId),
  ),
);
