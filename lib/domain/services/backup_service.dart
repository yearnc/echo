import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_info.dart';
import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';

/// 全量备份与恢复（v3.9）。
///
/// 两种加密模式：
/// - **integrity（默认）**：不设密码。密钥由应用内固定串派生，AES-GCM 同时
///   做加密与完整性校验——文件被改过一个字节就解不开。拿到文件的人当然
///   也能用同一个 App 导入，所以它**不是保密措施**，只防意外损坏与篡改。
/// - **password**：用户密码 → PBKDF2-HMAC-SHA256（12 万次）→ AES-GCM。
///   换设备后必须输入同一个密码才能解开。
///
/// 备份是**全量表快照**：帖子、互动、住民、记忆、私信、设置……都进去；
/// 模型密钥本来就在系统钥匙串，不在数据库里，所以不会被带走。
class BackupService {
  BackupService(this._db, {Future<Directory> Function()? documents})
    : _documents = documents ?? getApplicationDocumentsDirectory;

  final AppDatabase _db;

  /// 备份文件放哪。测试里换成临时目录，不用碰 path_provider。
  final Future<Directory> Function() _documents;

  static const String formatTag = 'echo-backup';
  static const int formatVersion = 1;
  static const int _iterations = 120000;

  /// 默认模式的固定派生串。改它会让旧备份解不开，别随手改。
  static const String _integritySeed = 'echo-backup:integrity:v1';

  /// 导出。返回写好的文件路径。
  Future<String> export({String? password}) async {
    final payload = await _snapshot();
    final plain = utf8.encode(jsonEncode(payload));

    final SecretKey key;
    final Map<String, Object?> kdf;
    final mode = (password == null || password.isEmpty)
        ? 'integrity'
        : 'password';
    if (mode == 'integrity') {
      key = await _integrityKey();
      kdf = const {'algorithm': 'fixed-sha256'};
    } else {
      final salt = _randomBytes(16);
      key = await _passwordKey(password!, salt);
      kdf = {
        'algorithm': 'pbkdf2-hmac-sha256',
        'iterations': _iterations,
        'salt': base64Encode(salt),
      };
    }

    final cipher = AesGcm.with256bits();
    final nonce = cipher.newNonce();
    final box = await cipher.encrypt(plain, secretKey: key, nonce: nonce);

    final envelope = {
      'format': formatTag,
      'version': formatVersion,
      'mode': mode,
      'cipher': 'aes-gcm-256',
      'kdf': kdf,
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'payload': base64Encode(box.cipherText),
      'created_at': DateTime.now().toIso8601String(),
      'app_version': appVersion,
    };

    final docs = await _documents();
    final dir = Directory(p.join(docs.path, 'backups'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    final now = DateTime.now();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}-'
        '${_two(now.hour)}${_two(now.minute)}';
    final file = File(p.join(dir.path, 'echo-backup-$stamp.echobak'));
    await file.writeAsString(jsonEncode(envelope), flush: true);
    return file.path;
  }

  /// 只读信封（不解密），用来判断需不需要密码、是哪一版导出的。
  Future<BackupEnvelope> read(String path) async {
    final raw = await File(path).readAsString();
    return BackupEnvelope.parse(raw);
  }

  /// 解密 + 校验。密码不对或文件被动过都会抛 [BackupException]。
  Future<BackupPayload> decode(
    BackupEnvelope envelope, {
    String? password,
  }) async {
    final SecretKey key;
    switch (envelope.mode) {
      case 'integrity':
        key = await _integrityKey();
      case 'password':
        final saltRaw = envelope.salt;
        if (saltRaw == null || saltRaw.isEmpty) {
          throw const BackupException('备份文件缺少盐，无法解密');
        }
        if (password == null || password.isEmpty) {
          throw const BackupException('这份备份需要密码');
        }
        key = await _passwordKey(password, saltRaw);
      default:
        throw BackupException('不认识的加密方式：${envelope.mode}');
    }

    try {
      final cipher = AesGcm.with256bits();
      final clear = await cipher.decrypt(
        SecretBox(
          base64Decode(envelope.payload),
          nonce: base64Decode(envelope.nonce),
          mac: Mac(base64Decode(envelope.mac)),
        ),
        secretKey: key,
      );
      final decoded = jsonDecode(utf8.decode(clear));
      if (decoded is! Map) {
        throw const BackupException('备份内容不是有效的 JSON');
      }
      return BackupPayload.fromJson(decoded.cast<String, Object?>());
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException('密码不对，或者备份文件被改动过');
    }
  }

  /// 覆盖恢复。调用方必须已经明确确认过——这里不再问。
  Future<RestoreResult> restore(BackupPayload payload) async {
    final known = {for (final table in _db.allTables) table.actualTableName};
    final tables = {
      for (final entry in payload.tables.entries)
        if (known.contains(entry.key)) entry.key: entry.value,
    };
    if (tables.isEmpty) {
      throw const BackupException('这份备份里没有可恢复的数据');
    }

    var rows = 0;
    // 外键先关：删除顺序和快照里的插入顺序都不必再迁就引用关系。
    await _db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await _db.transaction(() async {
        for (final table in _db.allTables) {
          await _db.customStatement('DELETE FROM "${table.actualTableName}"');
        }
        for (final entry in tables.entries) {
          final table = entry.key;
          for (final row in entry.value) {
            if (row.isEmpty) continue;
            final columns = row.keys.map((name) => '"$name"').join(', ');
            final marks = List.filled(row.length, '?').join(', ');
            await _db.customInsert(
              'INSERT INTO "$table" ($columns) VALUES ($marks)',
              variables: [
                for (final value in row.values) Variable(_decodeValue(value)),
              ],
            );
            rows += 1;
          }
        }
      });
    } finally {
      await _db.customStatement('PRAGMA foreign_keys = ON');
    }

    // customStatement 不会触发表更新：手动叫醒所有监听中的流，
    // 页面不用等重启就能显示恢复后的数据。
    _db.markTablesUpdated(_db.allTables);
    return RestoreResult(tables: tables.length, rows: rows);
  }

