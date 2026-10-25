import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/post_voice.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 每帖出现过的网民（v3.0）。
///
/// 只增不删：删帖也只把 `deleted_at` 置上，清醒模式的统计还要用。
class PostVoiceRepository {
  const PostVoiceRepository(this._db);

  final AppDatabase _db;

  /// 内置头像池的尺寸（`assets/avatars/avatar_001~110.webp`）。
  ///
  /// 前 32 张是 v3.0 的原始素材；033 之后是本地文生图扩的一批，
  /// 题材更杂（古风、赛博、动物、机器人），一个帖子里不容易“撞脸”。
  static const int avatarCount = 110;

  /// “我自己”的浏览记录用这个保留 id。它不在 post_voices 里，
  /// 所以 post_views.voice_id 不能有外键（v24 已重建）。
  static const String userViewerId = 'viewer_me';

  Future<void> insertAll(List<PostVoice> voices) async {
    if (voices.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAll(_db.postVoices, [
        for (final voice in voices)
          PostVoicesCompanion.insert(
            id: voice.id,
            postId: voice.postId,
            kind: Value(voice.kind.key),
            residentId: Value(voice.residentId),
            name: voice.name,
            avatarAsset: Value(voice.avatarAsset),
            avatarSeed: Value(voice.avatarSeed),
            bio: Value(voice.bio),
            languageStyle: Value(voice.languageStyle),
            tone: Value(voice.tone),
            model: Value(voice.model),
            memoryEnabled: Value(voice.memoryEnabled),
            memoryLimit: Value(voice.memoryLimit),
            alwaysShow: Value(voice.alwaysShow),
            createdAt: voice.createdAt.millisecondsSinceEpoch,
          ),
      ]);
    });
  }

  Stream<List<PostVoice>> watchByPost(String postId) {
    final query = _db.select(_db.postVoices)
      ..where((t) => t.postId.equals(postId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  Future<List<PostVoice>> byPost(String postId) async {
    final query = _db.select(_db.postVoices)
      ..where((t) => t.postId.equals(postId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    final rows = await query.get();
    return rows.map(_toDomain).toList(growable: false);
  }

  Future<PostVoice?> findById(String id) async {
    final row = await (_db.select(
      _db.postVoices,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  /// 最近用过的网名。
  ///
  /// 模型会反复用同一个名字（尤其是提示词里出现过的例子），
  /// 生成后拿它过滤一遍，跨帖子也不至于老看见同一张脸。
  Future<Set<String>> recentNames({int limit = 100}) async {
    final query = _db.select(_db.postVoices)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);
    final rows = await query.get();
    return {for (final row in rows) row.name};
  }

  /// 一批 id 一次查完，给评论区和调度器用（别逐条查）。
  Future<Map<String, PostVoice>> byIds(Iterable<String> ids) async {
    final unique = ids.toSet().toList(growable: false);
    if (unique.isEmpty) return const {};

    final query = _db.select(_db.postVoices)
      ..where((t) => t.id.isIn(unique));
    final rows = await query.get();
    return {for (final row in rows) row.id: _toDomain(row)};
  }

  Future<int> softDeleteByPost(String postId) {
    return (_db.update(
      _db.postVoices,
    )..where((t) => t.postId.equals(postId))).write(
      PostVoicesCompanion(
        deletedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 回滚一次没准备完的批次：只删指定的 voice 和它们的浏览记录。
  ///
  /// 生成到一半失败时用——不能把已经写进去的半个批次留在库里，
  /// 否则下次会以为"这条帖子已经有人来过了"。
  Future<void> deleteByIds(Iterable<String> ids) async {
    final list = ids.toList(growable: false);
    if (list.isEmpty) return;
    await (_db.delete(
      _db.postViews,
    )..where((t) => t.voiceId.isIn(list))).go();
    await (_db.delete(
      _db.postVoices,
    )..where((t) => t.id.isIn(list))).go();
  }

  /// 记一次浏览。同一账号在同一帖只留一行，重复来更新次数。
  Future<void> recordView({
    required String postId,
    required String voiceId,
    DateTime? at,
  }) async {
    final moment = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final existing =
        await (_db.select(_db.postViews)..where(
              (t) => t.postId.equals(postId) & t.voiceId.equals(voiceId),
            ))
            .getSingleOrNull();

    if (existing == null) {
      await _db
          .into(_db.postViews)
          .insert(
            PostViewsCompanion.insert(
              id: 'view_${postId}_$voiceId',
              postId: postId,
              voiceId: voiceId,
              firstViewedAt: moment,
              lastViewedAt: moment,
            ),
          );
      return;
    }

    await (_db.update(_db.postViews)..where((t) => t.id.equals(existing.id)))
        .write(
          PostViewsCompanion(
            lastViewedAt: Value(moment),
            viewCount: Value(existing.viewCount + 1),
          ),
        );
  }

  /// 我自己看了一眼。同一个帖子只留一行，重复进来加次数。
  Future<void> recordUserView(String postId, {DateTime? at}) {
    return recordView(
      postId: postId,
      voiceId: userViewerId,
      at: at,
    );
  }

  Stream<int> watchViewCount(String postId) {
    final count = _db.postViews.id.count();
    final query = _db.selectOnly(_db.postViews)
      ..addColumns([count])
      ..where(_db.postViews.postId.equals(postId));
    return query.watchSingle().map((row) => row.read(count) ?? 0);
  }

  Future<int> viewCount(String postId) async {
    final count = _db.postViews.id.count();
    final query = _db.selectOnly(_db.postViews)
      ..addColumns([count])
      ..where(_db.postViews.postId.equals(postId));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// 看过这条帖子的人，最近来的排前面。
  Future<List<PostViewer>> viewers(String postId) async {
    final rows =
        await (_db.select(_db.postViews)
              ..where((t) => t.postId.equals(postId))
              ..orderBy([(t) => OrderingTerm.desc(t.lastViewedAt)]))
            .get();
    if (rows.isEmpty) return const [];

    final voices = await byIds(rows.map((row) => row.voiceId));
    return [
      for (final row in rows)
        if (row.voiceId == userViewerId)
          PostViewer(
            voice: PostVoice(
              id: userViewerId,
              postId: postId,
              kind: PostVoiceKind.ephemeral,
              name: '我',
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                row.firstViewedAt,
              ),
            ),
            lastViewedAt: DateTime.fromMillisecondsSinceEpoch(row.lastViewedAt),
            viewCount: row.viewCount,
            isMe: true,
          )
        else if (voices[row.voiceId] != null)
          PostViewer(
            voice: voices[row.voiceId]!,
            lastViewedAt: DateTime.fromMillisecondsSinceEpoch(
              row.lastViewedAt,
            ),
            viewCount: row.viewCount,
          ),
    ];
  }

  /// 从内置池里挑一个没被同帖用过的头像。
  ///
  /// 池子见 [avatarCount]；人多了就从头再来，同帖内尽量不撞。
  static String avatarFor({required int seed, Set<int> used = const {}}) {
    var index = seed.abs() % avatarCount;
    for (var step = 0; step < avatarCount; step++) {
      final candidate = (index + step) % avatarCount;
      if (!used.contains(candidate)) {
        return 'asset:assets/avatars/avatar_${(candidate + 1).toString().padLeft(3, '0')}.webp';
      }
    }
    return 'asset:assets/avatars/avatar_${(index + 1).toString().padLeft(3, '0')}.webp';
  }

  PostVoice _toDomain(PostVoiceRow row) => PostVoice(
    id: row.id,
    postId: row.postId,
    kind: PostVoiceKind.fromKey(row.kind),
    residentId: row.residentId,
    name: row.name,
    avatarAsset: row.avatarAsset,
    avatarSeed: row.avatarSeed,
    bio: row.bio,
    languageStyle: row.languageStyle,
    tone: row.tone,
    model: row.model,
    memoryEnabled: row.memoryEnabled,
    memoryLimit: row.memoryLimit,
    alwaysShow: row.alwaysShow,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
  );
}

/// “看过这条帖子的人”列表里的一行。
class PostViewer {
  const PostViewer({
    required this.voice,
    required this.lastViewedAt,
    required this.viewCount,
    this.isMe = false,
  });

  final PostVoice voice;
  final DateTime lastViewedAt;
  final int viewCount;

  /// 这一行是"我自己"，界面用本机资料显示名字和头像。
  final bool isMe;
}

final postVoiceRepositoryProvider = Provider<PostVoiceRepository>(
  (ref) => PostVoiceRepository(ref.watch(databaseProvider)),
);

/// 一条帖子的网民名单：评论、通知、浏览记录都从这里取名字和头像。
final postVoicesProvider = StreamProvider.family<List<PostVoice>, String>(
  (ref, postId) => ref.watch(postVoiceRepositoryProvider).watchByPost(postId),
);

final postViewCountProvider = StreamProvider.family<int, String>(
  (ref, postId) => ref.watch(postVoiceRepositoryProvider).watchViewCount(postId),
);

