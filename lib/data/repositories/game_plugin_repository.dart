import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/game_plugin.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 声明式游戏插件的安装与管理（v50）。
///
/// 只认 GitHub 上的 JSON 清单：不下载可执行文件、不执行远程代码。
/// 国内直连 raw.githubusercontent.com 经常超时，所以失败时自动换
/// gh-proxy 镜像；装好之后游戏完全离线。
class GamePluginRepository {
  GamePluginRepository(this._db, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              responseType: ResponseType.plain,
              headers: {'Accept': 'application/json'},
            ),
          );

  final AppDatabase _db;
  final Dio _dio;

  static const String manifestFile = 'echo-game.json';
  static const int maxBytes = 1 << 20; // 1 MiB

  Stream<List<GamePlugin>> watchAll() {
    final query = _db.select(_db.gamePlugins)
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  Future<List<GamePlugin>> all() async {
    final rows = await (_db.select(_db.gamePlugins)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
    return rows.map(_toDomain).toList(growable: false);
  }

  Future<GamePlugin?> findById(String id) async {
    final row =
        await (_db.select(_db.gamePlugins)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  /// 从 GitHub 链接安装/更新。
  ///
  /// 支持：
  /// - `https://github.com/owner/repo`
  /// - `https://github.com/owner/repo/tree/branch`
  /// - `https://raw.githubusercontent.com/.../echo-game.json`
  /// - 以上链接的 gh-proxy 镜像形式
  Future<GamePlugin> installFromUrl(String rawUrl) async {
    final urls = _candidateUrls(rawUrl);
    Object? lastError;
    String? body;
    for (final url in urls) {
      try {
        final response = await _dio.get<String>(url);
        final data = response.data;
        if (data == null || data.trim().isEmpty) continue;
        if (data.length > maxBytes) {
          throw const FormatException('插件清单超过 1MB，太大了');
        }
        body = data;
        break;
      } catch (error) {
        lastError = error;
      }
    }
    if (body == null) {
      throw FormatException(
        '下载插件清单失败。请确认仓库根目录有 $manifestFile，'
        '并且链接可以公开访问${lastError == null ? '' : '（$lastError）'}',
      );
    }
    final plugin = GamePlugin.parse(body, sourceUrl: rawUrl.trim());
    final builtinConflict = plugin.id == 'werewolf' ||
        plugin.id == 'gomoku' ||
        plugin.id == 'xiangqi';
    if (builtinConflict) {
      throw const FormatException('插件 id 和内置游戏重名了，换一个 id');
    }
    final existing =
        await (_db.select(_db.gamePlugins)
              ..where((t) => t.id.equals(plugin.id)))
            .getSingleOrNull();
    if (existing != null && existing.sourceUrl != rawUrl.trim()) {
      throw FormatException(
        '已经有一个同 id 的插件来自别处：${existing.sourceUrl}',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.gamePlugins)
        .insertOnConflictUpdate(
          GamePluginsCompanion.insert(
            id: plugin.id,
            name: plugin.name,
            description: Value(plugin.description),
            sourceUrl: rawUrl.trim(),
            manifestJson: plugin.manifestJson,
            enabled: const Value(true),
            minPlayers: Value(plugin.minPlayers),
            maxPlayers: Value(plugin.maxPlayers),
            installedAt: existing?.installedAt ?? now,
            updatedAt: now,
          ),
        );
    return (await findById(plugin.id))!;
  }

  Future<void> remove(String id) async {
    await (_db.delete(_db.gamePlugins)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await (_db.update(_db.gamePlugins)
          ..where((t) => t.id.equals(id)))
        .write(
          GamePluginsCompanion(
            enabled: Value(enabled),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  /// 把用户输入的链接变成几个可尝试的下载地址。
  ///
  /// 只允许 GitHub / 常见镜像，避免把任意 URL 变成服务器请求。
  static List<String> _candidateUrls(String raw) {
    final input = raw.trim();
    if (input.isEmpty) throw const FormatException('链接是空的');
    final uri = Uri.tryParse(input);
    if (uri == null || !uri.hasScheme || uri.scheme != 'https') {
      throw const FormatException('请用 https:// 开头的 GitHub 链接');
    }
    const allowed = {
      'github.com',
      'raw.githubusercontent.com',
      'gist.githubusercontent.com',
      'gh-proxy.com',
      'ghfast.top',
      'ghproxy.net',
    };
    if (!allowed.contains(uri.host)) {
      throw FormatException('只支持 GitHub 链接（当前：${uri.host}）');
    }

    final directs = <String>[];
    if (uri.host == 'github.com') {
      final parts = uri.pathSegments;
      if (parts.length < 2) {
        throw const FormatException('GitHub 链接里缺少仓库名');
      }
      final owner = parts[0];
      final repo = parts[1];
      final treeIndex = parts.indexOf('tree');
      final blobIndex = parts.indexOf('blob');
      if (treeIndex >= 0 && treeIndex + 1 < parts.length) {
        final branch = parts[treeIndex + 1];
        directs.add(
          'https://raw.githubusercontent.com/$owner/$repo/$branch/$manifestFile',
        );
      } else if (blobIndex >= 0 && blobIndex + 1 < parts.length) {
        final branch = parts[blobIndex + 1];
        final rest = parts.skip(blobIndex + 2).join('/');
        if (!rest.toLowerCase().endsWith('.json')) {
          throw const FormatException('这个链接没有指向 echo-game.json');
        }
        directs.add(
          'https://raw.githubusercontent.com/$owner/$repo/$branch/$rest',
        );
      } else {
        // 没写分支时，常见默认分支都试一遍；raw.githubusercontent.com
        // 对 HEAD 的支持并不总是可靠。
        for (final branch in const ['HEAD', 'main', 'master']) {
          directs.add(
            'https://raw.githubusercontent.com/$owner/$repo/'
            '$branch/$manifestFile',
          );
        }
      }
    } else {
      if (!uri.path.toLowerCase().endsWith('.json')) {
        throw const FormatException('请直接给仓库链接，或指向 echo-game.json');
      }
      directs.add(input);
    }

    return [
      for (final direct in directs) ...[
        direct,
        'https://gh-proxy.com/$direct',
        'https://ghfast.top/$direct',
        'https://ghproxy.net/$direct',
      ],
    ];
  }

  GamePlugin _toDomain(GamePluginRow row) {
    try {
      final parsed = GamePlugin.parse(
        row.manifestJson,
        sourceUrl: row.sourceUrl,
      );
      return GamePlugin(
        id: row.id,
        name: row.name,
        description: row.description,
        sourceUrl: row.sourceUrl,
        minPlayers: row.minPlayers,
        maxPlayers: row.maxPlayers,
        initialState: parsed.initialState,
        tools: parsed.tools,
        stateFields: parsed.stateFields,
        manifestJson: row.manifestJson,
        enabled: row.enabled,
      );
    } catch (_) {
      // 清单损坏时保留一行，页面能删掉它，不把整个游戏页炸掉。
      return GamePlugin(
        id: row.id,
        name: row.name,
        description: '清单损坏，删掉后重新安装',
        sourceUrl: row.sourceUrl,
        minPlayers: 1,
        maxPlayers: 1,
        initialState: const {},
        tools: const [],
        stateFields: const [],
        manifestJson: row.manifestJson,
        enabled: false,
      );
    }
  }
}

final gamePluginRepositoryProvider = Provider<GamePluginRepository>(
  (ref) => GamePluginRepository(ref.watch(databaseProvider)),
);

final gamePluginsProvider = StreamProvider<List<GamePlugin>>(
  (ref) => ref.watch(gamePluginRepositoryProvider).watchAll(),
);
