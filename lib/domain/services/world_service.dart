import 'dart:math';

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../data/repositories/post_voice_repository.dart';
import '../models/ai_persona.dart';
import '../models/app_mode.dart';
import '../models/post_voice.dart';
import '../models/resident_post.dart';
import 'community_settings_controller.dart';
import 'content_generator.dart';
import 'interaction_planner.dart';
import 'resident_photo.dart';

/// 世界 tick：让社区在用户不在的时候也继续发生事情。
///
/// 它做的事很小——看一眼距上次生成过了多久，够久了就补几条住民动态，
/// 时间摊在过去那几个小时里。用户隔三天打开 APP，信息流里就有三天里
/// 社区发生过的事，而不是一片"刚刚"。
///
/// 它**不是**第二个调度器：排期与兑现仍然归 `SchedulerService`，
/// 这里只负责"社区该有新内容了"这一件事。
class WorldService {
  WorldService({
    required this.db,
    required this.posts,
    required this.people,
    required this.voices,
    required this.photo,
    required this.interactions,
    required this.generator,
    required this.sample,
    this.readAllowResidentPosts,
    Random? random,
  }) : _random = random ?? Random();

  final AppDatabase db;
  final PostRepository posts;

  /// 谁会自己发动态：只有用户配置的固定住民。
  ///
  /// 旧版本那批 32 位住民已经不再长内容了——开关写着「固定住民动态」，
  /// 长出来的却是旧住民，用户一眼就看出对不上。
  final CustomResidentRepository people;

  /// 每帖出现的人。动态底下也要有评论，评论者身份跟着快照走。
  final PostVoiceRepository voices;

  /// 住民自己发图文帖（B3.5）。
  final ResidentPhotoService photo;

  final InteractionRepository interactions;
  final ContentGenerator generator;

  /// 住民动态底下的回应从这儿出（见 [_schedulePeers] 里为什么先占位）。
  final SampleContentGenerator sample;

  /// 固定住民要不要自己发动态。默认 false，可空（测试里不传就是关）。
  final bool Function()? readAllowResidentPosts;

  final Random _random;

  /// 两条动态之间至少隔这么久。
  ///
  /// 社区安静一会儿才像社区；而且用户一开 APP 就看见十条新动态，
  /// 第一反应是"这是程序批量生成的"，不是"社区很热闹"。
  static const Duration minGap = Duration(hours: 2);

  /// 一条动态大约代表的时间跨度。三小时一条 ≈ 一天八条。
  static const Duration perPost = Duration(hours: 3);

  /// 一次 tick 最多补几条。隔了一周没开 APP，也不该一口气灌二十条进来。
  static const int maxPerTick = 4;

  static const String lastTickKey = 'world.lastTickAt';

  /// 检查并补齐。返回这次发了几条动态。
  Future<int> tick() async {
    // 开关关着就什么都不做（默认关）：v3.0 先把注意力放回"用户发帖后的反馈"，
    // 信息流不该自己一直长内容。
    if (!(readAllowResidentPosts?.call() ?? false)) return 0;

    // 清醒模式里不该长出新的虚拟动态——那不是"安静下来"，那是又冒出一批假的
    if (!await _isEchoMode()) return 0;

    final now = DateTime.now();
    final last = await _lastTickAt();

    if (last == null) {
      // 第一次：只记下时间，不生成。空信息流是新用户的真实起点（阶段 A 定的），
      // 一进门就冒出五条别人的动态会把这个起点冲掉。
      await _saveLastTickAt(now);
      return 0;
    }

    final elapsed = now.difference(last);
    if (elapsed < minGap) return 0;

    // 只有固定住民会自己起头。空着就什么都不发生——不拿旧住民补位。
    final pool = [
      for (final resident in await people.all()) resident.toPersona(),
    ];
    if (pool.isEmpty) return 0;

    final moments = planMoments(
      pool: pool,
      count: countFor(elapsed),
      from: last,
      to: now,
    );
    if (moments.isEmpty) return 0;

    final drafts = await generator.residentPosts(moments: moments);
    if (drafts.isEmpty) return 0;

    final byPersona = {for (final draft in drafts) draft.personaId: draft};
    var written = 0;
    final postIds = <String, String>{};
    for (final moment in moments) {
      final draft = byPersona[moment.persona.id];
      if (draft == null) continue;
      final postId = await posts.createResidentPost(
        // 作者是固定住民：不写 author_persona_id，旧住民那一列保持为空
        residentId: draft.personaId,
        content: draft.content,
        // 时间落在这条动态"该发生"的那一刻，不是现在——
        // 这样打开 APP 看到的是"过去几小时里发生的事"，而不是一屏"刚刚"
        createdAt: moment.at,
        topicName: draft.topicName,
      );
      postIds[draft.personaId] = postId;
      await _schedulePeers(
        postId: postId,
        authorId: draft.personaId,
        pool: pool,
        at: moment.at,
      );
      // 用预置台词先把排期占住（评论区不会空着），再让模型把内容换成
      // "真的看过这条动态"的话。不 await：写评论要几秒，而社区该动就动。
      unawaited(_upgradePeerComments(postId: postId));
      written++;
    }

    // 图文帖：**不等它**。出图要几十秒，而这条路在冷启动里跑着，
    // await 一下，用户开机就得先看几十秒空白。文字先发出去，图生成好了
    // 再挂到那条动态上；黄了就当这次是纯文字。
    unawaited(_attachPhoto(postIds: postIds, moments: moments, at: now));

    await _saveLastTickAt(now);
    return written;
  }

