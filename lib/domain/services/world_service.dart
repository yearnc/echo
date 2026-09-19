import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../models/ai_persona.dart';
import '../models/app_mode.dart';
import '../models/resident_post.dart';
import 'content_generator.dart';
import 'interaction_planner.dart';

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
    required this.personas,
    required this.interactions,
    required this.generator,
    required this.sample,
    Random? random,
  }) : _random = random ?? Random();

  final AppDatabase db;
  final PostRepository posts;
  final PersonaRepository personas;
  final InteractionRepository interactions;
  final ContentGenerator generator;

  /// 住民动态底下的回应从这儿出（见 [_schedulePeers] 里为什么不走模型）。
  final SampleContentGenerator sample;

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

    final pool = await personas.loadAll();
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
    for (final moment in moments) {
      final draft = byPersona[moment.persona.id];
      if (draft == null) continue;
      final postId = await posts.createResidentPost(
        personaId: draft.personaId,
        content: draft.content,
        // 时间落在这条动态"该发生"的那一刻，不是现在——
        // 这样打开 APP 看到的是"过去几小时里发生的事"，而不是一屏"刚刚"
        createdAt: moment.at,
        topicName: draft.topicName,
      );
      await _schedulePeers(
        postId: postId,
        authorId: draft.personaId,
        pool: pool,
        at: moment.at,
      );
      written++;
    }

    await _saveLastTickAt(now);
    return written;
  }

  /// 给一条住民动态排几位邻居的回应。
  ///
  /// 刻意排得少（0—2 条）：社区里绝大多数帖子只有零星回应，每条都热闹反而假。
  /// 回应用的是预置台词、**不走模型**——住民动态本身已经是一次模型调用了，
  /// 评论是配角，不值得为它再花一次。
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
    final count = _random.nextInt(3);
    if (count == 0 || others.isEmpty) return;

    final planned = <PlannedInteraction>[];
    for (var i = 0; i < count && i < others.length; i++) {
      final persona = others[i];
      planned.add(
        PlannedInteraction(
          personaId: persona.id,
          type: 'comment',
          content: sample.forPersona(persona),
          // 一条动态发出去，十几分钟到几小时内陆续有人路过
          scheduledAt: at.add(Duration(minutes: 15 + _random.nextInt(240))),
        ),
      );
    }

    await interactions.insertPlanned(postId, planned);
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
    final picked = shuffled
        .take(count.clamp(1, pool.length))
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
    personas: ref.watch(personaRepositoryProvider),
    interactions: ref.watch(interactionRepositoryProvider),
    generator: ref.watch(contentSourceProvider),
    sample: ref.watch(sampleContentGeneratorProvider),
  ),
);
