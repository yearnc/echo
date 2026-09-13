import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/plan_script.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 策划脚本的读写。
///
/// 脚本在库里是"一行 + 一段 JSON"：名字、开局内容这种要排序/展示的字段
/// 拆成列，事件表整体放 JSON。事件的形状会随剧本变（今天五种类型，
/// 明天可能多一种），拆成关系表只会让每次改剧本都要动 schema。
class PlanScriptRepository {
  const PlanScriptRepository(this._db);

  final AppDatabase _db;

  /// 脚本列表：内置的排前面，其余按更新时间倒序（刚改过的在最上面）。
  Stream<List<PlanScript>> watchAll() {
    final query = _db.select(_db.planScripts)
      ..orderBy([
        (t) => OrderingTerm.desc(t.isBuiltIn),
        (t) => OrderingTerm.desc(t.updatedAt),
      ]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  Future<PlanScript?> findById(String id) async {
    final query = _db.select(_db.planScripts)..where((t) => t.id.equals(id));
    final row = await query.getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  /// 新建或覆盖保存。`createdAt` 为 0 表示新建。
  Future<void> save(PlanScript script) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.planScripts)
        .insertOnConflictUpdate(
          PlanScriptsCompanion.insert(
            id: script.id,
            name: script.name,
            createdAt: script.createdAt == 0 ? now : script.createdAt,
            updatedAt: now,
            isBuiltIn: Value(script.isBuiltIn),
            postContent: Value(script.postContent),
            postImages: Value(jsonEncode(script.postImages)),
            topicName: Value(script.topicName),
            stepsJson: Value(_encodeSteps(script.steps)),
          ),
        );
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.planScripts)..where((t) => t.id.equals(id))).go();
  }

  /// 编译期就能给的新脚本 id（时间戳 + 后缀，够用且不引依赖）。
  static String newId([String prefix = 'script']) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

  Future<int> count() async => _db.planScripts.count().getSingle();

  /// 只在脚本表为空时播种（首次启动）。
  Future<void> seedIfEmpty(List<PlanScript> scripts) async {
    if (scripts.isEmpty) return;
    if (await count() > 0) return;
    await _insertAll(scripts);
  }

  /// 把还没入库的内置脚本补回来。
  ///
  /// 内置脚本是可以删的（用户可能压根不需要那三幕），但删了不该就找不回来——
  /// 所以脚本页留了一个"恢复内置脚本"的入口。返回补回来的条数。
  Future<int> restoreBuiltIns(List<PlanScript> builtIns) async {
    final existing = (await _db.select(_db.planScripts).get())
        .map((row) => row.id)
        .toSet();
    final missing = builtIns
        .where((script) => !existing.contains(script.id))
        .toList(growable: false);
    if (missing.isEmpty) return 0;

    await _insertAll(missing);
    return missing.length;
  }

  Future<void> _insertAll(List<PlanScript> scripts) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.batch((batch) {
      for (final script in scripts) {
        batch.insert(
          _db.planScripts,
          PlanScriptsCompanion.insert(
            id: script.id,
            name: script.name,
            createdAt: now,
            updatedAt: now,
            isBuiltIn: Value(script.isBuiltIn),
            postContent: Value(script.postContent),
            postImages: Value(jsonEncode(script.postImages)),
            topicName: Value(script.topicName),
            stepsJson: Value(_encodeSteps(script.steps)),
          ),
        );
      }
    });
  }

  String _encodeSteps(List<PlanStep> steps) =>
      jsonEncode(steps.map((s) => s.toJson()).toList(growable: false));

  PlanScript _toDomain(PlanScriptRow row) => PlanScript(
    id: row.id,
    name: row.name,
    isBuiltIn: row.isBuiltIn,
    postContent: row.postContent,
    postImages: _decodeStringList(row.postImages),
    topicName: row.topicName,
    steps: _decodeSteps(row.stepsJson),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  List<PlanStep> _decodeSteps(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(PlanStep.fromJson)
            .toList(growable: false);
      }
    } on FormatException {
      // 脚本 JSON 坏了就当作空脚本，不让一条脏数据把发布页打崩
      return const [];
    }
    return const [];
  }

  List<String> _decodeStringList(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } on FormatException {
      return const [];
    }
    return const [];
  }
}

final planScriptRepositoryProvider = Provider<PlanScriptRepository>(
  (ref) => PlanScriptRepository(ref.watch(databaseProvider)),
);

/// 脚本列表（发布页与脚本管理页共用）。
final planScriptsProvider = StreamProvider<List<PlanScript>>(
  (ref) => ref.watch(planScriptRepositoryProvider).watchAll(),
);
