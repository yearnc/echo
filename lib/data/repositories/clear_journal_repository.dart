import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/clear_journal.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 清醒模式的读写：价值澄清 + 真实行动（规划书 §4）。
///
/// 两者都用**软删除**：一份写满的价值观清单被误删一条，比"删了还能恢复"
/// 更让人难受；而周报要统计"这周真实行动了几次"，硬删除会让已经算过的数
/// 在下次打开时变少——那比数字本身更可疑。
class ClearJournalRepository {
  const ClearJournalRepository(this._db);

  final AppDatabase _db;

  // ── 价值澄清 ────────────────────────────────────────────────

  /// 列表按用户排的顺序来，不是按时间。同一顺序时再按创建时间兜底。
  Stream<List<ValueItem>> watchValues() {
    final query = _db.select(_db.valueClarifications)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return query.watch().map(
      (rows) => rows.map(_toValueItem).toList(growable: false),
    );
  }

  Future<List<ValueItem>> listValues() async {
    final query = _db.select(_db.valueClarifications)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return (await query.get()).map(_toValueItem).toList(growable: false);
  }

  /// 追加一条到末尾。返回新条目的 id。
  Future<String> addValue(String content) async {
    final items = await listValues();
    final id = newId('value');
    await _db
        .into(_db.valueClarifications)
        .insert(
          ValueClarificationsCompanion.insert(
            id: id,
            content: content.trim(),
            createdAt: DateTime.now().millisecondsSinceEpoch,
            sortOrder: Value(items.length),
          ),
        );
    return id;
  }

  Future<void> updateValueContent(String id, String content) async {
    await (_db.update(
      _db.valueClarifications,
    )..where((t) => t.id.equals(id))).write(
      ValueClarificationsCompanion(content: Value(content.trim())),
    );
  }

  /// 软删除，并把后面的条目往前挪，免得 sortOrder 出现空洞。
  Future<void> deleteValue(String id) async {
    await (_db.update(_db.valueClarifications)
          ..where((t) => t.id.equals(id)))
        .write(
          ValueClarificationsCompanion(
            deletedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
    await _normalizeValueOrder();
  }

  /// 按给定的 id 顺序重排（上移 / 下移后就调它）。
  Future<void> reorderValues(List<String> idsInOrder) async {
    await _db.batch((batch) {
      for (var i = 0; i < idsInOrder.length; i++) {
        batch.update(
          _db.valueClarifications,
          ValueClarificationsCompanion(sortOrder: Value(i)),
          where: (t) => t.id.equals(idsInOrder[i]),
        );
      }
    });
  }

  Future<void> _normalizeValueOrder() async {
    final items = await listValues();
    await reorderValues(items.map((item) => item.id).toList(growable: false));
  }

  ValueItem _toValueItem(ValueClarificationRow row) => ValueItem(
    id: row.id,
    content: row.content,
    sortOrder: row.sortOrder,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
  );

  // ── 真实行动 ────────────────────────────────────────────────

  /// 最近记的排在最上面。
  Stream<List<RealAction>> watchActions() {
    final query = _db.select(_db.realActions)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_toRealAction).toList(growable: false),
    );
  }

  Future<String> addAction({
    required String title,
    String description = '',
    RealActionCategory category = RealActionCategory.other,
  }) async {
    final id = newId('action');
    await _db
        .into(_db.realActions)
        .insert(
          RealActionsCompanion.insert(
            id: id,
            title: title.trim(),
            description: Value(description.trim()),
            category: category.id,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    return id;
  }

  Future<void> deleteAction(String id) async {
    await (_db.update(_db.realActions)..where((t) => t.id.equals(id))).write(
      RealActionsCompanion(
        deletedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 某个时间点之后记了几条（周报用）。
  Future<int> countActionsSince(int sinceMs) async {
    final count = _db.realActions.id.count();
    final query = _db.selectOnly(_db.realActions)
      ..addColumns([count])
      ..where(
        _db.realActions.deletedAt.isNull() &
            _db.realActions.createdAt.isBiggerOrEqualValue(sinceMs),
      );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  RealAction _toRealAction(RealActionRow row) => RealAction(
    id: row.id,
    title: row.title,
    description: row.description,
    category: RealActionCategory.fromId(row.category),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
  );

  static final Random _rand = Random();

  /// 时间戳 + 随机后缀。
  ///
  /// 只用时间戳不够：`DateTime.now()` 的实际精度常常只有毫秒（Windows 上尤其），
  /// 连着插入两条会拿到同一个值而撞主键。
  static String newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 20)}';
}

final clearJournalRepositoryProvider = Provider<ClearJournalRepository>(
  (ref) => ClearJournalRepository(ref.watch(databaseProvider)),
);

/// 价值澄清清单（清醒模式记录页与价值澄清页共用）。
final valueItemsProvider = StreamProvider<List<ValueItem>>(
  (ref) => ref.watch(clearJournalRepositoryProvider).watchValues(),
);

/// 真实行动记录（真实行动页与周报共用）。
final realActionsProvider = StreamProvider<List<RealAction>>(
  (ref) => ref.watch(clearJournalRepositoryProvider).watchActions(),
);

/// 最近 7 天记了几件真实行动。
///
/// 订阅列表本身，所以新增/删除后这个数会跟着重算——
/// 不能让用户删了一条记录、数字却还停在旧值。
final weeklyActionCountProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(realActionsProvider);
  final since = DateTime.now()
      .subtract(const Duration(days: 7))
      .millisecondsSinceEpoch;
  return ref.watch(clearJournalRepositoryProvider).countActionsSince(since);
});
