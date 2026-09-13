import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/post.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 帖子的读写（Drift 支撑）。
///
/// 领域模型与数据库行在这里完成转换——UI 只认 [Post]，
/// 所以将来换存储（加同步、加加密）不用动页面。
class PostRepository {
  const PostRepository(this._db);

  final AppDatabase _db;

  /// 信息流：按时间倒序，自动跟随数据库变化。
  Stream<List<Post>> watchFeed({String? scope}) {
    final query = _db.select(_db.posts)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);

    if (scope != null) {
      query.where((t) => t.scope.equals(scope));
    }

    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  Stream<Post?> watchById(String id) {
    final query = _db.select(_db.posts)
      ..where((t) => t.id.equals(id) & t.deletedAt.isNull());

    return query.watchSingleOrNull().map(
      (row) => row == null ? null : _toDomain(row),
    );
  }

  Future<Post?> findById(String id) async {
    final query = _db.select(_db.posts)
      ..where((t) => t.id.equals(id) & t.deletedAt.isNull());
    final row = await query.getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Future<String> create({
    required String content,
    List<String> images = const [],
    String? topicName,
    String scope = 'shared',
    bool allowAiReply = true,
    String? replyDensity,
    String? likeLevel,
    int? humanLevel,
  }) async {
    final id = _newId();
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db
        .into(_db.posts)
        .insert(
          PostsCompanion.insert(
            id: id,
            content: Value(content),
            images: Value(jsonEncode(images)),
            createdAt: now,
            scope: Value(scope),
            topicName: Value(topicName),
            allowAiReply: Value(allowAiReply),
            replyDensity: Value(replyDensity),
            likeLevel: Value(likeLevel),
            humanLevel: Value(humanLevel),
          ),
        );
    return id;
  }

  /// 互动兑现时回写计数（调度器用）。
  ///
  /// 顺带处理"热榜"：点赞过百就标热——热度本来就是外部评价的产物，
  /// 它在回响模式里出现、在清醒模式里被隐藏，这个反差正是产品要说的。
  Future<void> addCounters(String id, {int likes = 0, int comments = 0}) async {
    if (likes == 0 && comments == 0) return;

    final query = _db.select(_db.posts)..where((t) => t.id.equals(id));
    final row = await query.getSingleOrNull();
    if (row == null) return;

    final nextLikes = row.likeCount + likes;
    await (_db.update(_db.posts)..where((t) => t.id.equals(id))).write(
      PostsCompanion(
        likeCount: Value(nextLikes),
        commentCount: Value(row.commentCount + comments),
        isHot: Value(row.isHot || nextLikes >= 100),
      ),
    );
  }

  /// 直接设定计数（策划脚本里的"设定数据"事件）。
  ///
  /// 与 [addCounters] 的区别是它不做加法：脚本说"此刻 203 赞"，就是 203，
  /// 这样三幕那种"帖子已经火了"的开局才能被准确复现。
  Future<void> setCounters(String id, {int? likes, int? comments}) async {
    if (likes == null && comments == null) return;

    final query = _db.select(_db.posts)..where((t) => t.id.equals(id));
    final row = await query.getSingleOrNull();
    if (row == null) return;

    final nextLikes = likes ?? row.likeCount;
    await (_db.update(_db.posts)..where((t) => t.id.equals(id))).write(
      PostsCompanion(
        likeCount: Value(nextLikes),
        commentCount: comments == null ? const Value.absent() : Value(comments),
        isHot: Value(row.isHot || nextLikes >= 100),
      ),
    );
  }

  /// 「我的」页的统计。真实查出来的，不是写死的数字。
  Stream<ProfileStats> watchStats() {
    final count = _db.posts.id.count();
    final likes = _db.posts.likeCount.sum();
    final query = _db.selectOnly(_db.posts)
      ..addColumns([count, likes])
      ..where(_db.posts.deletedAt.isNull());

    return query.watchSingle().map(
      (row) => ProfileStats(
        postCount: row.read(count) ?? 0,
        likeCount: row.read(likes) ?? 0,
      ),
    );
  }

  /// 软删除：保留 `deletedAt` 供日后恢复与审计。
  Future<void> softDelete(String id) async {
    await (_db.update(_db.posts)..where((t) => t.id.equals(id))).write(
      PostsCompanion(deletedAt: Value(DateTime.now().millisecondsSinceEpoch)),
    );
  }

  /// 计数由互动执行时回写（M3），这里只做展示层需要的映射。
  Post _toDomain(PostRow row) {
    return Post(
      id: row.id,
      content: row.content,
      images: _decodeImages(row.images),
      topicName: row.topicName,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      likeCount: row.likeCount,
      commentCount: row.commentCount,
      isAiGenerated: row.isAiGenerated,
      scope: row.scope,
      allowAiReply: row.allowAiReply,
      isHot: row.isHot,
    );
  }

  List<String> _decodeImages(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } on FormatException {
      // 数据损坏时退化为无图，不因为一张图让整条信息流崩掉
      return const [];
    }
    return const [];
  }

  String _newId() =>
      'post_${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 20)}';

  static final _rand = _SimpleRandom();
}

/// 极简随机：只用来拼 id 后缀，避免为了这点需求引入额外依赖。
class _SimpleRandom {
  int nextInt(int max) =>
      DateTime.now().microsecondsSinceEpoch.remainder(max).abs();
}

final postRepositoryProvider = Provider<PostRepository>(
  (ref) => PostRepository(ref.watch(databaseProvider)),
);

/// 信息流（回响模式）。scope 为 null 表示不过滤。
final feedPostsProvider = StreamProvider.autoDispose
    .family<List<Post>, String?>((ref, scope) {
      return ref.watch(postRepositoryProvider).watchFeed(scope: scope);
    });

final postByIdProvider = StreamProvider.autoDispose.family<Post?, String>(
  (ref, id) => ref.watch(postRepositoryProvider).watchById(id),
);

/// 「我的」页的统计。
final profileStatsProvider = StreamProvider.autoDispose<ProfileStats>(
  (ref) => ref.watch(postRepositoryProvider).watchStats(),
);

/// 个人主页的汇总数字。
class ProfileStats {
  const ProfileStats({required this.postCount, required this.likeCount});

  final int postCount;
  final int likeCount;
}
