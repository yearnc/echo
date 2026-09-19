import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/analysis_repository.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/model_config_repository.dart';
import 'package:echo/data/repositories/notification_repository.dart';
import 'package:echo/data/repositories/persona_repository.dart';
import 'package:echo/data/repositories/plan_event_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/domain/models/model_config.dart';
import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/models/resident_post.dart';
import 'package:echo/domain/services/content_generator.dart';
import 'package:echo/domain/services/interaction_planner.dart';
import 'package:echo/domain/services/model_content_generator.dart';
import 'package:echo/domain/services/scheduler_service.dart';
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

AiPersona _persona(
  String id, {
  String name = '',
  List<String> samples = const ['预置台词'],
}) => AiPersona(
  id: id,
  name: name.isEmpty ? '住民$id' : name,
  bio: '简介',
  personalityType: '温和鼓励型',
  languageStyle: '温柔',
  tone: '先接情绪',
  commentSamples: samples,
);

Post _post({String content = '今天下课后在操场边拍了一张天空照'}) =>
    Post(id: 'p1', content: content, createdAt: DateTime(2026, 9, 19));

/// 假的生成器：调度器那条线只关心"它被叫了几次、回来的东西有没有落库"。
class _FakeGenerator implements ContentGenerator {
  Map<String, String> Function(List<AiPersona> personas)? reply;
  Object? error;
  int calls = 0;

  @override
  Future<Map<String, String>> comments({
    required List<AiPersona> personas,
    required Post post,
  }) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return reply?.call(personas) ??
        {for (final persona in personas) persona.id: '模型写的'};
  }

  @override
  Future<List<ResidentPostDraft>> residentPosts({
    required List<ResidentMoment> moments,
  }) async => const [];
}

