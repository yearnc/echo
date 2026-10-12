import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/relationship_rules.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 住民与你的关系（B4）。表在 B1 就建好了，这里是第一次真去读写它。
///
/// 这一层只做一件事：**把规矩的结果写进库、再读回来**。亲近度怎么涨、
/// 档位怎么升全在 [[RelationshipRules]] 里（纯逻辑，单独测）。
class RelationshipRepository {
  const RelationshipRepository(this._db);

  final AppDatabase _db;

  /// 库里的全部关系。
  ///
  /// **没打过交道的人不在里面**——读不到那一行就是陌生。给 32 个住民各插一行
  /// 空记录换不来任何东西，还要在扩编、删除的时候一路跟着补。
  Future<Map<String, RelationshipState>> loadAll() async {
    final rows = await _db.select(_db.aiRelationships).get();
    return {for (final row in rows) row.personaId: _toState(row)};
  }

  /// 全部关系，跟着库变（关注 / 粉丝页要它）。
  Stream<Map<String, RelationshipState>> watchAll() {
    return _db
        .select(_db.aiRelationships)
        .watch()
        .map(
          (rows) => {for (final row in rows) row.personaId: _toState(row)},
        );
  }

  /// 这个人跟你的关系，跟着库变（住民主页要它才显示得出来）。
  Stream<RelationshipState> watch(String personaId) {
    return (_db.select(_db.aiRelationships)
          ..where((t) => t.personaId.equals(personaId)))
        .watchSingleOrNull()
        .map(
          (row) => row == null
              ? RelationshipState.stranger(personaId)
              : _toState(row),
        );
  }

  Future<RelationshipState> load(String personaId) async {
    final row =
        await (_db.select(_db.aiRelationships)
              ..where((t) => t.personaId.equals(personaId)))
            .getSingleOrNull();
    return row == null ? RelationshipState.stranger(personaId) : _toState(row);
  }

  /// 记一次互动，返回推进之后的状态。
  ///
  /// 读—算—写不是原子的，这里也不为它加事务：真能同时发生的只有"心跳兑现
  /// 一批互动"和"用户自己点了个赞"，撞上也就是少涨一分亲近度，
  /// 而代价是每次互动都要开一个事务。
  Future<RelationshipState> record({
    required String personaId,
    required RelationshipEvent event,
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final current = await load(personaId);
    final next = RelationshipRules.apply(
      current: current,
      event: event,
      at: now,
    );
    await _save(next, updatedAt: now);
    return next;
  }

  /// 关注 / 取关这个人（B5）。
  ///
  /// 他关注过你的话，你这一下就成了互关；已经关注了，再点就是取关。
  Future<RelationshipState> toggleFollow(String personaId) async {
    final current = await load(personaId);
    final next = switch (current.followState) {
      'following' => current.copyWith(followState: 'none'),
      'mutual' => current.copyWith(followState: 'followed'),
      'followed' => current.copyWith(followState: 'mutual'),
      _ => current.copyWith(followState: 'following'),
    };

    await _save(next, updatedAt: DateTime.now());
    return next;
  }

  /// 记忆的长度上限。
  ///
  /// 记忆是模型写的，它有可能啰嗦；而这句会被带进**每一次**评论请求，
  /// 所以在入库这一层就截断——不是不信任模型，是别让一条啰嗦的记忆
  /// 一直贵下去。
  static const int maxMemoryLength = 60;

  /// 更新「我记得你…」。
  ///
  /// 空摘要不动——那是"这次没生成出来"，不该把上一次记住的东西抹掉。
  Future<void> updateMemory({
    required String personaId,
    required String summary,
  }) async {
    final raw = summary.trim();
    if (raw.isEmpty) return;

    // 按码点切，不按 UTF-16 单元切：不然表情包、生僻字会被从中间劈开
    final runes = raw.runes.toList();
    final trimmed = runes.length <= maxMemoryLength
        ? raw
        : '${String.fromCharCodes(runes.take(maxMemoryLength))}…';

    final current = await load(personaId);
    if (current.memorySummary == trimmed) return;

    await _save(
      current.copyWith(memorySummary: trimmed),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _save(RelationshipState state, {required DateTime updatedAt}) {
    return _db
        .into(_db.aiRelationships)
        .insertOnConflictUpdate(
          AiRelationshipsCompanion.insert(
            personaId: state.personaId,
            relationshipLevel: Value(state.level),
            intimacy: Value(state.intimacy),
            interactionCount: Value(state.interactionCount),
            lastInteractionAt: Value(
              state.lastInteractionAt?.millisecondsSinceEpoch,
            ),
            memorySummary: Value(state.memorySummary),
            followState: Value(state.followState),
            updatedAt: updatedAt.millisecondsSinceEpoch,
          ),
        );
  }

  RelationshipState _toState(AiRelationshipRow row) => RelationshipState(
    personaId: row.personaId,
    level: row.relationshipLevel,
    intimacy: row.intimacy,
    interactionCount: row.interactionCount,
    lastInteractionAt: row.lastInteractionAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.lastInteractionAt!),
    followState: row.followState,
    memorySummary: row.memorySummary,
  );
}

final relationshipRepositoryProvider = Provider<RelationshipRepository>(
  (ref) => RelationshipRepository(ref.watch(databaseProvider)),
);

/// 某个住民和你的关系（B4）。住民主页读它。
final relationshipProvider = StreamProvider.family<RelationshipState, String>(
  (ref, personaId) =>
      ref.watch(relationshipRepositoryProvider).watch(personaId),
);

/// 全部关系（关注 / 粉丝页读它）。
final relationshipsProvider =
    StreamProvider<Map<String, RelationshipState>>(
      (ref) => ref.watch(relationshipRepositoryProvider).watchAll(),
    );

/// 我关注的人（含互关）。
final followingProvider = Provider<List<String>>((ref) {
  final all = ref.watch(relationshipsProvider).value ?? const {};
  return [
    for (final entry in all.entries)
      if (entry.value.followState == 'following' ||
          entry.value.followState == 'mutual')
        entry.key,
  ];
});

/// 关注我的人（含互关）。
final followersProvider = Provider<List<String>>((ref) {
  final all = ref.watch(relationshipsProvider).value ?? const {};
  return [
    for (final entry in all.entries)
      if (entry.value.followState == 'followed' ||
          entry.value.followState == 'mutual')
        entry.key,
  ];
});
