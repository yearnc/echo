import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/action_tables.dart';
import 'tables/ai_tables.dart';
import 'tables/clear_tables.dart';
import 'tables/content_tables.dart';
import 'tables/log_tables.dart';
import 'tables/media_tables.dart';
import 'tables/model_tables.dart';
import 'tables/plan_tables.dart';
import 'tables/resident_tables.dart';
import 'tables/social_tables.dart';
import 'tables/understanding_tables.dart';
import 'tables/voice_tables.dart';

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
    AiInteractions,
    PrivateMessages,
    UserComments,
    CommentLikes,
    Topics,
    AnalysisResults,
    ModeSwitchLogs,
    NotificationLogs,
    FeedbackViewLogs,
    Stickers,
    CustomAvatars,
    PlanScripts,
    PlanEvents,
    ModelConfigs,
    ValueClarifications,
    RealActions,
    AddictionLogs,
    PostVoices,
    AiThreads,
    PostViews,
    PostUnderstandings,
    CustomResidents,
    ResidentMemories,
    ResidentWakeLogs,
    ResidentInboxItems,
    ActionLogs,
    ClearPhotos,
    ClearInsights,
    UsageSessions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 测试用：传入内存执行器，避免碰真实文件。
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 42;

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
        // ai_personas 在 v37 整体下线；这里不再重建它。
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
        await m.createTable(privateMessages);
        await m.createTable(topics);
        // v9 曾经给 posts 加过 author_persona_id；旧住民在 v37 整套下线，
        // 新库不再创建这一列。
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
      if (from < 13) {
        // v13：真实行动可以顺手记一下当时的心情（B11 的周报情绪维度）。
        // 老记录一律是空字符串 = 没记，不补、不猜——替用户编心情，
        // 那这张周报就没有一句是真的了。
        await m.addColumn(realActions, realActions.mood);
      }
      if (from < 14) {
        // v14：v3.0 的网民身份与上下文层。
        // 只新增，不动旧表：老的 ai_personas / ai_interactions 继续可读。
        await m.createTable(postVoices);
        await m.createTable(aiThreads);
        await m.createTable(postViews);
      }
      if (from < 15) {
        // v15：临时网民的 id 也要能写进 ai_interactions。
        // 老表把 persona_id 外键到了 ai_personas，SQLite 不能直接删外键，
        // 只能重建表再搬数据。列清单与 Drift 当前定义保持一致。
        //
        // 老到连 ai_interactions 都还没建出来的库（升级测试里有这种）
        // 直接跳过：后面的 createTable 会按新定义把它建好。
        final hasInteractions = await customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'ai_interactions'",
        ).getSingleOrNull();
        if (hasInteractions != null) {
        await customStatement('''
          CREATE TABLE ai_interactions_v15 (
            id TEXT NOT NULL,
            post_id TEXT NOT NULL REFERENCES posts (id),
            persona_id TEXT NOT NULL,
            type TEXT NOT NULL,
            media_type TEXT NULL,
            content TEXT NULL,
            voice_path TEXT NULL,
            transcript TEXT NULL,
            voice_duration_ms INTEGER NULL,
            scheduled_at INTEGER NOT NULL,
            executed_at INTEGER NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            is_ai INTEGER NOT NULL DEFAULT 1 CHECK (is_ai IN (0, 1)),
            scope TEXT NOT NULL DEFAULT 'echo',
            parent_id TEXT NULL,
            like_count INTEGER NOT NULL DEFAULT 0,
            deleted_at INTEGER NULL,
            PRIMARY KEY (id)
          )
        ''');
        await customStatement('''
          INSERT INTO ai_interactions_v15 (
            id, post_id, persona_id, type, media_type, content, voice_path,
            transcript, voice_duration_ms, scheduled_at, executed_at, status,
            is_ai, scope, parent_id, like_count, deleted_at
          )
          SELECT
            id, post_id, persona_id, type, media_type, content, voice_path,
            transcript, voice_duration_ms, scheduled_at, executed_at, status,
            is_ai, scope, parent_id, like_count, deleted_at
          FROM ai_interactions
        ''');
        await customStatement('DROP TABLE ai_interactions');
        await customStatement(
          'ALTER TABLE ai_interactions_v15 RENAME TO ai_interactions',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS ai_interactions_lookup '
          'ON ai_interactions (post_id, persona_id, status)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS ai_interactions_scheduled '
          'ON ai_interactions (scheduled_at)',
        );
        }
      }
      if (from < 16) {
        // v16：帖子解析层。先看懂，再让网民说话。
        await m.createTable(postUnderstandings);
      }
      if (from < 17) {
        // v17：互动来源。AI 之间的接话不该给用户弹通知，
        // 光看 parent_id 分不出“接用户”还是“接 AI”。
        // 和 v15 一样：老到还没建 ai_interactions 的库直接跳过。
        final hasInteractions = await customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'ai_interactions'",
        ).getSingleOrNull();
        if (hasInteractions != null) {
          await m.addColumn(aiInteractions, aiInteractions.source);
        }
      }
      if (from < 18) {
        // v18：评论曾经被排期时的 likeBatch 默认值凑了一个“自带赞”，
        // 把旧行上的这个假数字清掉。评论真正的赞走 comment_likes。
        final hasInteractions = await customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'ai_interactions'",
        ).getSingleOrNull();
        if (hasInteractions != null) {
          await customStatement(
            "UPDATE ai_interactions SET like_count = 0 WHERE type = 'comment'",
          );
        }
      }
      if (from < 19) {
        // v19：评论的赞要分“谁点的”。原来主键只有 comment_id，
        // 一个评论只能有一行，AI 和用户会互相顶掉。重建表加 actor。
        final hasLikes = await customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'comment_likes'",
        ).getSingleOrNull();
        if (hasLikes != null) {
          await customStatement('''
            CREATE TABLE comment_likes_v19 (
              comment_id TEXT NOT NULL,
              actor_kind TEXT NOT NULL DEFAULT 'user',
              actor_id TEXT NOT NULL DEFAULT '',
              created_at INTEGER NOT NULL,
              PRIMARY KEY (comment_id, actor_kind, actor_id)
            )
          ''');
          await customStatement('''
            INSERT INTO comment_likes_v19 (
              comment_id, actor_kind, actor_id, created_at
            )
            SELECT comment_id, 'user', '', created_at FROM comment_likes
          ''');
          await customStatement('DROP TABLE comment_likes');
          await customStatement(
            'ALTER TABLE comment_likes_v19 RENAME TO comment_likes',
          );
        }
      }
      if (from < 20) {
        // v20：固定住民与长期记忆的数据底座。
        await m.createTable(customResidents);
        await m.createTable(residentMemories);
        // 从 v14 及更早升上来时，post_voices 是 v14 才建的：
        // 那时用的已经是当前定义（带 resident_id），不能再加一次。
        if (from >= 14) {
          await m.addColumn(postVoices, postVoices.residentId);
        }
      }
      if (from < 21) {
        // v21：固定住民的设定按酒馆角色卡的结构拆开。
        // 从 v20 及更早升上来时，表是 v20 才建的——那时用的已经是
        // 当前定义（带这些列），不能再加一次。
        if (from >= 20) {
          await m.addColumn(customResidents, customResidents.description);
          await m.addColumn(customResidents, customResidents.personality);
          await m.addColumn(customResidents, customResidents.scenario);
          await m.addColumn(customResidents, customResidents.exampleDialogue);
          await m.addColumn(
            customResidents,
            customResidents.extraInstructions,
          );
          await m.addColumn(customResidents, customResidents.tags);
        }
      }
      if (from < 22) {
        // v22：固定住民自己也能发动态、也能私信了。
        await m.addColumn(posts, posts.authorResidentId);

        // AI 的楼中楼回复也要记得自己在回谁。
        final hasInteractionsForReply = await customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'ai_interactions'",
        ).getSingleOrNull();
        if (hasInteractionsForReply != null) {
          await m.addColumn(aiInteractions, aiInteractions.replyToName);
        }

        // private_messages.persona_id 原来外键指着 ai_personas，固定住民的 id
        // 插不进去。会话对象现在可能是旧住民、也可能是固定住民，
        // 只能去掉外键；两张表的 id 由各自的生成器保证唯一。
        final hasMessages = await customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'private_messages'",
        ).getSingleOrNull();
        if (hasMessages != null) {
          await customStatement('''
            CREATE TABLE private_messages_v22 (
              id TEXT NOT NULL,
              persona_id TEXT NOT NULL,
              direction TEXT NOT NULL,
              content TEXT NOT NULL DEFAULT '',
              media_type TEXT NOT NULL DEFAULT 'text',
              voice_path TEXT NULL,
              transcript TEXT NULL,
              created_at INTEGER NOT NULL,
              read_at INTEGER NULL,
              deleted_at INTEGER NULL,
              scope TEXT NOT NULL DEFAULT 'echo',
              PRIMARY KEY (id)
            )
          ''');
          await customStatement('''
            INSERT INTO private_messages_v22 (
              id, persona_id, direction, content, media_type, voice_path,
              transcript, created_at, read_at, deleted_at, scope
            )
            SELECT
              id, persona_id, direction, content, media_type, voice_path,
              transcript, created_at, read_at, deleted_at, scope
            FROM private_messages
          ''');
          await customStatement('DROP TABLE private_messages');
          await customStatement(
            'ALTER TABLE private_messages_v22 RENAME TO private_messages',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS private_messages_persona '
            'ON private_messages (persona_id)',
          );
        }
      }
      if (from < 23) {
        // v23：动作账本。工具调用、批量围观、被动触发都从这里过一遍，
        // 幂等键保证同一句话不会被模型重复发两次。
        await m.createTable(actionLogs);
      }
      if (from < 24) {
        // v24：身份资料、表情包标签、图片理解、评论区表情包。
        //
        // 统一的加列方式先查 PRAGMA：从很老的版本升上来时，某些表是
        // 在后续迁移里按**当前定义**新建的，直接 addColumn 会撞
        // "duplicate column name"（v12 已经踩过一次）。
        Future<bool> hasTable(String table) async {
          final row = await customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name = ?",
            variables: [Variable<String>(table)],
          ).getSingleOrNull();
          return row != null;
        }

        Future<bool> hasColumn(String table, String column) async {
          if (!await hasTable(table)) return false;
          final rows = await customSelect('PRAGMA table_info($table)').get();
          return rows.any((row) => row.read<String>('name') == column);
        }

        Future<void> addTextColumn(String table, String column) async {
          if (!await hasTable(table)) return;
          if (!await hasColumn(table, column)) {
            await customStatement(
              "ALTER TABLE $table ADD COLUMN $column TEXT NOT NULL DEFAULT ''",
            );
          }
        }

        for (final column in const [
          'gender',
          'age_range',
          'occupation',
          'city',
          'interests',
          'preferred_name',
          'intro',
        ]) {
          await addTextColumn('user_profile', column);
        }
        await addTextColumn('user_comments', 'media_type');
        await addTextColumn('stickers', 'tags');
        await addTextColumn('post_understandings', 'image_summary');

        if (!await hasColumn('model_configs', 'supports_vision')) {
          await customStatement(
            'ALTER TABLE model_configs ADD COLUMN supports_vision '
            'INTEGER NOT NULL DEFAULT 0',
          );
        }

        // post_views 原来把 voice_id 外键到 post_voices，导致"我自己"
        // 的浏览记录写不进去。SQLite 不能直接删外键，只能重建。
        // 只处理 v14 及以后真的带着旧外键建出来的表；更老的库会在
        // v14 那一步按当前定义新建，不需要再动。
        if (from >= 14) {
          await customStatement('''
            CREATE TABLE post_views_v24 (
              id TEXT NOT NULL,
              post_id TEXT NOT NULL REFERENCES posts (id),
              voice_id TEXT NOT NULL,
              first_viewed_at INTEGER NOT NULL,
              last_viewed_at INTEGER NOT NULL,
              view_count INTEGER NOT NULL DEFAULT 1,
              PRIMARY KEY (id),
              UNIQUE (post_id, voice_id)
            )
          ''');
          await customStatement('''
            INSERT INTO post_views_v24 (
              id, post_id, voice_id, first_viewed_at, last_viewed_at, view_count
            )
            SELECT id, post_id, voice_id, first_viewed_at, last_viewed_at,
                   view_count
            FROM post_views
          ''');
          await customStatement('DROP TABLE post_views');
          await customStatement(
            'ALTER TABLE post_views_v24 RENAME TO post_views',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS post_views_by_post '
            'ON post_views (post_id, last_viewed_at)',
          );
        }
      }
      if (from < 25) {
        // v25：评论可以“图 + 一句话”。以前一条评论只有一个 content，
        // 发图就得把输入框里的文字丢掉；caption 专门放那句话。
        final hasUserComments = await customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'user_comments'",
        ).getSingleOrNull();
        if (hasUserComments != null) {
          final columns = await customSelect(
            'PRAGMA table_info(user_comments)',
          ).get();
          final hasCaption = columns.any(
            (row) => row.read<String>('name') == 'caption',
          );
          if (!hasCaption) {
            await customStatement(
              "ALTER TABLE user_comments ADD COLUMN caption "
              "TEXT NOT NULL DEFAULT ''",
            );
          }
        }
      }
      if (from < 26) {
        // v26：点赞通知合并。同一条帖子只留一行，人数累加。
        final hasNotifications = await customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'notification_logs'",
        ).getSingleOrNull();
        if (hasNotifications != null) {
          final columns = await customSelect(
            'PRAGMA table_info(notification_logs)',
          ).get();
          final names = columns
              .map((row) => row.read<String>('name'))
              .toSet();
          if (!names.contains('group_key')) {
            await customStatement(
              "ALTER TABLE notification_logs ADD COLUMN group_key "
              "TEXT NOT NULL DEFAULT ''",
            );
          }
          if (!names.contains('actor_count')) {
            await customStatement(
              'ALTER TABLE notification_logs ADD COLUMN actor_count '
              'INTEGER NOT NULL DEFAULT 1',
            );
          }
          if (!names.contains('actor_names')) {
            await customStatement(
              "ALTER TABLE notification_logs ADD COLUMN actor_names "
              "TEXT NOT NULL DEFAULT ''",
            );
          }
        }
      }
      if (from < 27) {
        // v27：固定住民的收件箱。唤醒式交互靠它记住
        // “这条看过没有、怎么处理的”——没有它，“已读不回”会永远算待办。
        await m.createTable(residentInboxItems);
      }
      if (from < 28) {
        // v28：用户导入的网友头像池。临时网民优先从这里挑头像。
        await m.createTable(customAvatars);
      }
      if (from < 29) {
        // v29：把旧私信记忆的来源改对。
        //
        // v3.3 之前 `rememberUserReply` 把来源写死成 comment，于是私信内容
        // 在记忆页显示“来自评论”。当时私信调用的 sourceId 是 `reply_<时间>`
        // （评论回复传的是评论 id，不是这个格式），所以能可靠区分并回填。
        final hasMemories = await customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'resident_memories'",
        ).getSingleOrNull();
        if (hasMemories != null) {
          await customStatement(
            "UPDATE resident_memories SET source = 'dm', "
            "summary = REPLACE(summary, '他回我：', '他私信你：') "
            "WHERE source = 'comment' AND source_id LIKE 'reply_%'",
          );
        }
      }
      if (from < 30) {
        // v30：固定住民可以单独指定对话模型。
        // 用户可能给不同人设配不同的模型（一个人用便宜快的，一个人用会写长文的），
        // 空值表示沿用“当前启用的那条”，所以加一列默认空即可。
        final hasResidents = await customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'custom_residents'",
        ).getSingleOrNull();
        if (hasResidents != null) {
          final columns = await customSelect(
            'PRAGMA table_info(custom_residents)',
          ).get();
          final names = columns.map((row) => row.read<String>('name')).toSet();
          if (!names.contains('model_config_id')) {
            await customStatement(
              "ALTER TABLE custom_residents ADD COLUMN model_config_id "
              "TEXT NOT NULL DEFAULT ''",
            );
          }
        }
      }
      if (from < 31) {
        // v31：清醒侧的数据底座。
        // - 相册：只存用户主动选的照片，scope=clear；
        // - 分析快照：按维度落库，带生成区间与来源；
        // - 使用会话：支撑“今日用了多久”和用户自设的上限。
        await m.createTable(clearPhotos);
        await m.createTable(clearInsights);
        await m.createTable(usageSessions);
      }
      // v32 曾经建过群聊两张表；该功能已在 v34 下线，这里不再创建。
      // 老库里留下的表会由 v34 的 DROP IF EXISTS 清掉。
      if (from < 33) {
        // v33：删固定住民不再连带删私信。把 v3.6.1 那版级联软删的对话
        // 恢复回来——私信没有别的软删入口，所以这里可以安全地全部恢复。
        // v9 之前根本没有这张表，先确认它存在。
        final hasPrivateMessages = await customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'private_messages'",
        ).getSingleOrNull();
        if (hasPrivateMessages != null) {
          await customStatement(
            'UPDATE private_messages SET deleted_at = NULL '
            'WHERE deleted_at IS NOT NULL',
          );
        }
      }
      if (from < 34) {
        // v34：群聊功能下线。v32 建的两张表在这里删掉——
        // 历史迁移链保持原样（老库升上来会先建再删），新库则完全不建。
        await customStatement('DROP TABLE IF EXISTS group_messages');
        await customStatement('DROP TABLE IF EXISTS group_chats');
      }
      // 旧迁移里有些表是用**当前**定义重新建的，重建出来就已经带了新列。
      // 所以补列之前不只要确认表在，还要确认列不在——否则会 duplicate column。
      Future<bool> hasTable(String name) async {
        final row = await customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = ?",
          variables: [Variable<String>(name)],
        ).getSingleOrNull();
        return row != null;
      }

      Future<bool> hasColumn(String table, String column) async {
        final rows = await customSelect('PRAGMA table_info("$table")').get();
        return rows.any((row) => row.read<String>('name') == column);
      }

      if (from < 35) {
        // v35：图片/表情包的语义要传给住民。
        // - 私信：记录图片描述或表情包的名字、标签；
        // - AI 评论：表情包 + 一句话可以同时存在，不再二选一。
        if (await hasTable('private_messages') &&
            !await hasColumn('private_messages', 'caption')) {
          await m.addColumn(privateMessages, privateMessages.caption);
        }
        if (await hasTable('ai_interactions') &&
            !await hasColumn('ai_interactions', 'caption')) {
          await m.addColumn(aiInteractions, aiInteractions.caption);
        }
      }
      if (from < 36) {
        // v36：每个固定住民的音色。默认不说语音，用户自己开。
        if (await hasTable('custom_residents')) {
          for (final entry in <String, GeneratedColumn>{
            'voice_enabled': customResidents.voiceEnabled,
            'voice_description': customResidents.voiceDescription,
            'voice_sample_path': customResidents.voiceSamplePath,
            'voice_sample_text': customResidents.voiceSampleText,
            'voice_ref': customResidents.voiceRef,
          }.entries) {
            if (!await hasColumn('custom_residents', entry.key)) {
              await m.addColumn(customResidents, entry.value);
            }
          }
        }
      }
      if (from < 37) {
        // v37：旧住民整套下线。
        //
        // 他们不是“用户配置的人”，而是阶段 A 从 assets 播种的 32 位旧住民。
        // 从此以后社区只由固定住民 + 临时网民组成。旧住民的账号、帖子、
        // 评论、私信、关系、作息全部清掉，不给 UI 留孤儿数据。
        final hasPersonas = await hasTable('ai_personas');
        final hasPosts = await hasTable('posts');
        final hasInteractions = await hasTable('ai_interactions');
        final hasPostVoices = await hasTable('post_voices');
        final hasUserComments = await hasTable('user_comments');
        final hasCommentLikes = await hasTable('comment_likes');
        final hasPostViews = await hasTable('post_views');
        final hasNotifications = await hasTable('notification_logs');
        final hasPlanEvents = await hasTable('plan_events');
        final hasActionLogs = await hasTable('action_logs');
        final hasPrivateMessages = await hasTable('private_messages');
        final hasUnderstandings = await hasTable('post_understandings');
        final hasThreads = await hasTable('ai_threads');
        final hasPostsAuthor = hasPosts &&
            await hasColumn('posts', 'author_persona_id');

        // 1. 旧住民留下的评论/互动（先删孩子，再删帖子）。
        if (hasInteractions) {
          if (hasPersonas) {
            await customStatement(
              'DELETE FROM ai_interactions WHERE persona_id IN '
              '(SELECT id FROM ai_personas)',
            );
          }
          if (hasPostVoices) {
            await customStatement(
              "DELETE FROM ai_interactions WHERE persona_id IN "
              "(SELECT id FROM post_voices WHERE kind = 'builtin')",
            );
          }
          if (hasPostsAuthor) {
            await customStatement(
              'DELETE FROM ai_interactions WHERE post_id IN '
              '(SELECT id FROM posts WHERE author_persona_id IS NOT NULL)',
            );
          }
        }

        // 2. 旧帖子的浏览量、评论、通知、解析、线程、身份快照。
        if (hasPostsAuthor) {
          if (hasPostViews) {
            await customStatement(
              'DELETE FROM post_views WHERE post_id IN '
              '(SELECT id FROM posts WHERE author_persona_id IS NOT NULL)',
            );
            if (hasPostVoices) {
              await customStatement(
                "DELETE FROM post_views WHERE voice_id IN "
                "(SELECT id FROM post_voices WHERE kind = 'builtin')",
              );
            }
          }
          if (hasUserComments) {
            await customStatement(
              'DELETE FROM user_comments WHERE post_id IN '
              '(SELECT id FROM posts WHERE author_persona_id IS NOT NULL)',
            );
          }
          if (hasNotifications) {
            await customStatement(
              'DELETE FROM notification_logs WHERE post_id IN '
              '(SELECT id FROM posts WHERE author_persona_id IS NOT NULL)',
            );
          }
          if (hasUnderstandings) {
            await customStatement(
              'DELETE FROM post_understandings WHERE post_id IN '
              '(SELECT id FROM posts WHERE author_persona_id IS NOT NULL)',
            );
          }
          if (hasThreads) {
            await customStatement(
              'DELETE FROM ai_threads WHERE post_id IN '
              '(SELECT id FROM posts WHERE author_persona_id IS NOT NULL)',
            );
          }
          if (hasPostVoices) {
            await customStatement(
              'DELETE FROM post_voices WHERE post_id IN '
              '(SELECT id FROM posts WHERE author_persona_id IS NOT NULL)',
            );
          }
          if (hasInteractions) {
            await customStatement(
              'DELETE FROM ai_interactions WHERE post_id IN '
              '(SELECT id FROM posts WHERE author_persona_id IS NOT NULL)',
            );
          }
        }

        // 3. 旧住民的身份快照、私信、策划事件、动作日志。
        if (hasPostVoices) {
          await customStatement(
            "DELETE FROM post_voices WHERE kind = 'builtin'",
          );
        }
        if (hasPrivateMessages && hasPersonas) {
          await customStatement(
            'DELETE FROM private_messages WHERE persona_id IN '
            '(SELECT id FROM ai_personas)',
          );
        }
        if (hasPlanEvents && hasPersonas) {
          await customStatement(
            'DELETE FROM plan_events WHERE persona_id IN '
            '(SELECT id FROM ai_personas)',
          );
        }
        if (hasActionLogs && hasPersonas) {
          await customStatement(
            'DELETE FROM action_logs WHERE actor_id IN '
            '(SELECT id FROM ai_personas)',
          );
        }

        // 4. 删掉旧住民发的帖子本身。
        if (hasPostsAuthor) {
          await customStatement(
            'DELETE FROM posts WHERE author_persona_id IS NOT NULL',
          );
        }

        // 5. 评论的赞只保留还存在的评论。
        if (hasCommentLikes && hasInteractions) {
          final keepUserComments = hasUserComments
              ? ' AND comment_id NOT IN (SELECT id FROM user_comments)'
              : '';
          await customStatement(
            'DELETE FROM comment_likes WHERE comment_id NOT IN '
            '(SELECT id FROM ai_interactions)$keepUserComments',
          );
        }

        // 6. posts 去掉 author_persona_id（连外键一起），再删旧表。
        if (hasPostsAuthor) {
          await m.alterTable(TableMigration(posts));
        }
        await customStatement('DROP TABLE IF EXISTS ai_relationships');
        await customStatement('DROP TABLE IF EXISTS persona_routines');
        await customStatement('DROP TABLE IF EXISTS ai_personas');
      }
      if (from < 38) {
        // v38：「每帖必到」拆掉，两个 always_show 列一起下线。
        // 用 alterTable 重建，数据原样保留，只少这一列。
        //
        // ⚠️ alterTable 用的是**当前**表定义：它会把现有列原样 SELECT 过去。
        // 从更老的库（v13 之类）一路升上来时，v41 才加的 voice_mode 还没建，
        // 重建就会报 "no such column: voice_mode"。所以这里先把以后才会加、
        // 但重建时会被引用的列补上；v41 那段有 hasColumn 守卫，不会重复加。
        if (await hasTable('custom_residents') &&
            !await hasColumn('custom_residents', 'voice_mode')) {
          await m.addColumn(customResidents, customResidents.voiceMode);
        }
        if (await hasTable('custom_residents')) {
          await m.alterTable(TableMigration(customResidents));
        }
        if (await hasTable('post_voices')) {
          await m.alterTable(TableMigration(postVoices));
        }
      }
      if (from < 39) {
        // v39：固定住民的两个半废弃字段（first_message / active_hours）
        // 一起下线；它们不再参与提示词或唤醒。
        if (await hasTable('custom_residents')) {
          await m.alterTable(TableMigration(customResidents));
        }
      }
      if (from < 40) {
        // v40：内置策划脚本还是旧住民的内容资产，整套清掉。
        // 用户自己建的脚本（is_built_in = 0）不动。
        if (await hasTable('plan_events') && await hasTable('plan_scripts')) {
          await customStatement(
            'DELETE FROM plan_events WHERE script_id IN '
            '(SELECT id FROM plan_scripts WHERE is_built_in = 1)',
          );
        }
        if (await hasTable('plan_scripts')) {
          await customStatement(
            'DELETE FROM plan_scripts WHERE is_built_in = 1',
          );
        }
      }
      if (from < 41) {
        // v41：
        // - 私信分段可打断：一次唤醒写出的几段带同一个 group，未到点的段
        //   可以被下一轮取消或改写；
        // - 语音模型的音色能力（四种配置方式）；
        // - 每位住民选的是哪一种方式。
        if (await hasTable('private_messages')) {
          for (final entry in <String, GeneratedColumn>{
            'delivery_group': privateMessages.deliveryGroup,
            'delivery_index': privateMessages.deliveryIndex,
            'delivery_state': privateMessages.deliveryState,
          }.entries) {
            if (!await hasColumn('private_messages', entry.key)) {
              await m.addColumn(privateMessages, entry.value);
            }
          }
        }
        if (await hasTable('model_configs')) {
          for (final entry in <String, GeneratedColumn>{
            'tts_voice_description': modelConfigs.ttsVoiceDescription,
            'tts_reference_only': modelConfigs.ttsReferenceOnly,
            'tts_reference_description': modelConfigs.ttsReferenceDescription,
            'tts_reference_transcript': modelConfigs.ttsReferenceTranscript,
          }.entries) {
            if (!await hasColumn('model_configs', entry.key)) {
              await m.addColumn(modelConfigs, entry.value);
            }
          }
        }
        if (await hasTable('custom_residents') &&
            !await hasColumn('custom_residents', 'voice_mode')) {
          await m.addColumn(customResidents, customResidents.voiceMode);
        }
      }
      if (from < 42) {
        // v42：固定住民的唤醒日志 + 给未来自己的留言。
        if (!await hasTable('resident_wake_logs')) {
          await m.createTable(residentWakeLogs);
        }
      }
    },
  );
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'echo.sqlite'));
    return NativeDatabase.createInBackground(
      file,
      setup: (db) {
        // 后台 isolate（WorkManager）和前台可能同时打开同一个库。
        // 默认的 busy_timeout 是 0：撞上锁会立刻抛 SQLITE_BUSY，
        // 冷启动就变成“开库失败，退出重进又好了”。给锁一点耐心。
        db.execute('PRAGMA busy_timeout = 15000');
        // WAL 让读写互不阻塞，两个进程同时在线时也不会因为写锁互相等死。
        db.execute('PRAGMA journal_mode = WAL');
        db.execute('PRAGMA synchronous = NORMAL');
      },
    );
  });
}