  /// 给这次的某条动态配一张图（B3.5）。跑在 tick 之外，谁也不等它。
  Future<void> _attachPhoto({
    required Map<String, String> postIds,
    required List<ResidentMoment> moments,
    required DateTime at,
  }) async {
    try {
      await photo.attach(postIds: postIds, moments: moments, at: at);
    } catch (error) {
      // 这里必须兜到底：它跑在后台，抛出去就成了没人接的异常，
      // 而它坏掉的后果仅仅是"这条动态没有配图"。
      debugPrint('[世界] 这次没能配上图：$error');
    }
  }

  /// 给一条住民动态排几位的回应。
  ///
  /// 先按 1—3 条排期、用预置台词占住位置（不这么做的话，模型慢几秒，
  /// 用户刷新时就只能看到一条空评论区）。内容随后由
  /// [_upgradePeerComments] 换成模型写的。
  ///
  /// 这些互动进了同一条队列（`ai_interactions`），所以兑现、补发、
  /// 切清醒模式时取消，全都跟用户帖子下面的那些一个待遇。
  Future<void> _schedulePeers({
    required String postId,
    required String authorId,
    required List<AiPersona> pool,
    required DateTime at,
  }) async {
    final others = pool.where((p) => p.id != authorId).toList()
      ..shuffle(_random);
    // 1—3 条：以前有 1/3 的概率一条都没有，一屏翻下去全是零评论，
    // 社区像刚上线，而不像有人在住。
    final count = 1 + _random.nextInt(3);
    if (others.isEmpty) return;

    final now = DateTime.now();
    final built = <PostVoice>[];
    final planned = <PlannedInteraction>[];
    for (var i = 0; i < count && i < others.length; i++) {
      final persona = others[i];
      final voice = PostVoice(
        // 同一个人在同一条动态下只有一个身份；重跑也不会造出第二张脸
        id: 'voice_${persona.id}_$postId',
        postId: postId,
        kind: PostVoiceKind.custom,
        residentId: persona.id,
        name: persona.name,
        avatarAsset: persona.avatar,
        bio: persona.bio,
        languageStyle: persona.languageStyle,
        tone: persona.tone,
        createdAt: now,
      );
      built.add(voice);
      planned.add(
        PlannedInteraction(
          personaId: voice.id,
          type: 'comment',
          content: sample.forPersona(persona),
          // 一条动态发出去，十几分钟到几小时内陆续有人路过
          scheduledAt: at.add(Duration(minutes: 15 + _random.nextInt(240))),
        ),
      );
    }

    await voices.insertAll(built);
    await interactions.insertPlanned(postId, planned);
  }

