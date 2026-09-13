import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/models/model_config.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 密钥存储的边界。
///
/// 抽成接口是为了能在测试里换成内存实现——真实实现要走平台通道，
/// 在单元测试里调不起来，"删配置要连密钥一起清掉"这条就没法验证。
abstract interface class KeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// 生产实现：系统钥匙串（Windows 走 DPAPI、Android 走 Keystore）。
class SecureKeyStore implements KeyStore {
  const SecureKeyStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// 模型配置的读写。
///
/// 拆成两半：**怎么连**（地址、模型名）在本地数据库，
/// **API Key** 在系统钥匙串。两者用同一个 id 关联——
/// 所以就算有人拷走了 echo.sqlite，也拿不到密钥。
class ModelConfigRepository {
  ModelConfigRepository(this._db, {KeyStore? keyStore})
    : _keyStore = keyStore ?? const SecureKeyStore();

  final AppDatabase _db;
  final KeyStore _keyStore;

  static const String _keyPrefix = 'echo.model.key.';

  Stream<List<ModelConfig>> watchAll() {
    final query = _db.select(_db.modelConfigs)
      ..orderBy([
        (t) => OrderingTerm.desc(t.enabled),
        (t) => OrderingTerm.desc(t.updatedAt),
      ]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  Future<ModelConfig?> findById(String id) async {
    final query = _db.select(_db.modelConfigs)..where((t) => t.id.equals(id));
    final row = await query.getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Future<void> save(ModelConfig config) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.modelConfigs)
        .insertOnConflictUpdate(
          ModelConfigsCompanion.insert(
            id: config.id,
            provider: config.provider,
            label: config.label,
            baseUrl: config.baseUrl,
            model: config.model,
            createdAt: config.createdAt == 0 ? now : config.createdAt,
            updatedAt: now,
            enabled: Value(config.enabled),
          ),
        );
  }

  /// 启用某一条（同一时间只允许一条启用）。
  Future<void> setEnabled(String id) async {
    await _db.transaction(() async {
      await _db
          .update(_db.modelConfigs)
          .write(const ModelConfigsCompanion(enabled: Value(false)));
      await (_db.update(_db.modelConfigs)..where((t) => t.id.equals(id))).write(
        const ModelConfigsCompanion(enabled: Value(true)),
      );
    });
  }

  /// 删配置时连密钥一起清掉——留着一条没有配置的孤零零密钥没有意义。
  Future<void> delete(String id) async {
    await (_db.delete(_db.modelConfigs)..where((t) => t.id.equals(id))).go();
    await _keyStore.delete('$_keyPrefix$id');
  }

  Future<String?> readKey(String id) => _keyStore.read('$_keyPrefix$id');

  Future<void> writeKey(String id, String value) =>
      _keyStore.write('$_keyPrefix$id', value);

  Future<bool> hasKey(String id) async =>
      (await readKey(id))?.trim().isNotEmpty ?? false;

  static String newId() => 'model_${DateTime.now().microsecondsSinceEpoch}';

  ModelConfig _toDomain(ModelConfigRow row) => ModelConfig(
    id: row.id,
    provider: row.provider,
    label: row.label,
    baseUrl: row.baseUrl,
    model: row.model,
    enabled: row.enabled,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

final modelConfigRepositoryProvider = Provider<ModelConfigRepository>(
  (ref) => ModelConfigRepository(ref.watch(databaseProvider)),
);

final modelConfigsProvider = StreamProvider<List<ModelConfig>>(
  (ref) => ref.watch(modelConfigRepositoryProvider).watchAll(),
);

/// 某条配置有没有填过密钥（列表页要标"还没填密钥"）。
final modelHasKeyProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, id) => ref.watch(modelConfigRepositoryProvider).hasKey(id),
);
