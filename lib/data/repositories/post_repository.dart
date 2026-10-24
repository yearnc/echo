import 'dart:convert';
import 'dart:math';

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
  Stream<List<Post>> watchFeed({String? scope, int? limit}) {
    final query = _db.select(_db.posts)
      // 旧版本那 32 位住民的动态不再出现在信息流里（v3.0 之后不再长内容），
      // 数据仍然保留，只是这个"模拟社区"的入口不再摆出来。
      ..where((t) => t.deletedAt.isNull() & t.authorPersonaId.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);

    if (scope != null) {
      query.where((t) => t.scope.equals(scope));
    }
    if (limit != null) query.limit(limit);

    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// 一批帖子各自是谁发的（只返回住民发的那些）。
  ///
  /// 调度器兑现互动时要靠它分出"这是你的帖子"和"这是别人的帖子"——
  /// 别人的帖子下面来人了，没有理由通知你。
  Future<Map<String, String>> residentAuthorsOf(Set<String> postIds) async {
    if (postIds.isEmpty) return const {};

    final query = _db.select(_db.posts)..where(
      (t) =>
          t.id.isIn(postIds) &
          (t.authorPersonaId.isNotNull() | t.authorResidentId.isNotNull()),
    );

    final rows = await query.get();
    // 固定住民动态和旧住民动态都算"别人的帖子"：在别人帖子下面来人了，
    // 没有理由通知用户。作者 id 具体是谁这里不关心，只用来区分归属。
    return {
      for (final row in rows)
        row.id: row.authorResidentId ?? row.authorPersonaId!,
    };
  }

  /// 某个住民自己发的动态（住民主页用）。
  Stream<List<Post>> watchByAuthor(String personaId) {
    final query = _db.select(_db.posts)
      ..where(
        (t) => t.authorPersonaId.equals(personaId) & t.deletedAt.isNull(),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);

    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// 某个固定住民自己发的动态。
  Stream<List<Post>> watchByResident(String residentId) {
    final query = _db.select(_db.posts)
      ..where(
        (t) =>
            t.authorResidentId.equals(residentId) & t.deletedAt.isNull(),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);

    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// 你最近发过的几条（B4：住民靠它记住你）。
  ///
  /// 两重限定，缺一不可：
  /// - 只要**你自己**发的——住民那些动态是他们自己的事，
  ///   拿来当"对你的记忆"是两回事；
  /// - 只要 [scope] 里的（默认 echo）——**清醒模式的记录是只写给自己看的**，
  ///   把它们送进模型、再显示在住民主页上，是这个项目最不能碰的那条线。
  ///   默认值就是这件事最不容易出错的地方：忘了传，也不会泄漏。
  Future<List<Post>> recentMine({int limit = 5, String scope = 'echo'}) async {
    final query = _db.select(_db.posts)
      ..where(
        (t) =>
            t.authorPersonaId.isNull() &
            t.authorResidentId.isNull() &
            t.deletedAt.isNull() &
            t.scope.equals(scope),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);

    final rows = await query.get();
    return rows.map(_toDomain).toList(growable: false);
  }

  /// 最近需要“凑人”的帖子：用户自己发的 + 固定住民发的。
  ///
  /// v3.0 的临时网民只围着用户的帖子转，固定住民的帖子底下永远只有
  /// 另外几个固定住民。这里把两种帖子一起交给 AudienceService。
  Future<List<Post>> recentForAudience({
    int limit = 10,
    Duration window = const Duration(hours: 48),
  }) async {
    final cutoff = DateTime.now().subtract(window).millisecondsSinceEpoch;
    final query = _db.select(_db.posts)
      ..where(
        (t) =>
            t.authorPersonaId.isNull() &
            t.deletedAt.isNull() &
            t.scope.equals('echo') &
            t.createdAt.isBiggerOrEqualValue(cutoff),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);
    final rows = await query.get();
    return rows.map(_toDomain).toList(growable: false);
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

  /// 住民自己发的动态（B3）。
  ///
  /// 跟用户发帖分开走，有两个原因：它不该带发布页那套参数（回复密度、
  /// 拟人程度是用户给自己帖子调的旋钮）；而且它的时间**可以是过去**——
  /// 世界 tick 要补上"用户没开 APP 的那几个小时里社区发生了什么"。
  Future<String> createResidentPost({
    String? personaId,
    String? residentId,
    required String content,
    DateTime? createdAt,
    String? topicName,
  }) async {
    final id = _newId();
    final at = (createdAt ?? DateTime.now()).millisecondsSinceEpoch;

    await _db
        .into(_db.posts)
        .insert(
          PostsCompanion.insert(
            id: id,
            content: Value(content),
            createdAt: at,
            // 住民动态按 echo 作用域走：切到清醒模式时它跟虚拟反馈一起归档
            scope: const Value('echo'),
            topicName: Value(topicName),
            isAiGenerated: const Value(true),
            authorPersonaId: Value(personaId),
            authorResidentId: Value(residentId),
            // 住民的动态下面也会有人来评论，那就是这个社区自己的呼吸
            allowAiReply: const Value(true),
          ),
        );
    return id;
  }

  /// 事后给一条帖子配上图（住民图文帖）。
  ///
  /// 图是**后补**的，不跟着发帖一起等：出图要几十秒，而发帖那条路在
  /// 冷启动里跑着，用它去等一张图，用户开机就得先看几十秒空白。
  /// 所以顺序反过来——文字先发出去，图生成好了再挂上来；
  /// 生成失败就停在纯文字，那条动态本身照样成立。
  ///
  /// 返回受影响的行数。帖子不在了（0 行）调用方得知道——那时候图已经生成、
  /// 也已经落盘了，不声不响地丢掉会留下一个谁也不引用的文件。
  Future<int> attachImages(String postId, List<String> images) {
    return (_db.update(_db.posts)..where((t) => t.id.equals(postId))).write(
      PostsCompanion(images: Value(jsonEncode(images))),
    );
  }

  /// 点赞 / 取消点赞。返回点完之后"我赞了没有"。
  ///
  /// 自己发的帖子也能点：这颗心本来就是给自己看的一个标记，
  /// 不是"给别人的互动"。住民也不知道它——它只属于这台设备。
  Future<bool> toggleLike(String postId) async {
    final query = _db.select(_db.posts)..where((t) => t.id.equals(postId));
    final row = await query.getSingleOrNull();
    if (row == null) return false;

    final liked = row.likedAt == null;
    await (_db.update(_db.posts)..where((t) => t.id.equals(postId))).write(
      PostsCompanion(
        likedAt: liked
            ? Value(DateTime.now().millisecondsSinceEpoch)
            : const Value<int?>(null),
        likeCount: Value(
          liked ? row.likeCount + 1 : max(0, row.likeCount - 1),
        ),
      ),
    );
    return liked;
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
  ///
  /// 两个数字都只算**用户自己发的帖子**（`authorPersonaId` 为空）：
  /// 住民的动态躺在同一张表里，那是"社区里别人发的"，
  /// 不加这一条，个人主页上就变成了"我发了三百条、获赞两千"。
  Stream<ProfileStats> watchStats() {
    final count = _db.posts.id.count();
    final likes = _db.posts.likeCount.sum();
    final mine = _db.posts.deletedAt.isNull() &
        _db.posts.authorPersonaId.isNull() &
        _db.posts.authorResidentId.isNull();
    final query = _db.selectOnly(_db.posts)
      ..addColumns([count, likes])
      ..where(mine);

    return query.watchSingle().map(
      (row) => ProfileStats(
        postCount: row.read(count) ?? 0,
        likeCount: row.read(likes) ?? 0,
      ),
    );
  }

  /// 软删除：保留 `deletedAt` 供日后恢复与审计。
  ///
  /// 删除一条帖子会牵扯到四张表：还在路上的互动、通知、策划事件、
  /// 以及条帖子自己的评论。只写 posts.deleted_at 的话，用户会看到
  /// “帖没了，但通知还在点得进去、两分钟后还有人给空气点赞”。
  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await (_db.update(_db.posts)..where((t) => t.id.equals(id))).write(
        PostsCompanion(deletedAt: Value(now)),
      );
      await (_db.update(_db.aiInteractions)
            ..where((t) => t.postId.equals(id) & t.status.equals('pending')))
          .write(const AiInteractionsCompanion(status: Value('cancelled')));
      await (_db.delete(
        _db.planEvents,
      )..where((t) => t.postId.equals(id))).go();
      await (_db.delete(
        _db.notificationLogs,
      )..where((t) => t.postId.equals(id))).go();
      await (_db.update(_db.userComments)
            ..where((t) => t.postId.equals(id) & t.deletedAt.isNull()))
          .write(UserCommentsCompanion(deletedAt: Value(now)));
    });
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
      authorPersonaId: row.authorPersonaId,
      authorResidentId: row.authorResidentId,
      likedByMe: row.likedAt != null,
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

  /// 时间戳 + 随机后缀。
  ///
  /// 后缀必须**真的**随机：`DateTime.now()` 的实际精度常常只有毫秒
  /// （Windows 上尤其），同一毫秒里连着插两条会拿到同一个时间戳。
  /// 这原本用的是"拿时间戳当随机数"的写法——发帖一次只插一条，撞不上；
  /// 直到世界 tick 开始一次连写好几条住民动态，它立刻撞了主键。
  static final Random _rand = Random();
}

final postRepositoryProvider = Provider<PostRepository>(
  (ref) => PostRepository(ref.watch(databaseProvider)),
);

/// 信息流（回响模式）。scope 为 null 表示不过滤。
final feedPostsProvider = StreamProvider.autoDispose
    .family<List<Post>, String?>((ref, scope) {
      return ref.watch(postRepositoryProvider).watchFeed(scope: scope);
    });

/// 首页首屏只取最近 10 条，底部的“加载更多”把它加 10。
class FeedLimitController extends Notifier<int> {
  @override
  int build() => 10;

  void more() => state += 10;
}

final feedLimitProvider = NotifierProvider<FeedLimitController, int>(
  FeedLimitController.new,
);

final feedPagePostsProvider = StreamProvider.autoDispose
    .family<List<Post>, int>((ref, limit) {
      return ref.watch(postRepositoryProvider).watchFeed(
        scope: 'echo',
        limit: limit,
      );
    });

final postByIdProvider = StreamProvider.autoDispose.family<Post?, String>(
  (ref, id) => ref.watch(postRepositoryProvider).watchById(id),
);

/// 某个住民发过的动态（住民主页用）。
final residentPostsProvider = StreamProvider.autoDispose
    .family<List<Post>, String>(
      (ref, personaId) =>
          ref.watch(postRepositoryProvider).watchByAuthor(personaId),
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
