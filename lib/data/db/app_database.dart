import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/ai_tables.dart';
import 'tables/clear_tables.dart';
import 'tables/content_tables.dart';
import 'tables/log_tables.dart';
import 'tables/media_tables.dart';
import 'tables/model_tables.dart';
import 'tables/plan_tables.dart';
import 'tables/social_tables.dart';

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
    AiRelationships,
    PersonaRoutines,
    PrivateMessages,
    UserComments,
    CommentLikes,
    Topics,
    AnalysisResults,
    ModeSwitchLogs,
    NotificationLogs,
    FeedbackViewLogs,
    Stickers,
    PlanScripts,
    PlanEvents,
    ModelConfigs,
    ValueClarifications,
    RealActions,
    AddictionLogs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 测试用：传入内存执行器，避免碰真实文件。
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 12;

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
      if (from < 3) {
        // v3 新增策划脚本与策划事件队列；ai_personas 去掉 ipLocation 列。
        // 人设目前还是"内容资产"（从 assets 播种、不可编辑），
        // 所以删表重建最简单——下次启动会按新结构重新播种。
        await m.createTable(planScripts);
        await m.createTable(planEvents);
        await m.deleteTable('ai_personas');
        await m.createTable(aiPersonas);
      }
      if (from < 4) {
        // v4：清掉旧的播种内容（三幕演示帖 + 清醒模式示例记录）。
        // 它们不再是产品的一部分——空信息流才是新用户的真实起点。
        // 按 id 白名单删，只动确定由播种产生的行，不碰用户自己发的内容。
        const seededPostIds = [
          'demo_post_sky',
          'demo_post_trash',
          'demo_record_walk',
          'demo_record_book',
        ];
        for (final id in seededPostIds) {
          await (delete(
            aiInteractions,
          )..where((t) => t.postId.equals(id))).go();
          await (delete(posts)..where((t) => t.id.equals(id))).go();
        }
      }
      if (from < 5) {
        // v5：通知带上来源帖子，点通知可以直接跳到那条帖子。
        await m.addColumn(notificationLogs, notificationLogs.postId);
      }
      if (from < 6) {
        // v6：模型配置（密钥不放这里，在系统钥匙串）。
        await m.createTable(modelConfigs);
      }
      if (from < 7) {
        // v7：清醒模式的价值重建闭环（价值澄清 / 真实行动）+ 防沉迷日志。
        await m.createTable(valueClarifications);
        await m.createTable(realActions);
        await m.createTable(addictionLogs);
      }
      if (from < 8) {
        // v8：策划事件带上语音时长。原先这一步在转换时丢了，
        // 评论区只能显示 0"——老库里的语音条重排一次即可恢复。
        await m.addColumn(planEvents, planEvents.voiceDurationMs);
      }
      if (from < 9) {
        // v9：阶段 B 的社区关系层（规划书 §3 / §8）。
        //
        // 四张新表 + 两个新列，一次给齐：住民与用户的关系、住民的作息轨迹、
        // 私信、话题；帖子多一个"住民作者"，住民多一个"圈层"。
        //
        // 全是**新增**，没有删改既有结构——老库升上来时帖子、互动、设置、
        // 记录一概不动，这是这一版迁移唯一要保证的事。
        await m.createTable(aiRelationships);
        await m.createTable(personaRoutines);
        await m.createTable(privateMessages);
        await m.createTable(topics);
        await m.addColumn(posts, posts.authorPersonaId);
        await m.addColumn(aiPersonas, aiPersonas.circle);
      }
      if (from < 10) {
        // v10：模型配置分用途（对话 / 文生图）。
        // 老配置都是拿来聊天的，默认值正好就是它。
        await m.addColumn(modelConfigs, modelConfigs.kind);
      }
      if (from < 11) {
        // v11：用户自己也能点赞和评论了。
        // 之前只有住民在说话——社区是单向的，回一句都没地方回。
        await m.createTable(userComments);
        await m.addColumn(posts, posts.likedAt);
      }
      if (from < 12) {
        // v12：评论也能点赞、也能回了。
        await m.createTable(commentLikes);

        // user_comments 是 v11 才有的表，而 `createTable` 用的永远是**当前**
        // 的表定义（里面已经有 parent_id / reply_to_name 了）。所以从 v10 及
        // 更早升上来时，上面那个 createTable 已经把这两列建好了，这里再加一次
        // 就是 "duplicate column name"。只有从 v11 升上来时才真的缺这两列。
        if (from >= 11) {
          await m.addColumn(userComments, userComments.parentId);
          await m.addColumn(userComments, userComments.replyToName);
        }
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
