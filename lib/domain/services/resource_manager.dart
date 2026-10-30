import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../models/model_resource.dart';
import 'speech_models.dart';

/// 下载、解压、删除模型资源（v4.4）。
///
/// 资源不放进 APK，统一落在 `applicationSupport/speech_models/`。
/// 升级 APK 不会碰这个目录，所以没变版本的文件不用重新下。
class ResourceManager {
  ResourceManager(
    this._db,
    this._store, {
    Dio? dio,
  }) : _dio = dio ?? Dio();

  final AppDatabase _db;
  final SpeechModelStore _store;
  final Dio _dio;

  static const String _sourceKey = 'resources.source';
  static const String _metaName = '.installed.json';

  Future<Directory> rootDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'speech_models'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> directoryOf(ModelResource resource) async =>
      Directory(p.join((await rootDirectory()).path, resource.storageDir));

  Future<ResourceSource> source() async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((t) => t.key.equals(_sourceKey))).getSingleOrNull();
    return ResourceSource.parse(row?.value);
  }

  Future<void> setSource(ResourceSource value) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: _sourceKey, value: value.key),
        );
  }

  Future<InstalledResource?> installed(ModelResource resource) async {
    final dir = await directoryOf(resource);
    if (!await dir.exists()) return null;
    for (final name in resource.requiredFiles) {
      final file = File(p.joinAll([dir.path, ...name.split('/')]));
      if (!await file.exists() || await file.length() == 0) return null;
    }
    var version = 0;
    var bytes = 0;
    DateTime? installedAt;
    try {
      final meta = File(p.join(dir.path, _metaName));
      if (await meta.exists()) {
        final decoded = jsonDecode(await meta.readAsString());
        if (decoded is Map) {
          version = _asInt(decoded['version']);
          bytes = _asInt(decoded['bytes']);
          final at = decoded['installed_at'];
          if (at is String) installedAt = DateTime.tryParse(at);
        }
      }
    } catch (error) {
      debugPrint('[资源] 安装信息读不出来：$error');
    }
    // 没有元数据但文件齐全：按当前内置版本算，避免老用户被判成“未安装”。
    // 这类目录（旧全量包释放出来的）没有记录体积，按资源包大小估算展示。
    if (version == 0) version = resource.version;
    if (bytes == 0) bytes = resource.bytes;
    return InstalledResource(
      version: version,
      bytes: bytes,
      installedAt: installedAt,
    );
  }

  /// 下载并替换资源。先走用户选的源，失败自动换另一个源再试一次。
  Future<void> download(
    ModelResource resource, {
    required ResourceSource source,
    void Function(double progress)? onProgress,
  }) async {
    final root = await rootDirectory();
    final tempZip = File(
      p.join(root.path, '.download_${resource.id}_'
          '${DateTime.now().microsecondsSinceEpoch}.zip'),
    );
    final first = resource.urlFor(source);
    final fallback = resource.urlFor(
      source == ResourceSource.github
          ? ResourceSource.mirror
          : ResourceSource.github,
    );
    Object? firstError;
    var downloaded = false;
    for (final url in [first, if (fallback.isNotEmpty && fallback != first) fallback]) {
      if (url.trim().isEmpty) continue;
      try {
        await _dio.download(
          url,
          tempZip.path,
          deleteOnError: true,
          onReceiveProgress: (received, total) {
            final size = total > 0 ? total : resource.bytes;
            if (size <= 0) return;
            onProgress?.call((received / size).clamp(0.0, 1.0));
          },
          options: Options(
            receiveTimeout: const Duration(minutes: 30),
            sendTimeout: const Duration(seconds: 20),
          ),
        );
        if (await tempZip.exists() && await tempZip.length() > 1024) {
          downloaded = true;
          break;
        }
      } catch (error) {
        firstError = error;
        debugPrint('[资源] $url 下载失败：$error');
      }
    }
    if (!downloaded) {
      throw StateError(
        '下载失败。可以先换一个下载源再试；'
        '${firstError == null ? '' : '（$firstError）'}',
      );
    }

    try {
      await _verify(resource, tempZip);
      await _install(resource, tempZip);
      onProgress?.call(1);
    } finally {
      try {
        if (await tempZip.exists()) await tempZip.delete();
      } catch (_) {
        // 临时文件删不掉不拦安装结果。
      }
    }
  }

  Future<void> delete(ModelResource resource) async {
    final dir = await directoryOf(resource);
    if (await dir.exists()) await dir.delete(recursive: true);
    _store.invalidate(resource.storageDir);
  }

  Future<void> _verify(ModelResource resource, File zip) async {
    final raf = await zip.open(mode: FileMode.read);
    try {
      final head = await raf.read(2);
      if (head.length < 2 || head[0] != 0x50 || head[1] != 0x4B) {
        throw StateError('下载到的不是有效的压缩包，可能被网络代理改坏了');
      }
    } finally {
      await raf.close();
    }
    if (resource.sha256.trim().isEmpty) return;
    final sink = Sha256().newHashSink();
    await for (final chunk in zip.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final digest = (await sink.hash()).bytes;
    final hex = [
      for (final byte in digest) byte.toRadixString(16).padLeft(2, '0'),
    ].join();
    if (hex.toLowerCase() != resource.sha256.trim().toLowerCase()) {
      throw StateError('资源校验失败（文件可能下载不完整），请重试');
    }
  }

  Future<void> _install(ModelResource resource, File zip) async {
    final root = await rootDirectory();
    final tempDir = Directory(
      p.join(root.path, '.extract_${resource.id}_'
          '${DateTime.now().microsecondsSinceEpoch}'),
    );
    await tempDir.create(recursive: true);
    try {
      final input = InputFileStream(zip.path);
      try {
        final archive = ZipDecoder().decodeStream(input, verify: false);
        for (final entry in archive.files) {
          if (!entry.isFile) continue;
          final relative = p.normalize(entry.name);
          if (relative.startsWith('..') || p.isAbsolute(relative)) continue;
          final target = File(
            p.joinAll([tempDir.path, ...relative.split('/')]),
          );
          await target.parent.create(recursive: true);
          final output = OutputFileStream(target.path);
          try {
            entry.writeContent(output);
          } finally {
            await output.close();
          }
        }
      } finally {
        await input.close();
      }

      final base = await _findBase(resource, tempDir);
      if (base == null) {
        throw StateError('压缩包里缺少必要文件，资源包可能不完整');
      }
      final target = await directoryOf(resource);
      final backup = Directory('${target.path}.old');
      if (await backup.exists()) await backup.delete(recursive: true);
      if (await target.exists()) await target.rename(backup.path);
      try {
        if (p.equals(base.path, tempDir.path)) {
          // 解压目录本身就是资源根：挪过去时先删掉当时的临时壳。
          await tempDir.rename(target.path);
        } else {
          if (!await target.exists()) await target.create(recursive: true);
          await for (final entity in base.list(followLinks: false)) {
            await entity.rename(
              p.join(target.path, p.basename(entity.path)),
            );
          }
        }
      } catch (error) {
        if (await backup.exists() && !await target.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
      if (await backup.exists()) await backup.delete(recursive: true);
      await File(p.join(target.path, _metaName)).writeAsString(
        jsonEncode({
          'version': resource.version,
          'bytes': resource.bytes,
          'installed_at': DateTime.now().toIso8601String(),
          'source': resource.id,
        }),
        flush: true,
      );
      _store.invalidate(resource.storageDir);
    } finally {
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {
        // 清理失败交给系统缓存。
      }
    }
  }

  /// 压缩包可能把文件放在一层同名目录里；找到“包含全部必要文件”的那一层。
  Future<Directory?> _findBase(ModelResource resource, Directory root) async {
    Future<bool> hasAll(Directory dir) async {
      for (final name in resource.requiredFiles) {
        final file = File(p.joinAll([dir.path, ...name.split('/')]));
        if (!await file.exists() || await file.length() == 0) return false;
      }
      return true;
    }

    if (await hasAll(root)) return root;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory && await hasAll(entity)) return entity;
    }
    return null;
  }

  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw') ?? 0;
  }
}

final resourceManagerProvider = Provider<ResourceManager>((ref) {
  return ResourceManager(
    ref.watch(databaseProvider),
    ref.watch(speechModelStoreProvider),
  );
});
