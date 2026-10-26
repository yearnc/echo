import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/custom_avatar_repository.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../data/repositories/post_understanding_repository.dart';
import '../../data/repositories/post_voice_repository.dart';
import '../models/echo_settings.dart';
import '../models/model_config.dart';
import '../models/planned_interaction.dart';
import '../models/post.dart';
import '../models/post_understanding.dart';
import '../models/post_voice.dart';
import 'community_settings_controller.dart';
import 'content_generator.dart';
import 'model_gateway.dart';
import 'post_analyzer.dart';
import 'post_voice_generator.dart';
import 'voice_name_generator.dart';

/// 发帖之后，给这一帖凑一桌人（v3.0）。
///
/// 第一批发帖时生成；之后由 `tick()` 按节奏再拉一两个新面孔进来，
/// 浏览量和评论区才会像真的有人陆续刷到。
/// 没有模型、生成失败就一个人都不来——不拿固定台词和固定人设硬凑。
class AudienceService {
  AudienceService({
    required this.posts,
    required this.voices,
    required this.interactions,
    required this.generator,
    required this.activeConfig,
    this.activeVisionConfig,
    this.analyzer,
    this.understandings,
    this.notifications,
    this.customAvatars,
    this.contentGenerator,
    this.readSendImagesDirectly,
    VoiceNameGenerator? nameGenerator,
    Random? random,
  }) : _random = random ?? Random(),
       _nameGenerator = nameGenerator ?? VoiceNameGenerator(random: random);

  final PostRepository posts;
  final PostVoiceRepository voices;
  final InteractionRepository interactions;
  final PostVoiceGenerator generator;
  final Future<ModelConfig?> Function() activeConfig;

  /// 额外的图片理解配置；没配就看文字。
  final Future<ModelConfig?> Function()? activeVisionConfig;

  /// 先看懂，再说话。可空：测试里不传就是不做解析。
  final PostAnalyzer? analyzer;
  final PostUnderstandingRepository? understandings;

  /// 连续失败时在通知页留一条提醒。可空：测试里不传就是不提醒。
  final NotificationRepository? notifications;

  /// 用户导入的网友头像池；有图就优先用它，空池回落到内置素材。
  final CustomAvatarRepository? customAvatars;

  /// 固定住民的评论走它；与临时网民的“起名字+动作”分开。
  final ContentGenerator? contentGenerator;


  /// 帖子图片是原图直发还是先总结（设置项）。
  final bool Function()? readSendImagesDirectly;

  /// 连续几次生成失败才提醒一次；同一提醒 6 小时只出现一次。
  static const int failureThreshold = 3;
  static const Duration failureNoticeCooldown = Duration(hours: 6);

  int _consecutiveFailures = 0;
  DateTime? _lastFailureNoticeAt;

  final Random _random;

  /// 网名由本地词库分配，不再用模型起的名。
  final VoiceNameGenerator _nameGenerator;

  /// 排期窗口与旧规划一致：0—48 小时摊开。
  static const Duration window = Duration(hours: 48);

  /// 一条帖子最多来多少人。到顶就不再拉人。
  static const int maxVoicesPerPost = 16;

  /// 一条帖子的首批人数：按频率档位缩。
  static int countFor(ReplyDensity density) => switch (density) {
    ReplyDensity.low => 4,
    ReplyDensity.medium => 7,
    ReplyDensity.high => 12,
    ReplyDensity.auto => 8,
  };

  /// 返回这次来了几个人。0 表示没生成出来。
  Future<int> prepare({
    required String postId,
    required ReplyDensity density,
    bool allowLurk = true,
  }) async {
    final post = await posts.findById(postId);
    if (post == null) return 0;

    final config = await activeConfig();
    if (config == null) return 0;

    final existing = await voices.byPost(postId);
    final understanding = await _understand(post, config);
    var added = 0;

    // 固定住民的帖子在 WorldService 里已经排过几个固定住民，
    // 但一个临时网民都还没有。所以判断“要不要首批”不能只看
    // existing 是否为空，要看**有没有临时网民**。
    final hasEphemeral = existing.any((voice) => voice.isEphemeral);
    if (!hasEphemeral) {
      // 先把 A+B+C 写进服务端缓存，再要第一批人（§4.3）。
      // 必须等它回来：并发发出去的话，第一批并不会命中这次"预热"。
      // 五秒封顶，失败就当这家不缓存前缀。
      await contentGenerator?.prewarm(
        post: post,
        understanding: understanding,
      );
      added += await _addBatch(
        post: post,
        config: config,
        count: countFor(density),
        existing: existing,
        allowLurk: allowLurk,
        understanding: understanding,
      );
    }

    return existing.length + added;
  }

