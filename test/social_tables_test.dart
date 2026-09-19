// drift 和 matcher 都有 isNull / isNotNull，测试里要的是后者的
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// v8 的库长什么样（只留这次迁移会碰到的两张表）。
///
/// 列名与类型照 Drift 生成的 snake_case 写法来。迁移测试的意义就在这里：
/// 拿一个**真的旧结构**去升，而不是拿新结构自欺欺人——`addColumn` 到底能不能
/// 在已有数据的表上跑通，只有这么测才算数。
const String _legacySchema = '''
CREATE TABLE ai_personas (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  avatar TEXT NOT NULL DEFAULT '',
  bio TEXT NOT NULL DEFAULT '',
  language_style TEXT NOT NULL DEFAULT '',
  tone TEXT NOT NULL DEFAULT '',
  active_hours TEXT NOT NULL DEFAULT '[]',
  like_probability REAL NOT NULL DEFAULT 0.5,
  comment_probability REAL NOT NULL DEFAULT 0.4,
  reply_length TEXT NOT NULL DEFAULT 'medium',
  voice_model TEXT NOT NULL DEFAULT '',
  is_active INTEGER NOT NULL DEFAULT 1,
  scope TEXT NOT NULL DEFAULT 'echo',
  level INTEGER NOT NULL DEFAULT 1,
  badges TEXT NOT NULL DEFAULT '[]',
  followers INTEGER NOT NULL DEFAULT 0,
  following INTEGER NOT NULL DEFAULT 0,
  personality_type TEXT NOT NULL DEFAULT '',
  memory_enabled INTEGER NOT NULL DEFAULT 1,
  relationship_level INTEGER NOT NULL DEFAULT 0,
  deleted_at INTEGER
);

CREATE TABLE model_configs (
  id TEXT NOT NULL PRIMARY KEY,
  provider TEXT NOT NULL,
  label TEXT NOT NULL,
  base_url TEXT NOT NULL,
  model TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE posts (
  id TEXT NOT NULL PRIMARY KEY,
  content TEXT NOT NULL DEFAULT '',
  images TEXT NOT NULL DEFAULT '[]',
  created_at INTEGER NOT NULL,
  updated_at INTEGER,
  scope TEXT NOT NULL DEFAULT 'shared',
  is_ai_generated INTEGER NOT NULL DEFAULT 0,
  deleted_at INTEGER,
  topic_id TEXT,
  topic_name TEXT,
  allow_ai_reply INTEGER NOT NULL DEFAULT 1,
  reply_density TEXT,
  like_level TEXT,
  human_level INTEGER,
  is_hot INTEGER NOT NULL DEFAULT 0,
  like_count INTEGER NOT NULL DEFAULT 0,
  comment_count INTEGER NOT NULL DEFAULT 0
);
''';

