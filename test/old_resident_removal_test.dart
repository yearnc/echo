import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// v8 的库长什么样（只留迁移会碰到的表）。
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

CREATE TABLE real_actions (
  id TEXT NOT NULL PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  deleted_at INTEGER,
  scope TEXT NOT NULL DEFAULT 'clear'
);
''';

void main() {
  test('v37 把旧住民的表清掉，用户自己的帖子原样保留', () async {
    final raw = sqlite3.openInMemory();
    raw.execute(_legacySchema);
    raw.execute(
      "INSERT INTO ai_personas (id, name) VALUES ('persona_001', '老住民');",
    );
    raw.execute(
      "INSERT INTO posts (id, content, created_at) "
      "VALUES ('my_post', '我自己的帖子', 200);",
    );
    raw.execute('PRAGMA user_version = 8;');

    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final rows = await db.select(db.posts).get();
    expect(rows.map((row) => row.id), ['my_post']);

    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = tables.map((row) => row.read<String>('name')).toSet();
    expect(names, isNot(contains('ai_personas')));
    expect(names, isNot(contains('ai_relationships')));
    expect(names, isNot(contains('persona_routines')));
  });
}
