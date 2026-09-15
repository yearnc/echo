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

  /// 把内置脚本同步回出厂状态。
  ///
  /// 做三件事：补回被删掉的、**刷新与出厂版本不一致的**、以及
  /// **清掉已经下线的**。
  ///
  /// 前两件是必要的：脚本定义会随着功能一起长，已经播种过的库不会自动更新。
  /// 第三件同样是必要的：内置脚本的**集合**本身会变——第三幕已经取消
  /// （它唯一的动作没有页面读，且清醒模式发帖本来就不排期），
  /// 老库里那一行不会自己消失，不清理就会永远留一个点了没反应的死脚本。
  ///
  /// 用户自己复制出来的副本不受影响——想保留改动，就该先复制一份。
  Future<({int written, int removed})> restoreBuiltIns(
    List<PlanScript> builtIns,
  ) async {
    final existing = {
      for (final row in await _db.select(_db.planScripts).get()) row.id: row,
    };

    final shippedIds = {for (final script in builtIns) script.id};
    final retiredIds = [
      for (final row in existing.values)
        if (row.isBuiltIn && !shippedIds.contains(row.id)) row.id,
    ];

    final toWrite = <PlanScript>[];
    for (final script in builtIns) {
      final row = existing[script.id];
      if (row == null) {
        toWrite.add(script);
        continue;
      }
      final changed =
          row.stepsJson != _encodeSteps(script.steps) ||
          row.postContent != script.postContent ||
          row.name != script.name;
      if (changed) toWrite.add(script);
    }

    if (toWrite.isNotEmpty) await _insertAll(toWrite);
    if (retiredIds.isNotEmpty) {
      await (_db.delete(
        _db.planScripts,
      )..where((t) => t.id.isIn(retiredIds))).go();
    }

    return (written: toWrite.length, removed: retiredIds.length);
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
          // 刷新已有行要用覆盖模式，否则主键冲突直接抛异常
          mode: InsertMode.insertOrReplace,
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