void main() {
  group('阶段 B 的新表', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async => db.close());

    Future<void> addPersona(String id) => db
        .into(db.aiPersonas)
        .insert(AiPersonasCompanion.insert(id: id, name: '测试住民 $id'));

    test('关系表一行一个住民，档位与记忆都能改', () async {
      await addPersona('persona_001');
      await db
          .into(db.aiRelationships)
          .insert(
            AiRelationshipsCompanion.insert(
              personaId: 'persona_001',
              updatedAt: 100,
            ),
          );

      await (db.update(
        db.aiRelationships,
      )..where((t) => t.personaId.equals('persona_001'))).write(
        const AiRelationshipsCompanion(
          relationshipLevel: Value(2),
          intimacy: Value(30),
          memorySummary: Value('记得你拍过一张天空照'),
        ),
      );

      final row = await db.select(db.aiRelationships).getSingle();
      expect(row.relationshipLevel, 2);
      expect(row.intimacy, 30);
      expect(row.memorySummary, contains('天空照'));
    });

    test('关系表不允许同一住民两行', () async {
      await addPersona('persona_001');
      await db
          .into(db.aiRelationships)
          .insert(
            AiRelationshipsCompanion.insert(
              personaId: 'persona_001',
              updatedAt: 1,
            ),
          );

      expect(
        () => db
            .into(db.aiRelationships)
            .insert(
              AiRelationshipsCompanion.insert(
                personaId: 'persona_001',
                updatedAt: 2,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('私信按住民归档，能标记已读', () async {
      await addPersona('persona_001');
      await db
          .into(db.privateMessages)
          .insert(
            PrivateMessagesCompanion.insert(
              id: 'm1',
              personaId: 'persona_001',
              direction: 'in',
              content: const Value('在吗'),
              createdAt: 1,
            ),
          );

      final unread =
          await (db.select(
            db.privateMessages,
          )..where((t) => t.readAt.isNull())).get();
      expect(unread.length, 1);

      await (db.update(
        db.privateMessages,
      )..where((t) => t.id.equals('m1'))).write(
        const PrivateMessagesCompanion(readAt: Value(2)),
      );

      expect((await db.select(db.privateMessages).getSingle()).readAt, 2);
    });

    test('帖子记得住住民作者；用户自己发的为 null', () async {
      await addPersona('persona_001');
      await db
          .into(db.posts)
          .insert(
            PostsCompanion.insert(
              id: 'p1',
              createdAt: 1,
              authorPersonaId: const Value('persona_001'),
            ),
          );
      await db.into(db.posts).insert(PostsCompanion.insert(id: 'p2', createdAt: 2));

      final byResident =
          await (db.select(
            db.posts,
          )..where((t) => t.id.equals('p1'))).getSingle();
      final byMe =
          await (db.select(db.posts)..where((t) => t.id.equals('p2'))).getSingle();

      expect(byResident.authorPersonaId, 'persona_001');
      expect(byMe.authorPersonaId, isNull);
    });

    test('外键挡得住指向不存在住民的帖子', () async {
      expect(
        () => db
            .into(db.posts)
            .insert(
              PostsCompanion.insert(
                id: 'p3',
                createdAt: 1,
                authorPersonaId: const Value('persona_999'),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('话题能建，热度能改', () async {
      await db
          .into(db.topics)
          .insert(
            TopicsCompanion.insert(
              id: 't1',
              name: '随手拍',
              createdAt: 1,
            ),
          );

      await (db.update(
        db.topics,
      )..where((t) => t.id.equals('t1'))).write(
        const TopicsCompanion(heat: Value(12)),
      );

      final topic = await db.select(db.topics).getSingle();
      expect(topic.name, '随手拍');
      expect(topic.heat, 12);
      expect(topic.isBuiltIn, isFalse);
    });

    test('住民作息按人查得出来，并按钟点排好', () async {
      await addPersona('persona_001');
      await db
          .into(db.personaRoutines)
          .insert(
            PersonaRoutinesCompanion.insert(
              personaId: 'persona_001',
              hour: 20,
              place: const Value('操场'),
            ),
          );
      await db
          .into(db.personaRoutines)
          .insert(
            PersonaRoutinesCompanion.insert(
              personaId: 'persona_001',
              hour: 8,
              place: const Value('食堂'),
            ),
          );

      final rows =
          await (db.select(db.personaRoutines)
                ..where((t) => t.personaId.equals('persona_001'))
                ..orderBy([(t) => OrderingTerm.asc(t.hour)]))
              .get();

      expect(rows.map((row) => row.place), ['食堂', '操场']);
    });
  });

  group('v8 老库升级到最新', () {
    test('老数据原样在，新表与新增的列都能用', () async {
      final raw = sqlite3.openInMemory();
      raw.execute(_legacySchema);
      raw.execute(
        "INSERT INTO ai_personas (id, name) VALUES ('persona_001', '老住民');",
      );
      raw.execute(
        "INSERT INTO posts (id, content, created_at) VALUES ('p1', '老帖子', 100);",
      );
      raw.execute(
        "INSERT INTO model_configs "
        "(id, provider, label, base_url, model, created_at, updated_at) "
        "VALUES ('m1', 'custom', '老配置', 'https://example.com/v1', 'm', 1, 1);",
      );
      raw.execute('PRAGMA user_version = 8;');

      final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
      addTearDown(db.close);

      final post =
          await (db.select(db.posts)..where((t) => t.id.equals('p1'))).getSingle();
      expect(post.content, '老帖子', reason: '迁移不该动老帖子的内容');
      expect(post.authorPersonaId, isNull, reason: '新列的默认值就是"用户发的"');

      final persona = await db.select(db.aiPersonas).getSingle();
      expect(persona.name, '老住民');
      expect(persona.circle, '', reason: '老住民没有圈层，等播种去补');

      // 四张新表都要真的能用，而不只是"建出来了"
      await db
          .into(db.aiRelationships)
          .insert(
            AiRelationshipsCompanion.insert(
              personaId: 'persona_001',
              updatedAt: 1,
            ),
          );
      await db
          .into(db.privateMessages)
          .insert(
            PrivateMessagesCompanion.insert(
              id: 'm1',
              personaId: 'persona_001',
              direction: 'in',
              createdAt: 1,
            ),
          );
      await db
          .into(db.topics)
          .insert(TopicsCompanion.insert(id: 't1', name: '树洞', createdAt: 1));
      await db
          .into(db.personaRoutines)
          .insert(
            PersonaRoutinesCompanion.insert(
              personaId: 'persona_001',
              hour: 9,
            ),
          );

      expect(await db.select(db.aiRelationships).getSingle(), isNotNull);
      expect(await db.select(db.privateMessages).getSingle(), isNotNull);
      expect(await db.select(db.topics).getSingle(), isNotNull);
      expect(await db.select(db.personaRoutines).getSingle(), isNotNull);

      // v10：模型配置分用途了，老配置默认就是"聊天"
      final config = await db.select(db.modelConfigs).getSingle();
      expect(config.label, '老配置');
      expect(config.kind, 'chat');
    });
  });
}
