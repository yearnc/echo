import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/custom_resident.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 用户自己配置的固定住民。
class CustomResidentRepository {
  const CustomResidentRepository(this._db);

  /// 内置固定住民的 id。播种时按它判断“有没有”，用户改过也不覆盖。
  static const String builtinResidentId = 'resident_builtin_dafeiyu';

  final AppDatabase _db;

  Stream<List<CustomResident>> watchAll() {
    final query = _db.select(_db.customResidents)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  Future<List<CustomResident>> all() async {
    final query = _db.select(_db.customResidents)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    final rows = await query.get();
    return rows.map(_toDomain).toList(growable: false);
  }

  /// 包括已经删掉的住民。
  ///
  /// 只用来**显示历史**：老帖子的作者、旧私信会话的名字和头像。
  /// 行为判断（能不能唤醒、能不能继续发私信）一律用 [all]。
  Stream<List<CustomResident>> watchAllIncludingDeleted() {
    final query = _db.select(_db.customResidents)
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  Future<CustomResident?> findById(String id) async {
    final row =
        await (_db.select(_db.customResidents)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Future<void> upsert(CustomResident resident) async {
    await _db
        .into(_db.customResidents)
        .insertOnConflictUpdate(
          CustomResidentsCompanion.insert(
            id: resident.id,
            name: resident.name,
            avatarAsset: Value(resident.avatarAsset),
            bio: Value(resident.bio),
            description: Value(resident.description),
            personality: Value(resident.personality),
            scenario: Value(resident.scenario),
            languageStyle: Value(resident.languageStyle),
            tone: Value(resident.tone),
            firstMessage: Value(resident.firstMessage),
            exampleDialogue: Value(resident.exampleDialogue),
            extraInstructions: Value(resident.extraInstructions),
            tags: Value(jsonEncode(resident.tags)),
            activeHours: Value(jsonEncode(resident.activeHours)),
            memoryEnabled: Value(resident.memoryEnabled),
            memoryLimit: Value(resident.memoryLimit),
            alwaysShow: Value(resident.alwaysShow),
            modelConfigId: Value(resident.modelConfigId),
            createdAt: resident.createdAt.millisecondsSinceEpoch,
          ),
        );
  }

  /// 删除一位固定住民。
  ///
  /// 只动“这个人还在不在”和运行期队列：
  /// - 本人软删除：不再进帖子、唤醒名单；
  /// - 待办清掉：以后不会再醒，留着也没人处理；
  /// - **私信原样保留**。过去的对话是发生过的事，可以回看，但页面会变成只读；
  ///   评论、动态、记忆同样保留。
  Future<int> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final affected =
        await (_db.update(
          _db.customResidents,
        )..where((t) => t.id.equals(id))).write(
          CustomResidentsCompanion(deletedAt: Value(now)),
        );

    await (_db.delete(
      _db.residentInboxItems,
    )..where((t) => t.residentId.equals(id))).go();

    return affected;
  }

  static String newId() => 'resident_${DateTime.now().microsecondsSinceEpoch}';

  CustomResident _toDomain(CustomResidentRow row) => CustomResident(
    id: row.id,
    name: row.name,
    avatarAsset: row.avatarAsset,
    bio: row.bio,
    description: row.description,
    personality: row.personality,
    scenario: row.scenario,
    languageStyle: row.languageStyle,
    tone: row.tone,
    firstMessage: row.firstMessage,
    exampleDialogue: row.exampleDialogue,
    extraInstructions: row.extraInstructions,
    tags: _strings(row.tags),
    activeHours: _hours(row.activeHours),
    memoryEnabled: row.memoryEnabled,
    memoryLimit: row.memoryLimit,
    alwaysShow: row.alwaysShow,
    modelConfigId: row.modelConfigId,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
  );

  static List<String> _strings(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ];
    } catch (_) {
      return const [];
    }
  }

  static List<int> _hours(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is num) item.toInt(),
      ];
    } catch (_) {
      return const [];
    }
  }
}

final customResidentRepositoryProvider = Provider<CustomResidentRepository>(
  (ref) => CustomResidentRepository(ref.watch(databaseProvider)),
);

final customResidentsProvider = StreamProvider<List<CustomResident>>(
  (ref) => ref.watch(customResidentRepositoryProvider).watchAll(),
);

final customResidentsIncludingDeletedProvider =
    StreamProvider<List<CustomResident>>(
      (ref) =>
          ref.watch(customResidentRepositoryProvider).watchAllIncludingDeleted(),
    );

/// 按 id 找一位还在社区里的固定住民（行为判断用）。
///
/// 固定住民数量很少（建议上限六个），从列表里找比每条动态各开一次
/// 数据库查询更省事，也和列表的刷新天然同步。
final customResidentByIdProvider = Provider.autoDispose
    .family<CustomResident?, String>((ref, id) {
      final all = ref.watch(customResidentsProvider).value ?? const [];
      for (final resident in all) {
        if (resident.id == id) return resident;
      }
      return null;
    });

/// 按 id 找一位固定住民，**包括已经删掉的**。
///
/// 只给“显示历史”用：旧帖子的作者、旧私信的名字和头像。
/// 已删除的人不该被唤醒，也不该再收到新私信。
final customResidentAnyByIdProvider = Provider.autoDispose
    .family<CustomResident?, String>((ref, id) {
      final all =
          ref.watch(customResidentsIncludingDeletedProvider).value ?? const [];
      for (final resident in all) {
        if (resident.id == id) return resident;
      }
      return null;
    });