void main() {
  // 调度器那条线要读 assets 里的住民，rootBundle 需要 binding
  TestWidgetsFlutterBinding.ensureInitialized();

  group('样本生成', () {
    test('从住民自己的台词里挑', () {
      final sample = SampleContentGenerator(random: Random(1));
      final persona = _persona('persona_001', samples: const ['A', 'B', 'C']);

      final picked = sample.forPersona(persona);
      expect(['A', 'B', 'C'], contains(picked));
    });

    test('没有台词的住民也有话说——绝不返回空', () {
      // 空字符串会在评论区渲染成一条空白气泡，那是"这个 APP 坏了"的样子
      final line = SampleContentGenerator().forPersona(
        _persona('p', samples: const []),
      );
      expect(line, isNotEmpty);
      expect(SampleContentGenerator.fallbackLines, contains(line));
    });

    test('批量给结果时人人都有内容', () {
      final result = SampleContentGenerator().commentsFor(
        personas: [
          _persona('a', samples: const ['有']),
          _persona('b', samples: const []),
        ],
      );
      expect(result.keys, containsAll(['a', 'b']));
      expect(result['b'], isNotEmpty);
    });
  });

  group('提示词组装', () {
    test('每个人的编号、身份、语气都在里面', () {
      final prompt = ModelContentGenerator.systemPrompt([
        _persona('persona_001', name: '温柔学姐'),
        _persona('persona_002', name: '老陈的键盘'),
      ]);

      expect(prompt, contains('[1] 温柔学姐'));
      expect(prompt, contains('[2] 老陈的键盘'));
      expect(prompt, contains('温和鼓励型'));
      expect(prompt, contains('先接情绪'));
      expect(prompt, contains('不要提到自己是 AI'));
    });

    test('明确要求返回 JSON 数组，且给了形状', () {
      final prompt = ModelContentGenerator.systemPrompt([_persona('p')]);
      expect(prompt, contains('JSON'));
      expect(prompt, contains('"index"'));
      expect(prompt, contains('"content"'));
    });

    test('帖子提示词带正文；有话题和图时一并说明', () {
      final plain = ModelContentGenerator.postPrompt(_post(content: '正文在这里'));
      expect(plain, contains('正文在这里'));
      expect(plain, isNot(contains('话题')));
      expect(plain, isNot(contains('张图')));

      final rich = ModelContentGenerator.postPrompt(
        Post(
          id: 'p',
          content: '正文',
          createdAt: DateTime(2026, 9, 19),
          topicName: '随手拍',
          images: const ['file:a.jpg', 'file:b.jpg'],
        ),
      );
      expect(rich, contains('#随手拍'));
      expect(rich, contains('2 张图'));
    });
  });

  group('模型回复的解析', () {
    test('标准数组', () {
      final personas = [_persona('persona_001'), _persona('persona_002')];
      final parsed = ModelContentGenerator.parseComments(
        '[{"index":1,"content":"第一条"},{"index":2,"content":"第二条"}]',
        personas,
      );

      expect(parsed['persona_001'], '第一条');
      expect(parsed['persona_002'], '第二条');
    });

    test('包在代码块里也能认出来', () {
      final parsed = ModelContentGenerator.parseComments(
        '```json\n[{"index":1,"content":"好"}]\n```',
        [_persona('persona_001')],
      );
      expect(parsed['persona_001'], '好');
    });

    test('编号越界的丢掉，不硬塞给某个人', () {
      // 把 A 的话挂在 B 名下，比这条没生成出来糟糕得多
      final parsed = ModelContentGenerator.parseComments(
        '[{"index":5,"content":"越界"},{"index":0,"content":"越界"}]',
        [_persona('persona_001')],
      );
      expect(parsed, isEmpty);
    });

    test('内容为空的丢掉', () {
      final parsed = ModelContentGenerator.parseComments(
        '[{"index":1,"content":"   "},{"index":1}]',
        [_persona('persona_001')],
      );
      expect(parsed, isEmpty);
    });

    test('认不出来的一律返回空，不炸', () {
      final personas = [_persona('persona_001')];
      expect(ModelContentGenerator.parseComments('我觉得可以', personas), isEmpty);
      expect(
        ModelContentGenerator.parseComments('[{"index":', personas),
        isEmpty,
      );
      expect(ModelContentGenerator.parseComments('', personas), isEmpty);
    });
  });

  group('内容来源的选路与降级', () {
    late AppDatabase db;
    late ModelConfigRepository repo;
    late Dio dio;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = ModelConfigRepository(db, keyStore: _MemoryKeyStore());
      dio = Dio();
    });

    tearDown(() async => db.close());

    ContentSource buildSource({ModelConfig? config}) {
      final gateway = ModelGateway(repo, dio: dio);
      return ContentSource(
        model: ModelContentGenerator(gateway),
        sample: SampleContentGenerator(random: Random(1)),
        activeConfig: () async => config,
      );
    }

    Future<void> enableModel() async {
      await repo.save(_config);
      await repo.setEnabled(_config.id);
      await repo.writeKey(_config.id, 'sk-test');
    }

    test('没有模型时用样本，一次请求都不发', () async {
      final adapter = _FakeAdapter((_) async {
        fail('没有模型不该发请求');
      });
      dio.httpClientAdapter = adapter;

      final result = await buildSource().comments(
        personas: [_persona('persona_001', samples: const ['预置台词'])],
        post: _post(),
      );

      expect(result['persona_001'], '预置台词');
      expect(adapter.calls, 0);
    });

    test('有模型时模型说了算，它没写的用样本补上', () async {
      await enableModel();
      dio.httpClientAdapter = _FakeAdapter(
        (_) async =>
            _json(_chatReply('[{"index":1,"content":"模型写的这一条"}]')),
      );

      final result = await buildSource(config: _config).comments(
        personas: [
          _persona('persona_001', samples: const ['样本一']),
          _persona('persona_002', samples: const ['样本二']),
        ],
        post: _post(),
      );

      expect(result['persona_001'], '模型写的这一条');
      expect(result['persona_002'], '样本二', reason: '不能因为模型少写一条就留白');
    });

    test('模型报错时整批退回样本', () async {
      await enableModel();
      dio.httpClientAdapter = _FakeAdapter(
        (_) async => _json('{"error":"boom"}', status: 500),
      );

      final result = await buildSource(config: _config).comments(
        personas: [_persona('persona_001', samples: const ['样本一'])],
        post: _post(),
      );

      expect(result['persona_001'], '样本一');
    });

    test('模型返回空数组时也退回样本', () async {
      await enableModel();
      dio.httpClientAdapter = _FakeAdapter(
        (_) async => _json(_chatReply('[]')),
      );

      final result = await buildSource(config: _config).comments(
        personas: [_persona('persona_001', samples: const ['样本一'])],
        post: _post(),
      );

      expect(result['persona_001'], '样本一');
    });

    test('一个人都没有时不发请求', () async {
      final adapter = _FakeAdapter((_) async {
        fail('没有人要评论，不该发请求');
      });
      dio.httpClientAdapter = adapter;

      final result = await buildSource(config: _config).comments(
        personas: const [],
        post: _post(),
      );

      expect(result, isEmpty);
      expect(adapter.calls, 0);
    });
  });

  group('把还没到点的评论换成人写的', () {
    late AppDatabase db;
    late InteractionRepository interactions;
    late PostRepository posts;
    late String postId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      interactions = InteractionRepository(db);
      posts = PostRepository(db);

      for (final id in ['persona_001', 'persona_002']) {
        await db
            .into(db.aiPersonas)
            .insert(AiPersonasCompanion.insert(id: id, name: '住民$id'));
      }
      postId = await posts.create(content: '帖子', scope: 'echo');
    });

    tearDown(() async => db.close());

    /// 一次排一批评论：到点与否由各自的 scheduledAt 决定。
    ///
    /// 必须一次排完——排期的 id 是「帖子 + 序号」，同一条帖子只排一次。
    Future<void> scheduleComments(Map<String, bool> dueByPersona) async {
      await interactions.insertPlanned(postId, [
        for (final entry in dueByPersona.entries)
          PlannedInteraction(
            personaId: entry.key,
            type: 'comment',
            content: '预置台词',
            scheduledAt: DateTime.now().add(
              entry.value
                  ? const Duration(seconds: -5)
                  : const Duration(hours: 3),
            ),
          ),
      ]);
    }

    test('只换还没兑现的那几条', () async {
      await scheduleComments({'persona_001': false, 'persona_002': true});
      // 把 persona_002 那条兑现掉——用户已经能看见它了
      final dueItems = await interactions.duePending(DateTime.now());
      await interactions.markExecuted(dueItems.single.id);

      final updated = await interactions.updatePendingComments(postId, {
        'persona_001': '模型写的这条',
        'persona_002': '不该被换掉的那条',
      });

      expect(updated, 1, reason: '已兑现的不该被改写');

      final all = await db.select(db.aiInteractions).get();
      final pending = all.firstWhere((row) => row.personaId == 'persona_001');
      final executed = all.firstWhere((row) => row.personaId == 'persona_002');

      expect(pending.content, '模型写的这条');
      expect(executed.content, '预置台词', reason: '评论在眼皮底下变一次很怪');
    });

    test('已经兑现的不算待换的', () async {
      await scheduleComments({'persona_001': false, 'persona_002': true});
      final dueItems = await interactions.duePending(DateTime.now());
      await interactions.markExecuted(dueItems.single.id);

      final pending = await interactions.pendingCommentPersonaIds(postId);

      expect(
        pending,
        ['persona_001'],
        reason: '到点但还没兑现的也要换——改写要赶在它送到用户眼前之前',
      );
    });

    test('空 map 不做事，也不把已有内容抹掉', () async {
      await scheduleComments({'persona_001': false});

      expect(await interactions.updatePendingComments(postId, const {}), 0);

      final row = await db.select(db.aiInteractions).getSingle();
      expect(row.content, '预置台词');
    });
  });

  group('发帖后把评论交给模型', () {
    late AppDatabase db;
    late PostRepository posts;
    late InteractionRepository interactions;
    late _FakeGenerator generator;
    late SchedulerService scheduler;
    late String postId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      posts = PostRepository(db);
      interactions = InteractionRepository(db);
      generator = _FakeGenerator();

      for (final id in ['persona_001', 'persona_002']) {
        await db
            .into(db.aiPersonas)
            .insert(AiPersonasCompanion.insert(id: id, name: '住民$id'));
      }

      scheduler = SchedulerService(
        interactions: interactions,
        planEvents: PlanEventRepository(db),
        posts: posts,
        notifications: NotificationRepository(db),
        personas: const PersonaRepository(),
        analyses: AnalysisRepository(db),
        generator: generator,
      );

      postId = await posts.create(content: '帖子', scope: 'echo');
    });

    tearDown(() async => db.close());

    Future<void> scheduleComments(Map<String, bool> dueByPersona) async {
      await interactions.insertPlanned(postId, [
        for (final entry in dueByPersona.entries)
          PlannedInteraction(
            personaId: entry.key,
            type: 'comment',
            content: '预置台词',
            scheduledAt: DateTime.now().add(
              entry.value
                  ? const Duration(seconds: -5)
                  : const Duration(hours: 3),
            ),
          ),
      ]);
    }

    test('把还没兑现的评论换成模型写的', () async {
      await scheduleComments({'persona_001': false});

      await scheduler.upgradeCommentsWithModel(postId);

      final row = await db.select(db.aiInteractions).getSingle();
      expect(row.content, '模型写的');
      expect(generator.calls, 1, reason: '整批一次请求，不逐条调用');
    });

    test('已经兑现的不动', () async {
      await scheduleComments({'persona_001': false, 'persona_002': true});
      final dueItems = await interactions.duePending(DateTime.now());
      await interactions.markExecuted(dueItems.single.id);

      await scheduler.upgradeCommentsWithModel(postId);

      final all = await db.select(db.aiInteractions).get();
      final executed = all.firstWhere((row) => row.personaId == 'persona_002');
      expect(executed.content, '预置台词');
    });

    test('模型写挂了就保持预置台词，不往外抛', () async {
      generator.error = Exception('boom');
      await scheduleComments({'persona_001': false});

      // 这一步失败不该让调用方（发布流程）看见异常
      await scheduler.upgradeCommentsWithModel(postId);

      final row = await db.select(db.aiInteractions).getSingle();
      expect(row.content, '预置台词');
    });

    test('没有待兑现的评论就不发请求', () async {
      await scheduler.upgradeCommentsWithModel(postId);

      expect(generator.calls, 0);
    });

    test('帖子不存在时安静收场', () async {
      await scheduleComments({'persona_001': false});

      await scheduler.upgradeCommentsWithModel('不存在的帖子');

      expect(generator.calls, 0);
    });
  });
}
