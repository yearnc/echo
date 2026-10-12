import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/model_config_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/relationship_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/domain/models/model_config.dart';
import 'package:echo/domain/services/memory_summarizer.dart';
import 'package:echo/domain/services/model_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryKeyStore implements KeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.reply);

  final Future<ResponseBody> Function(RequestOptions options) reply;

  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls++;
    return reply(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, {int status = 200}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

String _chatReply(String content) => jsonEncode({
  'choices': [
    {
      'message': {'role': 'assistant', 'content': content},
    },
  ],
});

const _config = ModelConfig(
  id: 'm1',
  provider: 'custom',
  label: '测试',
  baseUrl: 'https://example.com/v1',
  model: 'test-model',
  enabled: true,
);

AiPersona _persona(String id) => AiPersona(
  id: id,
  name: '住民$id',
  circle: '摄影',
  personalityType: '温和鼓励型',
);

void main() {
  group('本地兜底那句话', () {
    test('只取第一句', () {
      expect(
        MemorySummarizer.localGist('今天下课后在操场边拍了一张天空照。风很大，但挺好。'),
        '他最近发过：「今天下课后在操场边拍了一张天空照」',
      );
    });

    test('一句话太长就截断', () {
      final gist = MemorySummarizer.localGist('一' * 40);

      expect(gist, '他最近发过：「${'一' * 24}…」');
    });

    test('换行和多余的空格会被压平', () {
      expect(
        MemorySummarizer.localGist('第一行\n   第二行'),
        '他最近发过：「第一行 第二行」',
      );
    });

    test('什么内容都没有时，宁可没得记也别编', () {
      expect(MemorySummarizer.localGist('   '), isNull);
      expect(MemorySummarizer.localGist(''), isNull);
    });
  });

  group('记忆提示词', () {
    test('带上他发过的帖子，也带上这几位分别是谁', () {
      final prompt = MemorySummarizer.memoryPrompt(
        [_persona('persona_001'), _persona('persona_002')],
        ['拍了一张天空照', '在图书馆坐了一下午'],
      );

      expect(prompt, contains('拍了一张天空照'));
      expect(prompt, contains('在图书馆坐了一下午'));
      expect(prompt, contains('住民persona_001'));
      expect(prompt, contains('住民persona_002'));
      expect(prompt, contains('JSON'));
    });
  });

  group('更新记忆', () {
    late AppDatabase db;
    late PostRepository posts;
    late RelationshipRepository relations;
    late ModelConfigRepository configs;
    late Dio dio;
    late MemorySummarizer summarizer;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      posts = PostRepository(db);
      relations = RelationshipRepository(db);
      configs = ModelConfigRepository(db, keyStore: _MemoryKeyStore());
      dio = Dio();
      summarizer = MemorySummarizer(
        db: db,
        posts: posts,
        relationships: relations,
        gateway: ModelGateway(configs, dio: dio),
      );

      // 关系表对 ai_personas 有外键，住民得先在表里
      await db
          .into(db.aiPersonas)
          .insert(
            AiPersonasCompanion.insert(id: 'persona_001', name: '住民一'),
          );
    });

    tearDown(() async => db.close());

    Future<void> enableModel() async {
      await configs.save(_config);
      await configs.setEnabled(_config.id);
      await configs.writeKey(_config.id, 'sk-test');
    }

    test('模型写的那句会存进关系里', () async {
      await enableModel();
      await posts.create(content: '今天下课后在操场边拍了一张天空照', scope: 'echo');
      dio.httpClientAdapter = _FakeAdapter(
        (_) async => _json(_chatReply('[{"index":1,"content":"他拍过一张天空照"}]')),
      );

      final written = await summarizer.refresh(
        personas: [_persona('persona_001')],
      );

      expect(written, 1);
      final state = await relations.load('persona_001');
      expect(state.memorySummary, '他拍过一张天空照');
    });

    test('模型挂了就退回截一句，不往外抛', () async {
      await enableModel();
      await posts.create(content: '今天下课后在操场边拍了一张天空照。风很大。', scope: 'echo');
      dio.httpClientAdapter = _FakeAdapter(
        (_) async => _json('{"error":"boom"}', status: 500),
      );

      final written = await summarizer.refresh(
        personas: [_persona('persona_001')],
      );

      expect(written, 1);
      final state = await relations.load('persona_001');
      expect(state.memorySummary, contains('天空照'));
    });

    test('还没发过帖子就没什么可记的，也不发请求', () async {
      await enableModel();
      final adapter = _FakeAdapter((_) async {
        fail('没有帖子可给，不该发请求');
      });
      dio.httpClientAdapter = adapter;

      final written = await summarizer.refresh(
        personas: [_persona('persona_001')],
      );

      expect(written, 0);
      expect(adapter.calls, 0);
      expect((await relations.load('persona_001')).memorySummary, isEmpty);
    });

    test('十二小时内不会重复记', () async {
      await enableModel();
      await posts.create(content: '拍了一张天空照', scope: 'echo');
      final adapter = _FakeAdapter(
        (_) async => _json(_chatReply('[{"index":1,"content":"他拍过一张天空照"}]')),
      );
      dio.httpClientAdapter = adapter;

      expect(await summarizer.refresh(personas: [_persona('persona_001')]), 1);
      final callsAfterFirst = adapter.calls;

      expect(await summarizer.refresh(personas: [_persona('persona_001')]), 0);
      expect(adapter.calls, callsAfterFirst, reason: '冷却期内不该再问一次模型');
    });

    test('没配模型时用兜底，一次请求也不发', () async {
      await posts.create(content: '在图书馆坐了一下午', scope: 'echo');
      final adapter = _FakeAdapter((_) async {
        fail('没配模型不该发请求');
      });
      dio.httpClientAdapter = adapter;

      final written = await summarizer.refresh(
        personas: [_persona('persona_001')],
      );

      expect(written, 1);
      expect(adapter.calls, 0);
      expect(
        (await relations.load('persona_001')).memorySummary,
        contains('图书馆'),
      );
    });
  });
}