  /// 把住民动态底下还没到点的评论，换成模型读着这条动态写的话。
  ///
  /// 这是"评论和帖子无关"的根：以前这里直接用 `sample.forPersona()`，
  /// 那是住民随身的一句台词，跟帖子内容没有任何关系。于是就会出现
  /// "在吧台做咖啡"底下有人聊"河边坐了半小时"——而且楼主接着那句
  /// 聊得还挺像回事（楼中楼走了模型），对比之下特别刺眼。
  ///
  /// 排期早就落库了，所以这一步失败也无所谓：预置台词还在，社区照常运转，
  /// 只是这条评论又变成"随口一句"。
  Future<void> _upgradePeerComments({required String postId}) async {
    try {
      final personaIds = await interactions.pendingCommentPersonaIds(postId);
      if (personaIds.isEmpty) return;

      // 评论者的身份是这一帖的 post_voices 快照——直接从库里读，
      // 不再从旧住民池里对号入座。
      final snapshots = await voices.byPost(postId);
      final byId = {
        for (final voice in snapshots) voice.id: voice.toPersona(),
      };
      final targets = personaIds
          .map((id) => byId[id])
          .whereType<AiPersona>()
          .toList(growable: false);
      if (targets.isEmpty) return;

      final post = await posts.findById(postId);
      if (post == null) return;

      final generated = await generator.comments(personas: targets, post: post);
      if (generated.isEmpty) return;
      await interactions.updatePendingComments(postId, generated);
    } catch (error) {
      debugPrint('[世界] 住民动态的评论没能换成模型写的：$error');
    }
  }

  /// 这次该补几条。纯逻辑。
  static int countFor(Duration elapsed) =>
      (elapsed.inMinutes / perPost.inMinutes).floor().clamp(1, maxPerTick);

  /// 挑人、排时间。纯逻辑，单独测——
  /// "谁在什么时候发"这件事不该只能靠干等两小时来验证。
  ///
  /// 返回的列表按时间升序，落库顺序与信息流顺序一致。
  List<ResidentMoment> planMoments({
    required List<AiPersona> pool,
    required int count,
    required DateTime from,
    required DateTime to,
  }) {
    final span = to.difference(from);
    if (pool.isEmpty || count <= 0 || span <= Duration.zero) return const [];

    final shuffled = List<AiPersona>.of(pool)..shuffle(_random);

    // 这个点本来就活跃的人先上：凌晨三点发"又要起床上班"的住民，
    // 一眼就是排期器写的。分两组再拼起来，组内保持刚打乱的顺序——
    // 于是"谁先谁后"仍然是随机的，只是活跃的人排在前面。
    final active = <AiPersona>[];
    final quiet = <AiPersona>[];
    for (final persona in shuffled) {
      (persona.isActiveAt(from) ? active : quiet).add(persona);
    }
    final ordered = [...active, ...quiet];

    final picked = ordered
        .take(count.clamp(1, ordered.length))
        .toList(growable: false);

    final moments = <ResidentMoment>[];
    for (var i = 0; i < picked.length; i++) {
      // 把 [from, to] 切成等份，每份里随机取一点：既有先后，
      // 又不会全挤在同一分钟里
      final slotStart = from.add(span * (i / picked.length));
      final slotEnd = from.add(span * ((i + 1) / picked.length));
      final slotMs = slotEnd.difference(slotStart).inMilliseconds;
      moments.add(
        ResidentMoment(
          persona: picked[i],
          at: slotStart.add(
            Duration(milliseconds: slotMs <= 0 ? 0 : _random.nextInt(slotMs)),
          ),
        ),
      );
    }

    moments.sort((a, b) => a.at.compareTo(b.at));
    return moments;
  }

  Future<DateTime?> _lastTickAt() async {
    final query = db.select(db.appSettings)
      ..where((t) => t.key.equals(lastTickKey));
    final row = await query.getSingleOrNull();
    final raw = int.tryParse(row?.value ?? '');
    return raw == null ? null : DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> _saveLastTickAt(DateTime at) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: lastTickKey,
            value: '${at.millisecondsSinceEpoch}',
            scope: const Value('echo'),
          ),
        );
  }

  Future<bool> _isEchoMode() async {
    final query = db.select(db.appSettings)
      ..where((t) => t.key.equals('app.mode'));
    final row = await query.getSingleOrNull();
    return row?.value != AppMode.clear.scope;
  }
}

final worldServiceProvider = Provider<WorldService>(
  (ref) => WorldService(
    db: ref.watch(databaseProvider),
    posts: ref.watch(postRepositoryProvider),
    people: ref.watch(customResidentRepositoryProvider),
    voices: ref.watch(postVoiceRepositoryProvider),
    photo: ref.watch(residentPhotoServiceProvider),
    interactions: ref.watch(interactionRepositoryProvider),
    generator: ref.watch(contentSourceProvider),
    sample: ref.watch(sampleContentGeneratorProvider),
    readAllowResidentPosts: () =>
        ref.read(communitySettingsProvider).allowResidentPosts,
  ),
);
