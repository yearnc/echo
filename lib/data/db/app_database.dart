import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/ai_tables.dart';
import 'tables/content_tables.dart';
import 'tables/log_tables.dart';
import 'tables/media_tables.dart';

part 'app_database.g.dart';

/// Echo 本地数据库（规划书 §8）。
///
/// 本地优先：帖子、图片、AI 互动、分析结果全部只存在这台设备上。
/// 唯一的例外是调用用户自己配置的模型时，帖内容会发给那个 API——
/// 这一点在设置页和隐私说明里都有明示。
@DriftDatabase(
  tables: [
    AppSettings,
    UserProfile,
    Posts,
    AiPersonas,
    AiInteractions,
    AnalysisResults,
    ModeSwitchLogs,
    NotificationLogs,
    FeedbackViewLogs,
    Stickers,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 测试用：传入内存执行器，避免碰真实文件。
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          // 外键约束默认是关的，必须显式打开，否则 ai_interactions 的引用形同虚设
          await customStatement('PRAGMA foreign_keys = ON');
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 的 ai_interactions 带 (postId, personaId, type) 唯一约束，
            // 会禁止同一住民对同一条帖子多次评论——而"连续回复"正是规划书要的效果。
            // v2 去掉该约束，只能重建表。阶段 A 的互动都是可再生的（种子/演示脚本），
            // 因此不做数据搬迁。
            await m.deleteTable('ai_interactions');
            await m.createTable(aiInteractions);
          }
        },
      );
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'echo.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