  Future<Map<String, Object?>> _snapshot() async {
    final tables = <String, Object?>{};
    for (final table in _db.allTables) {
      final rows = await _db
          .customSelect('SELECT * FROM "${table.actualTableName}"')
          .get();
      tables[table.actualTableName] = [
        for (final row in rows)
          {
            for (final entry in row.data.entries)
              entry.key: _encodeValue(entry.value),
          },
      ];
    }
    return {
      'exported_at': DateTime.now().toIso8601String(),
      'app_version': appVersion,
      'tables': tables,
    };
  }

  Future<SecretKey> _integrityKey() async {
    final digest = await Sha256().hash(utf8.encode(_integritySeed));
    return SecretKey(digest.bytes);
  }

  Future<SecretKey> _passwordKey(String password, List<int> salt) {
    final pbkdf2 = Pbkdf2.hmacSha256(iterations: _iterations, bits: 256);
    return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// JSON 里只放基本类型；BLOB 转成带标记的 base64。
  static Object? _encodeValue(Object? value) {
    if (value == null || value is num || value is String || value is bool) {
      return value;
    }
    if (value is Uint8List) {
      return {'__blob': base64Encode(value)};
    }
    if (value is List<int>) {
      return {'__blob': base64Encode(value)};
    }
    return value.toString();
  }

  static Object? _decodeValue(Object? value) {
    if (value is Map && value['__blob'] is String) {
      return base64Decode(value['__blob'] as String);
    }
    return value;
  }
}

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackupEnvelope {
  const BackupEnvelope({
    required this.mode,
    required this.createdAt,
    required this.appVersion,
    required this.version,
    required this.nonce,
    required this.mac,
    required this.payload,
    this.salt,
  });

  final String mode;
  final DateTime createdAt;
  final String appVersion;
  final int version;
  final String nonce;
  final String mac;
  final String payload;
  final List<int>? salt;

  bool get needsPassword => mode == 'password';

  static BackupEnvelope parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const BackupException('这不是回响的备份文件');
    }
    if (decoded is! Map || decoded['format'] != BackupService.formatTag) {
      throw const BackupException('这不是回响的备份文件');
    }
    final map = decoded.cast<String, Object?>();
    final version = (map['version'] as num?)?.toInt() ?? 0;
    if (version > BackupService.formatVersion) {
      throw const BackupException('这份备份来自更新版本的回响，请先升级 App');
    }
    final kdf = map['kdf'];
    final saltRaw = kdf is Map ? kdf['salt'] : null;
    return BackupEnvelope(
      mode: (map['mode'] as String?) ?? 'integrity',
      createdAt:
          DateTime.tryParse((map['created_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      appVersion: (map['app_version'] as String?) ?? '未知',
      version: version,
      nonce: (map['nonce'] as String?) ?? '',
      mac: (map['mac'] as String?) ?? '',
      payload: (map['payload'] as String?) ?? '',
      salt: saltRaw is String && saltRaw.isNotEmpty
          ? base64Decode(saltRaw)
          : null,
    );
  }
}

class BackupPayload {
  const BackupPayload({required this.tables, required this.exportedAt});

  /// 表名 → 行列表。值里可能有 [Map] 包裹的 blob。
  final Map<String, List<Map<String, Object?>>> tables;
  final DateTime exportedAt;

  int get rowCount => tables.values.fold(0, (sum, rows) => sum + rows.length);

  static BackupPayload fromJson(Map<String, Object?> json) {
    final rawTables = json['tables'];
    if (rawTables is! Map) {
      throw const BackupException('备份里没有表数据');
    }
    final tables = <String, List<Map<String, Object?>>>{};
    for (final entry in rawTables.entries) {
      final name = entry.key;
      final rows = entry.value;
      if (name is! String || rows is! List) continue;
      tables[name] = [
        for (final row in rows)
          if (row is Map) row.cast<String, Object?>(),
      ];
    }
    return BackupPayload(
      tables: tables,
      exportedAt:
          DateTime.tryParse((json['exported_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class RestoreResult {
  const RestoreResult({required this.tables, required this.rows});

  final int tables;
  final int rows;
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider)),
);
