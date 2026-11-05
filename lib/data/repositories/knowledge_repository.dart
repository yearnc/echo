import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/knowledge.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 知识库的读写。
///
/// 只在"归属"这一层做判断：独立库看 ownerKind，共享库看 targets。
/// 注入提示词时该取哪几条、要不要按帖子筛，是 [KnowledgeService] 的事。
class KnowledgeRepository {
  KnowledgeRepository(this._db);

  final AppDatabase _db;
  static final Random _rand = Random();

  static const String builtinTrendBaseId = 'kb_builtin_trends';

  // —— 知识库本体 ——

  Stream<List<KnowledgeBase>> watchBases({KnowledgeScope? scope}) {
    final query = _db.select(_db.knowledgeBases);
    if (scope != null) {
      query.where((t) => t.scope.equals(scope.key));
    }
    query.orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.watch().map(
      (rows) => rows.map(_toBase).toList(growable: false),
    );
  }

  Future<List<KnowledgeBase>> listBases({KnowledgeScope? scope}) async {
    final query = _db.select(_db.knowledgeBases);
    if (scope != null) {
      query.where((t) => t.scope.equals(scope.key));
    }
    query.orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    final rows = await query.get();
    return rows.map(_toBase).toList(growable: false);
  }

  Future<KnowledgeBase?> findBase(String id) async {
    final row = await (_db.select(_db.knowledgeBases)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toBase(row);
  }

  Future<String> createBase({
    required String name,
    required KnowledgeScope scope,
    KnowledgeOwnerKind ownerKind = KnowledgeOwnerKind.transient,
    String description = '',
    String ownerResidentId = '',
    bool builtin = false,
    bool autoUpdate = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'kb_${now}_${_rand.nextInt(1 << 20)}';
    await _db
        .into(_db.knowledgeBases)
        .insert(
          KnowledgeBasesCompanion.insert(
            id: id,
            name: _cleanName(name),
            scope: scope.key,
            ownerKind: Value(ownerKind.key),
            description: Value(description.trim()),
            ownerResidentId: Value(
              scope == KnowledgeScope.independent &&
                      ownerKind == KnowledgeOwnerKind.resident
                  ? ownerResidentId
                  : '',
            ),
            builtin: Value(builtin),
            autoUpdate: Value(autoUpdate),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> updateBase(KnowledgeBase base) async {
    await (_db.update(_db.knowledgeBases)
          ..where((t) => t.id.equals(base.id)))
        .write(
          KnowledgeBasesCompanion(
            name: Value(_cleanName(base.name)),
            description: Value(base.description.trim()),
            scope: Value(base.scope.key),
            ownerKind: Value(base.ownerKind.key),
            ownerResidentId: Value(
              base.scope == KnowledgeScope.independent &&
                      base.ownerKind == KnowledgeOwnerKind.resident
                  ? base.ownerResidentId
                  : '',
            ),
            enabled: Value(base.enabled),
            autoUpdate: Value(base.autoUpdate),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  /// 删除整本。内置库不允许删除（返回 false）。
  Future<bool> deleteBase(String id) async {
    final base = await findBase(id);
    if (base == null) return false;
    if (base.builtin) return false;
    await _db.transaction(() async {
      await (_db.delete(_db.knowledgeTargets)
            ..where((t) => t.baseId.equals(id)))
          .go();
      await (_db.delete(_db.knowledgeEntries)
            ..where((t) => t.baseId.equals(id)))
          .go();
      await (_db.delete(_db.knowledgeBases)..where((t) => t.id.equals(id)))
          .go();
    });
    return true;
  }

  /// 条目变了就动一下库的 updatedAt：注入方的缓存靠它失效。
  Future<void> touchBase(String baseId, {int? lastUpdatedAt}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.knowledgeBases)
          ..where((t) => t.id.equals(baseId)))
        .write(
          KnowledgeBasesCompanion(
            updatedAt: Value(now),
            lastUpdatedAt: lastUpdatedAt == null
                ? const Value<int>.absent()
                : Value(lastUpdatedAt),
          ),
        );
  }

  // —— 条目 ——

  Stream<List<KnowledgeEntry>> watchEntries(String baseId) {
    final query = _db.select(_db.knowledgeEntries)
      ..where((t) => t.baseId.equals(baseId))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.watch().map(
      (rows) => rows.map(_toEntry).toList(growable: false),
    );
  }

  Future<List<KnowledgeEntry>> listEntries(
    String baseId, {
    bool includeExpired = false,
  }) async {
    final query = _db.select(_db.knowledgeEntries)
      ..where((t) => t.baseId.equals(baseId))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    final rows = await query.get();
    final now = DateTime.now();
    return [
      for (final row in rows)
        if (includeExpired || !_toEntry(row).expiredAt(now)) _toEntry(row),
    ];
  }

  Future<KnowledgeEntry?> findEntry(String id) async {
    final row = await (_db.select(_db.knowledgeEntries)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toEntry(row);
  }

  Future<void> upsertEntry(KnowledgeEntry entry) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.knowledgeEntries)
        .insertOnConflictUpdate(
          KnowledgeEntriesCompanion.insert(
            id: entry.id.trim().isEmpty
                ? 'ke_${now}_${_rand.nextInt(1 << 20)}'
                : entry.id,
            baseId: entry.baseId,
            title: entry.title.trim(),
            summary: Value(entry.summary.trim()),
            content: Value(entry.content.trim()),
            examples: Value(jsonEncode(entry.examples)),
            tags: Value(jsonEncode(_cleanTags(entry.tags))),
            sourceUrl: Value(entry.sourceUrl.trim()),
            sourceTitle: Value(entry.sourceTitle.trim()),
            verifiedAt: Value(entry.verifiedAt),
            expiresAt: Value(entry.expiresAt),
            createdAt: entry.createdAt == 0 ? now : entry.createdAt,
            updatedAt: now,
          ),
        );
    await touchBase(entry.baseId);
  }

  Future<void> deleteEntry(String id) async {
    final entry = await findEntry(id);
    await (_db.delete(_db.knowledgeEntries)..where((t) => t.id.equals(id)))
        .go();
    if (entry != null) await touchBase(entry.baseId);
  }

  // —— 共享库的服务对象 ——

  Future<List<KnowledgeTarget>> listTargets(String baseId) async {
    final rows = await (_db.select(_db.knowledgeTargets)
          ..where((t) => t.baseId.equals(baseId)))
        .get();
    return rows.map(_toTarget).toList(growable: false);
  }

  Future<Map<String, List<KnowledgeTarget>>> allTargets() async {
    final rows = await _db.select(_db.knowledgeTargets).get();
    final map = <String, List<KnowledgeTarget>>{};
    for (final row in rows) {
      map.putIfAbsent(row.baseId, () => []).add(_toTarget(row));
    }
    return map;
  }

  /// 整体替换服务对象。空的"全体"不会被写成一行——
  /// 没配 target 的共享库等于没人看得到，这比写一行 `all` 更不容易误伤。
  Future<void> setTargets(
    String baseId,
    Iterable<KnowledgeTarget> targets,
  ) async {
    final unique = <KnowledgeTarget>{
      for (final target in targets)
        if (target.kind != KnowledgeTargetKind.resident ||
            target.targetId.trim().isNotEmpty)
          KnowledgeTarget(
            baseId: baseId,
            kind: target.kind,
            targetId: target.kind == KnowledgeTargetKind.resident
                ? target.targetId.trim()
                : '',
          ),
    };
    await _db.transaction(() async {
      await (_db.delete(_db.knowledgeTargets)
            ..where((t) => t.baseId.equals(baseId)))
          .go();
      for (final target in unique) {
        await _db
            .into(_db.knowledgeTargets)
            .insert(
              KnowledgeTargetsCompanion.insert(
                baseId: baseId,
                targetKind: target.kind.key,
                targetId: Value(target.targetId),
              ),
            );
      }
      await touchBase(baseId);
    });
  }

  // —— 可见性 ——

  /// 临时网民能读到的库：独立库里的 transient，加上共享库点名全体网民。
  Future<List<KnowledgeBase>> transientBases() async {
    final bases = await listBases();
    final targets = await allTargets();
    return [
      for (final base in bases)
        if (base.enabled && _servesTransient(base, targets[base.id]))
          base,
    ];
  }

  /// 某位固定住民能读到的库：自己的独立库 + 共享库点名全体/他本人。
  Future<List<KnowledgeBase>> residentBases(String residentId) async {
    final bases = await listBases();
    final targets = await allTargets();
    return [
      for (final base in bases)
        if (base.enabled && _servesResident(base, targets[base.id], residentId))
          base,
    ];
  }

  bool _servesTransient(
    KnowledgeBase base,
    List<KnowledgeTarget>? targets,
  ) {
    if (base.scope == KnowledgeScope.independent) {
      return base.ownerKind == KnowledgeOwnerKind.transient;
    }
    return targets?.any(
          (t) => t.kind == KnowledgeTargetKind.transientAll,
        ) ??
        false;
  }

  bool _servesResident(
    KnowledgeBase base,
    List<KnowledgeTarget>? targets,
    String residentId,
  ) {
    if (base.scope == KnowledgeScope.independent) {
      return base.ownerKind == KnowledgeOwnerKind.resident &&
          base.ownerResidentId == residentId;
    }
    if (targets == null) return false;
    return targets.any(
      (t) =>
          t.kind == KnowledgeTargetKind.residentAll ||
          (t.kind == KnowledgeTargetKind.resident &&
              t.targetId == residentId),
    );
  }

  // —— 自动更新的跨 isolate 节流 ——

  static const String _trendAttemptKey = 'knowledge.trend.attemptAt';

  /// 上一次尝试更新时间。WorkManager 和前台可能同时醒，
  /// 用库里的时间戳挡一下，免得两边一起跑、重复计费。
  Future<DateTime?> trendAttemptAt() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(_trendAttemptKey)))
        .getSingleOrNull();
    final ms = int.tryParse(row?.value ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markTrendAttempt(DateTime at) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _trendAttemptKey,
            value: '${at.millisecondsSinceEpoch}',
          ),
        );
  }

  // —— 内置热门梗库 ——

  /// 拿到（必要时创建）内置热门梗库。**不填任何条目**：
  /// 内容只由每周自动更新或主人手动添加。
  Future<KnowledgeBase> ensureTrendBase() async {
    final existing = await findBase(builtinTrendBaseId);
    if (existing != null) return existing;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.knowledgeBases)
        .insertOnConflictUpdate(
          KnowledgeBasesCompanion.insert(
            id: builtinTrendBaseId,
            name: '热门梗',
            scope: KnowledgeScope.shared.key,
            ownerKind: const Value('transient'),
            description: const Value(
              '最近流行的网络梗：来源、怎么用、例子。'
              '不确定含义就别硬套，跟不上的时候宁可提问。',
            ),
            builtin: const Value(true),
            autoUpdate: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await setTargets(builtinTrendBaseId, const [
      KnowledgeTarget(
        baseId: builtinTrendBaseId,
        kind: KnowledgeTargetKind.transientAll,
      ),
      KnowledgeTarget(
        baseId: builtinTrendBaseId,
        kind: KnowledgeTargetKind.residentAll,
      ),
    ]);
    return (await findBase(builtinTrendBaseId))!;
  }

  static String _cleanName(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? '未命名知识库' : trimmed;
  }

  static List<String> _cleanTags(List<String> tags) => [
    for (final tag in tags)
      if (tag.trim().isNotEmpty) tag.trim(),
  ];

  static KnowledgeBase _toBase(KnowledgeBaseRow row) => KnowledgeBase(
    id: row.id,
    name: row.name,
    description: row.description,
    scope: KnowledgeScope.fromKey(row.scope),
    ownerKind: KnowledgeOwnerKind.fromKey(row.ownerKind),
    ownerResidentId: row.ownerResidentId,
    builtin: row.builtin,
    enabled: row.enabled,
    autoUpdate: row.autoUpdate,
    lastUpdatedAt: row.lastUpdatedAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  static KnowledgeEntry _toEntry(KnowledgeEntryRow row) => KnowledgeEntry(
    id: row.id,
    baseId: row.baseId,
    title: row.title,
    summary: row.summary,
    content: row.content,
    examples: KnowledgeEntry.decodeList(row.examples),
    tags: KnowledgeEntry.decodeList(row.tags),
    sourceUrl: row.sourceUrl,
    sourceTitle: row.sourceTitle,
    verifiedAt: row.verifiedAt,
    expiresAt: row.expiresAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  static KnowledgeTarget _toTarget(KnowledgeTargetRow row) => KnowledgeTarget(
    baseId: row.baseId,
    kind: KnowledgeTargetKind.fromKey(row.targetKind),
    targetId: row.targetId,
  );
}

final knowledgeRepositoryProvider = Provider<KnowledgeRepository>(
  (ref) => KnowledgeRepository(ref.watch(databaseProvider)),
);
