import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/clear_insight_repository.dart';
import '../../data/repositories/clear_photo_repository.dart';
import '../../data/repositories/usage_repository.dart';
import '../../data/media/media_service.dart';

/// 清醒数据的一键导出与删除（v31）。
///
/// 导出的边界写死在这里：**只有 scope=clear 的东西**——价值澄清、真实行动、
/// 清醒记录、相册、分析快照、使用时长。回响侧的 AI 互动、住民、私信
/// 一条都不进这份文件。
class ClearDataService {
  const ClearDataService({
    required this.db,
    required this.photos,
    required this.insights,
    required this.usage,
    required this.media,
  });

  final AppDatabase db;
  final ClearPhotoRepository photos;
  final ClearInsightRepository insights;
  final UsageRepository usage;
  final MediaService media;

  /// 导出一份 JSON，返回文件路径。
  Future<String> export() async {
    final values = await (db.select(db.valueClarifications)
          ..where(
            (t) => t.deletedAt.isNull() & t.scope.equals('clear'),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    final actions = await (db.select(db.realActions)
          ..where((t) => t.deletedAt.isNull() & t.scope.equals('clear'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    final records = await (db.select(db.posts)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.scope.equals('clear') &
                t.authorPersonaId.isNull() &
                t.authorResidentId.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    final photoRows = await photos.all();
    final insightRows = await insights.all();
    final usageRows = await usage.all();

    final data = {
      'exported_at': DateTime.now().toIso8601String(),
      'scope': 'clear',
      'note': '这份文件只含清醒侧的真实记录，不含回响侧的 AI 互动、住民主页与私信。',
      'values': [
        for (final row in values)
          {
            'content': row.content,
            'sort_order': row.sortOrder,
            'created_at':
                DateTime.fromMillisecondsSinceEpoch(row.createdAt).toIso8601String(),
          },
      ],
      'actions': [
        for (final row in actions)
          {
            'title': row.title,
            'description': row.description,
            'category': row.category,
            'mood': row.mood,
            'created_at':
                DateTime.fromMillisecondsSinceEpoch(row.createdAt).toIso8601String(),
          },
      ],
      'records': [
        for (final row in records)
          {
            'content': row.content,
            'topic': row.topicName,
            'images': _decodeList(row.images),
            'created_at':
                DateTime.fromMillisecondsSinceEpoch(row.createdAt).toIso8601String(),
          },
      ],
      'photos': [
        for (final row in photoRows)
          {
            'caption': row.caption,
            // 只导文件名：私有目录的绝对路径换台设备就没意义了。
            'file': p.basename(row.path.replaceFirst('file:', '')),
            'created_at':
                DateTime.fromMillisecondsSinceEpoch(row.createdAt).toIso8601String(),
          },
      ],
      'insights': [
        for (final insight in insightRows)
          {
            'summary': insight.summary,
            'source': insight.source,
            'period_start': insight.periodStart.toIso8601String(),
            'period_end': insight.periodEnd.toIso8601String(),
            'generated_at': insight.generatedAt.toIso8601String(),
            'metrics': [
              for (final metric in insight.metrics) metric.toJson(),
            ],
          },
      ],
      'usage_sessions': [
        for (final row in usageRows)
          {
            'started_at':
                DateTime.fromMillisecondsSinceEpoch(row.startedAt).toIso8601String(),
            'ended_at':
                DateTime.fromMillisecondsSinceEpoch(row.endedAt).toIso8601String(),
            'minutes': (row.durationMs / 60000).toStringAsFixed(1),
          },
      ],
    };

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'exports'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    final now = DateTime.now();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}-'
        '${_two(now.hour)}${_two(now.minute)}';
    final file = File(p.join(dir.path, 'echo-clear-$stamp.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    return file.path;
  }

  /// 只删分析快照。
  Future<int> deleteInsights() => insights.deleteAll();

  /// 清空相册（连同磁盘文件）。
  Future<int> deletePhotos() => photos.deleteAll();

  /// 清空清醒侧的全部记录。
  ///
  /// 硬删除：用户点了“清除”就是不要了。相册文件一起删；
  /// 回响侧数据一条不碰。
  Future<void> deleteAllClearData() async {
    await photos.deleteAll();

    final clearPosts = await (db.select(db.posts)
          ..where((t) => t.scope.equals('clear')))
        .get();
    for (final row in clearPosts) {
      for (final ref in _decodeList(row.images)) {
        await media.deleteByRef(ref);
      }
    }

    // 只删 scope=clear 的帖子；回响侧一条不动。
    // 帖子被好几张表引用着，先清依赖再删本体，避免外键把删除拦下来。
    final postIds = [for (final row in clearPosts) row.id];
    if (postIds.isNotEmpty) {
      await (db.delete(db.postViews)
            ..where((t) => t.postId.isIn(postIds)))
          .go();
      await (db.delete(db.postVoices)
            ..where((t) => t.postId.isIn(postIds)))
          .go();
      await (db.delete(db.userComments)
            ..where((t) => t.postId.isIn(postIds)))
          .go();
      await (db.delete(db.aiInteractions)
            ..where((t) => t.postId.isIn(postIds)))
          .go();
      await (db.delete(db.postUnderstandings)
            ..where((t) => t.postId.isIn(postIds)))
          .go();
      await (db.delete(db.analysisResults)
            ..where((t) => t.postId.isIn(postIds)))
          .go();
      await (db.delete(db.planEvents)
            ..where((t) => t.postId.isIn(postIds)))
          .go();
    }
    await (db.delete(db.posts)..where((t) => t.scope.equals('clear'))).go();
    await (db.delete(db.valueClarifications)
          ..where((t) => t.scope.equals('clear')))
        .go();
    await (db.delete(db.realActions)..where((t) => t.scope.equals('clear')))
        .go();
    await insights.deleteAll();
    await usage.deleteAll();
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static List<String> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is String) item,
      ];
    } catch (_) {
      return const [];
    }
  }
}

final clearDataServiceProvider = Provider<ClearDataService>(
  (ref) => ClearDataService(
    db: ref.watch(databaseProvider),
    photos: ref.watch(clearPhotoRepositoryProvider),
    insights: ref.watch(clearInsightRepositoryProvider),
    usage: ref.watch(usageRepositoryProvider),
    media: ref.watch(mediaServiceProvider),
  ),
);