  /// 解析一次、落库、所有批次共享；解析失败就返回 null，评论照常生成。
  Future<PostUnderstanding?> _understand(
    Post post,
    ModelConfig config,
  ) async {
    final repo = understandings;
    if (repo == null) return null;

    final existing = await repo.find(post.id);
    if (existing != null) return existing;

    final result = await analyzer?.analyze(
      config: config,
      // 原图直发模式下不再额外做一次图片摘要；普通文字解析照常。
      visionConfig: (readSendImagesDirectly?.call() ?? false)
          ? null
          : await activeVisionConfig?.call(),
      post: post,
    );
    if (result != null) await repo.upsert(result);
    return result;
  }

  /// 心跳调用：看看哪条帖子该来下一批人了。
  ///
  /// 节奏只做粗粒度：前 10 分钟每 30 秒、1 小时内每 5 分钟、
  /// 6 小时内每 25 分钟、之后每 2 小时，直到 48 小时或到人数上限。
  Future<int> tick() async {
    final config = await activeConfig();
    if (config == null) return 0;

    // 用户自己的帖子 + 固定住民的帖子都要继续来人。
    final recent = await posts.recentForAudience(limit: 12);
    final now = DateTime.now();
    var added = 0;

    for (final post in recent) {
      final age = now.difference(post.createdAt);
      if (age.isNegative || age > window) continue;

      final existing = await voices.byPost(post.id);
      if (existing.length >= maxVoicesPerPost) continue;

      final lastAt = existing.isEmpty ? post.createdAt : existing.last.createdAt;
      final interval = _batchInterval(age);
      if (now.difference(lastAt) < interval) continue;

      added += await _addBatch(
        post: post,
        config: config,
        count: 1,
        existing: existing,
        allowLurk: true,
        // 后续批次直接读第一次的解析结果，不重复调用模型
        understanding: await understandings?.find(post.id),
      );
    }

    return added;
  }

