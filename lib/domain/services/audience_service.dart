import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../data/repositories/post_understanding_repository.dart';
import '../../data/repositories/post_voice_repository.dart';
import '../../data/repositories/resident_memory_repository.dart';
import '../models/echo_settings.dart';
import '../models/model_config.dart';
import '../models/post.dart';
import '../models/post_understanding.dart';
import '../models/post_voice.dart';
import 'content_generator.dart';
import 'interaction_planner.dart';
import 'model_gateway.dart';
import 'post_analyzer.dart';
import 'post_voice_generator.dart';
import 'relationship_rules.dart';
import 'resident_memory_service.dart';

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
    this.analyzer,
    this.understandings,
    this.fixedPersonas,
    this.notifications,
    this.customResidents,
    this.memories,
    this.contentGenerator,
    this.residentMemory,
    Random? random,
  }) : _random = random ?? Random();

  final PostRepository posts;
  final PostVoiceRepository voices;
  final InteractionRepository interactions;
  final PostVoiceGenerator generator;
  final Future<ModelConfig?> Function() activeConfig;

  /// 先看懂，再说话。可空：测试里不传就是不做解析。
  final PostAnalyzer? analyzer;
  final PostUnderstandingRepository? understandings;

  /// 固定住民的出厂名单：临时网民不取同名，免得把旧熟人又拉回来。
  final PersonaRepository? fixedPersonas;

  /// 连续失败时在通知页留一条提醒。可空：测试里不传就是不提醒。
  final NotificationRepository? notifications;

  /// 用户自己配置的固定住民（阶段三）。
  final CustomResidentRepository? customResidents;
  final ResidentMemoryRepository? memories;

  /// 固定住民的评论走它；与临时网民的“起名字+动作”分开。
  final ContentGenerator? contentGenerator;

  /// 固定住民“记住这条帖子”的入口。
  final ResidentMemoryService? residentMemory;

  /// 连续几次生成失败才提醒一次；同一提醒 6 小时只出现一次。
  static const int failureThreshold = 3;
  static const Duration failureNoticeCooldown = Duration(hours: 6);

  int _consecutiveFailures = 0;
  DateTime? _lastFailureNoticeAt;

  final Random _random;

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

    if (existing.isEmpty) {
      added += await _addBatch(
        post: post,
        config: config,
        count: countFor(density),
        existing: existing,
        allowLurk: allowLurk,
        understanding: understanding,
      );
    }

    // 固定住民每帖都来一次；已经有快照的跳过。
    added += await _addCustomResidents(
      post: post,
      config: config,
      understanding: understanding,
    );

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

    final result = await analyzer?.analyze(config: config, post: post);
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

    final mine = await posts.recentMine(limit: 10);
    final now = DateTime.now();
    var added = 0;

    for (final post in mine) {
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
      final drafts = await generator.draft(
        config: config,
        post: post,
        count: count,
        allowLurk: allowLurk,
        understanding: understanding,
      );
      if (drafts.isEmpty) {
        await _recordFailure('模型没生成出网民');
        return 0;
      }

      // 已来过的人名不重复：临时网民换了批次也不该撞名。
      // 再加上最近用过的名字和固定住民的出厂名单——模型很爱照抄示例，
      // 不拦一下，“老陈的键盘”会在每个人的帖子里反复出现。
      final takenNames = <String>{
        for (final voice in existing) voice.name,
        ...await voices.recentNames(),
      };
      try {
        final fixed = await fixedPersonas?.loadAll();
        if (fixed != null) {
          takenNames.addAll(fixed.map((persona) => persona.name));
        }
      } catch (error) {
        debugPrint('[围观] 这次没读到固定住民名单：$error');
      }

      final fresh = drafts
          .where((draft) => !takenNames.contains(draft.name))
          .toList(growable: false);
      if (fresh.isEmpty) return 0;

      final now = DateTime.now();
      final built = <PostVoice>[];
      final usedAvatars = <int>{};
      for (final voice in existing) {
        final index = _avatarIndexOf(voice.avatarAsset);
        if (index != null) usedAvatars.add(index);
      }

      for (var i = 0; i < fresh.length; i++) {
        final draft = fresh[i];
        final seed = (now.microsecondsSinceEpoch + i * 7919) % 100000;
        final avatar = PostVoiceRepository.avatarFor(
          seed: seed,
          used: usedAvatars,
        );
        final avatarIndex = _avatarIndexOf(avatar);
        if (avatarIndex != null) usedAvatars.add(avatarIndex);

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
      for (var i = 0; i < built.length; i++) {
        final draft = fresh[i];
        final voice = built[i];

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

        if (draft.action == VoiceAction.view) continue;

        final likeAt = arrival.add(
          Duration(seconds: 5 + _random.nextInt(31)),
        );
        if (draft.action.wantsLike) {
          planned.add(
            PlannedInteraction(
              personaId: voice.id,
              type: 'like',
              scheduledAt: likeAt,
              likeBatch: 1,
            ),
          );
        }
        if (draft.action.wantsComment && draft.comment.trim().isNotEmpty) {
          planned.add(
            PlannedInteraction(
              personaId: voice.id,
              type: 'comment',
              scheduledAt: likeAt.add(
                Duration(seconds: 10 + _random.nextInt(61)),
              ),
              content: draft.comment.trim(),
              mediaType: 'text',
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

  /// 固定住民每帖都来一次：留浏览 + 一条评论；写不出评论就点个赞。
  ///
  /// 快照的 id 带着帖子，但 `residentId` 指向同一个固定住民——
  /// 关系和记忆以后都认这个 id，不认每次发帖新造的 voice id。
  Future<int> _addCustomResidents({
    required Post post,
    required ModelConfig config,
    PostUnderstanding? understanding,
  }) async {
    final repo = customResidents;
    if (repo == null) return 0;

    final all = await repo.all();
    if (all.isEmpty) return 0;

    final existing = await voices.byPost(post.id);
    final seen = {
      for (final voice in existing)
        if (voice.residentId != null) voice.residentId!,
    };

    final now = DateTime.now();
    var added = 0;

    for (final resident in all.take(6)) {
      if (!resident.alwaysShow) continue;
      if (seen.contains(resident.id)) continue;

      try {
        final voice = PostVoice(
          id: 'voice_${resident.id}_${post.id}',
          postId: post.id,
          kind: PostVoiceKind.custom,
          residentId: resident.id,
          name: resident.name,
          avatarAsset: resident.avatarAsset,
          // 快照里把酒馆式字段拼成现有提示词认的三段：
          // bio=身份/背景/场景，languageStyle=说话方式/示例，
          // tone=语气/额外指令。老字段保持原样，不改接口。
          bio: [
            resident.bio,
            resident.description,
            resident.scenario,
          ].where((part) => part.trim().isNotEmpty).join('\n'),
          languageStyle: [
            resident.languageStyle,
            resident.exampleDialogue,
          ].where((part) => part.trim().isNotEmpty).join('\n'),
          tone: [
            resident.tone,
            resident.extraInstructions,
          ].where((part) => part.trim().isNotEmpty).join('；'),
          memoryEnabled: resident.memoryEnabled,
          memoryLimit: resident.memoryLimit,
          alwaysShow: resident.alwaysShow,
          createdAt: now,
        );
        await voices.insertAll([voice]);

        final arrival = now.add(
          Duration(seconds: 15 + _random.nextInt(31)),
        );
        final planned = <PlannedInteraction>[
          PlannedInteraction(
            personaId: voice.id,
            type: 'view',
            scheduledAt: arrival,
          ),
        ];

        var comment = '';
        final generator = contentGenerator;
        if (generator != null) {
          try {
            final memory = await _memorySummary(resident.id);
            final generated = await generator.comments(
              personas: [voice.toPersona()],
              post: post,
              relations: {
                voice.id: RelationshipState(
                  personaId: voice.id,
                  level: 1,
                  memorySummary: memory,
                ),
              },
            );
            comment = (generated[voice.id] ?? '').trim();
          } catch (error) {
            debugPrint('[固定住民] ${resident.name} 这次没写出评论：$error');
          }
        }

        if (comment.isEmpty) {
          planned.add(
            PlannedInteraction(
              personaId: voice.id,
              type: 'like',
              scheduledAt: arrival.add(
                Duration(seconds: 5 + _random.nextInt(21)),
              ),
            ),
          );
        } else {
          planned.add(
            PlannedInteraction(
              personaId: voice.id,
              type: 'comment',
              scheduledAt: arrival.add(
                Duration(seconds: 10 + _random.nextInt(41)),
              ),
              content: comment,
            ),
          );
        }

        await interactions.insertPlanned(post.id, planned);
        // 他来过之后，把这条帖子记进他的长期记忆。
        await residentMemory?.rememberPost(
          residentId: resident.id,
          post: post,
          understanding: understanding,
        );
        seen.add(resident.id);
        added++;
      } catch (error) {
        debugPrint('[固定住民] 这次没安排上 ${resident.name}：$error');
      }
    }

    return added;
  }

  Future<String> _memorySummary(String residentId) async {
    final repo = memories;
    if (repo == null) return '';
    final recent = await repo.recent(residentId, limit: 5);
    if (recent.isEmpty) return '';
    final text = recent.map((memory) => memory.toPromptLine()).join('；');
    return text.length > 300 ? '${text.substring(0, 300)}…' : text;
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

  static int? _avatarIndexOf(String asset) {
    if (asset.isEmpty) return null;
    final name = asset.split('avatar_').last.replaceAll('.webp', '');
    final index = int.tryParse(name);
    if (index == null) return null;
    return index - 1;
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
    analyzer: ref.watch(postAnalyzerProvider),
    understandings: ref.watch(postUnderstandingRepositoryProvider),
    fixedPersonas: ref.watch(personaRepositoryProvider),
    notifications: ref.watch(notificationRepositoryProvider),
    customResidents: ref.watch(customResidentRepositoryProvider),
    memories: ref.watch(residentMemoryRepositoryProvider),
    contentGenerator: ref.watch(contentSourceProvider),
    residentMemory: ref.watch(residentMemoryServiceProvider),
  ),
);