  /// 一个人一次请求：比一批更容易出不同的网名、状态和角度。
  ///
  /// system（规则 + 帖子快照）逐字节不变，预热之后每次都能吃同一段前缀；
  /// 当前时间、已出现名单、表情包目录全部放 user，不影响缓存。
  /// 并发压到 3，避免服务商限流；重名就带着更新后的名单再要一次。
  Future<List<PostVoiceDraft>> _draftOneByOne({
    required ModelConfig config,
    required Post post,
    required int count,
    required bool allowLurk,
    PostUnderstanding? understanding,
    required Set<String> takenNames,
    required DateTime at,
    required bool sendImagesDirectly,
  }) async {
    if (count <= 0) return const [];

    final results = <PostVoiceDraft>[];
    final reserved = {...takenNames};
    final queue = <int>[for (var i = 0; i < count; i++) i];
    final workerCount = count >= 3 ? 3 : 1;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        queue.removeLast();

        var drafts = await generator.draft(
          config: config,
          post: post,
          count: 1,
          allowLurk: allowLurk,
          understanding: understanding,
          at: at,
          avoidNames: reserved,
          sendImagesDirectly: sendImagesDirectly,
        );
        if (drafts.isEmpty) continue;
        var draft = drafts.first;

        // 并发请求互相看不见对方的名字，这里兜一次重名。
        if (!reserved.add(draft.name)) {
          drafts = await generator.draft(
            config: config,
            post: post,
            count: 1,
            allowLurk: allowLurk,
            understanding: understanding,
            at: at,
            avoidNames: reserved,
            sendImagesDirectly: sendImagesDirectly,
          );
          if (drafts.isEmpty || !reserved.add(drafts.first.name)) continue;
          draft = drafts.first;
        }
        results.add(draft);
      }
    }

    await Future.wait([
      for (var i = 0; i < workerCount; i++) worker(),
    ]);
    return results;
  }

  Duration _batchInterval(Duration age) {
    if (age < const Duration(minutes: 10)) return const Duration(seconds: 30);
    if (age < const Duration(hours: 1)) return const Duration(minutes: 5);
    if (age < const Duration(hours: 6)) return const Duration(minutes: 25);
    return const Duration(hours: 2);
  }

  Future<int> _addBatch({
    required Post post,
    required ModelConfig config,
    required int count,
    required List<PostVoice> existing,
    required bool allowLurk,
    PostUnderstanding? understanding,
  }) async {
    var insertedIds = <String>[];
    try {
      // 已来过的人名不重复：临时网民换了批次也不该撞名。
      // 再加上最近用过的名字和固定住民的出厂名单——模型很爱照抄示例，
      // 不拦一下，“老陈的键盘”会在每个人的帖子里反复出现。
      final takenNames = <String>{
        for (final voice in existing) voice.name,
        ...await voices.recentNames(),
      };

      final now = DateTime.now();
      final drafts = await _draftOneByOne(
        config: config,
        post: post,
        count: count,
        allowLurk: allowLurk,
        understanding: understanding,
        takenNames: takenNames,
        at: now,
        sendImagesDirectly: readSendImagesDirectly?.call() ?? false,
      );
      if (drafts.isEmpty) {
        await _recordFailure('模型没生成出网民');
        return 0;
      }

      // 不再按模型给的名字过滤：那个名字只是占位，最终用哪个由下面决定。
      final generated = drafts.toList(growable: false);
      if (generated.isEmpty) return 0;

      // 名字不用模型起的：模型起名会围着帖子内容打转，几批下来高度同质。
      // 本地词库负责“这个人叫什么”，模型只负责“他说什么”。
      final avoidNames = <String>{
        ...takenNames,
        for (final voice in existing) voice.name,
      };
      final fresh = <PostVoiceDraft>[];
      for (final draft in generated) {
        final name = _nameGenerator.next(avoid: avoidNames);
        avoidNames.add(name);
        fresh.add(
          PostVoiceDraft(
            name: name,
            status: draft.status,
            action: draft.action,
            comment: draft.comment,
            stickerId: draft.stickerId,
            stickerRef: draft.stickerRef,
          ),
        );
      }

      final built = <PostVoice>[];
      final usedPaths = <String>{};
      for (final voice in existing) {
        if (voice.avatarAsset.isNotEmpty) usedPaths.add(voice.avatarAsset);
      }

      // 用户导入的头像和内置素材**一起**参与挑选：只用自己的图会让
      // 一帖里翻来覆去就那几张，内置素材也不该因此“不能用”。
      final avatarPool = <String>[
        for (final avatar
            in await customAvatars?.all() ?? const <CustomAvatar>[])
          avatar.path,
        for (var index = 0; index < PostVoiceRepository.avatarCount; index++)
          'asset:assets/avatars/avatar_'
              '${(index + 1).toString().padLeft(3, '0')}.webp',
      ];

      for (var i = 0; i < fresh.length; i++) {
        final draft = fresh[i];
        final seed = (now.microsecondsSinceEpoch + i * 7919) % 100000;
        final avatar = _pickFromPool(avatarPool, seed, usedPaths);
        usedPaths.add(avatar);

        built.add(
          PostVoice(
            id: 'voice_${now.microsecondsSinceEpoch}_${existing.length + i}',
            postId: post.id,
            kind: PostVoiceKind.ephemeral,
            name: draft.name,
            avatarAsset: avatar,
            avatarSeed: seed,
            bio: draft.status,
            languageStyle: '口语，短句',
            tone: '随口说',
            createdAt: now,
          ),
        );
      }

      await voices.insertAll(built);
      insertedIds = [for (final voice in built) voice.id];

      final planned = <PlannedInteraction>[];
      // 逐人生成时“只读四分之一”的批次约束在单条请求里看不到，
      // 收到结果后再统一压一次。
      final maxLurk = allowLurk ? (built.length / 4).ceil() : 0;
      var lurkCount = 0;
      for (var i = 0; i < built.length; i++) {
        final draft = fresh[i];
        final voice = built[i];
        var action = draft.action;
        if (action == VoiceAction.view) {
          if (lurkCount >= maxLurk) {
            action = VoiceAction.like;
          } else {
            lurkCount++;
          }
        }

        // 浏览也排队：到点才写 post_views。否则帖子刚发出去，
        // 8 个人瞬间"同时看过"，数字一眼就是程序填的。
        final arrival = _arrivalAt(
          now: now,
          index: i,
          total: built.length,
          firstBatch: existing.isEmpty,
        );
        planned.add(
          PlannedInteraction(
            personaId: voice.id,
            type: 'view',
            scheduledAt: arrival,
          ),
        );

        if (action == VoiceAction.view) continue;

        final likeAt = arrival.add(
          Duration(seconds: 5 + _random.nextInt(31)),
        );
        if (action.wantsLike) {
          planned.add(
            PlannedInteraction(
              personaId: voice.id,
              type: 'like',
              scheduledAt: likeAt,
              likeBatch: 1,
            ),
          );
        }
        final sticker = draft.stickerRef;
        final hasComment = draft.comment.trim().isNotEmpty;
        if (action.wantsComment && (hasComment || sticker != null)) {
          planned.add(
            PlannedInteraction(
              personaId: voice.id,
              type: 'comment',
              scheduledAt: likeAt.add(
                Duration(seconds: 10 + _random.nextInt(61)),
              ),
              // 表情包是内容，输入框里的话是“顺便说一句”。
              // 以前 `sticker ?? comment` 会把文字整个吞掉。
              content: sticker ?? draft.comment.trim(),
              caption: sticker == null ? '' : draft.comment.trim(),
              mediaType: sticker == null ? 'text' : 'image',
            ),
          );
        }
      }

      if (planned.isNotEmpty) {
        planned.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
        await interactions.insertPlanned(post.id, planned);
      }

      _consecutiveFailures = 0;
      return built.length;
    } catch (error) {
      // 这一步失败不影响帖子本身：少一桌人，不是把发帖搞砸。
      // 但已经写进去的半个批次要清掉，否则下次会误以为已经来过人。
      debugPrint('[围观] 这次没凑上人：$error');
      await _recordFailure('$error');
      if (insertedIds.isNotEmpty) {
        try {
          await voices.deleteByIds(insertedIds);
        } catch (cleanupError) {
          debugPrint('[围观] 半批数据没清干净：$cleanupError');
        }
      }
      return 0;
    }
  }

  /// 连续失败到阈值，就在通知页留一条“检查模型配置”。
  /// 不弹窗、不打断；失败期间本来就没有互动，提醒也不该更吵。
  Future<void> _recordFailure(String reason) async {
    _consecutiveFailures++;
    debugPrint('[围观] 连续失败 $_consecutiveFailures 次：$reason');
    if (_consecutiveFailures < failureThreshold) return;

    final now = DateTime.now();
    final last = _lastFailureNoticeAt;
    if (last != null && now.difference(last) < failureNoticeCooldown) return;
    _lastFailureNoticeAt = now;

    try {
      await notifications?.insert(
        id: 'n_ai_failure_'
            '${now.millisecondsSinceEpoch ~/ failureNoticeCooldown.inMilliseconds}',
        type: 'system',
        title: 'AI 回复暂时不可用',
        body: '连续几次都没生成出来，检查一下模型配置',
        at: now,
      );
    } catch (error) {
      debugPrint('[围观] 失败提醒没写进去：$error');
    }
  }

  /// 从用户头像池里挑一张，尽量避开这一帖已经用过的。
  static String _pickFromPool(
    List<String> pool,
    int seed,
    Set<String> used,
  ) {
    final start = seed.abs() % pool.length;
    for (var step = 0; step < pool.length; step++) {
      final candidate = pool[(start + step) % pool.length];
      if (!used.contains(candidate)) return candidate;
    }
    return pool[start];
  }

  /// 这一批人陆续"刷到"的时间。
  ///
  /// 首批摊在前几分钟（第一个 15-30 秒，之后每隔二三十秒一个），
  /// 后续批次由心跳触发，几秒内到。浏览数因此是慢慢涨的，不是瞬移。
  DateTime _arrivalAt({
    required DateTime now,
    required int index,
    required int total,
    required bool firstBatch,
  }) {
    if (!firstBatch) {
      return now.add(Duration(seconds: 3 + _random.nextInt(13)));
    }
    if (index == 0) {
      return now.add(Duration(seconds: 15 + _random.nextInt(16)));
    }
    return now.add(
      Duration(seconds: 30 + index * 20 + _random.nextInt(21)),
    );
  }
}

final audienceServiceProvider = Provider<AudienceService>(
  (ref) => AudienceService(
    posts: ref.watch(postRepositoryProvider),
    voices: ref.watch(postVoiceRepositoryProvider),
    interactions: ref.watch(interactionRepositoryProvider),
    generator: ref.watch(modelPostVoiceGeneratorProvider),
    activeConfig: ref.watch(modelGatewayProvider).activeConfig,
    activeVisionConfig: () =>
        ref.watch(modelGatewayProvider).activeConfig(kind: ModelKind.vision),
    analyzer: ref.watch(postAnalyzerProvider),
    understandings: ref.watch(postUnderstandingRepositoryProvider),
    notifications: ref.watch(notificationRepositoryProvider),
    customAvatars: ref.watch(customAvatarRepositoryProvider),
    contentGenerator: ref.watch(contentSourceProvider),
    readSendImagesDirectly: () =>
        ref.read(communitySettingsProvider).sendPostImagesDirectly,
  ),
);
