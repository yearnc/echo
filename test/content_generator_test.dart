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
import 'package:echo/data/repositories/relationship_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/domain/models/model_config.dart';
import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/models/post_understanding.dart';
import 'package:echo/domain/models/resident_post.dart';
import 'package:echo/domain/services/content_generator.dart';
import 'package:echo/domain/services/interaction_planner.dart';
import 'package:echo/domain/services/model_content_generator.dart';
import 'package:echo/domain/services/relationship_rules.dart';
import 'package:echo/domain/services/scheduler_service.dart';
import 'package:echo/domain/services/model_call_common.dart';
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
  bool memoryEnabled = true,
}) => AiPersona(
  id: id,
  name: name.isEmpty ? '住民$id' : name,
  bio: '简介',
  personalityType: '温和鼓励型',
  languageStyle: '温柔',
  tone: '先接情绪',
  memoryEnabled: memoryEnabled,
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
    Map<String, RelationshipState> relations = const {},
    PostUnderstanding? understanding,
    bool sendImagesDirectly = false,
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

  @override
  Future<Map<String, String>> directMessages({
    required List<DirectThread> threads,
    Map<String, RelationshipState> relations = const {},
  }) async => {
    for (final thread in threads) thread.persona.id: '模型写的私信',
  };

  @override
  Future<Map<String, String>> replies({
    required List<ReplyThread> threads,
    Map<String, RelationshipState> relations = const {},
  }) async => {
    for (final thread in threads) thread.persona.id: '模型写的追问',
  };

  @override
  Future<String?> peerReply({required PeerReplyThread thread}) async => null;

  @override
  Future<void> prewarm({
    required Post post,
    PostUnderstanding? understanding,
  }) async {}
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

    test('熟人话多一点：关系近的从长台词里挑', () {
      final persona = _persona(
        'persona_001',
        samples: const ['嗯。', '这条我看了好久，最近也在想同一件事'],
      );

      final picked = SampleContentGenerator(random: Random(1)).forPersona(
        persona,
        relation: const RelationshipState(personaId: 'persona_001', level: 2),
      );

      expect(picked, '这条我看了好久，最近也在想同一件事');
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

    test('还没来往的人，提示词里不写关系那一行', () {
      final prompt = ModelContentGenerator.systemPrompt(
        [_persona('persona_001')],
        relations: {
          'persona_001': const RelationshipState(personaId: 'persona_001'),
        },
      );

      expect(prompt, isNot(contains('你和他的关系')));
    });

    test('熟了之后带上档位，还有他记得的事', () {
      final prompt = ModelContentGenerator.systemPrompt(
        [_persona('persona_001')],
        relations: {
          'persona_001': const RelationshipState(
            personaId: 'persona_001',
            level: 2,
            memorySummary: '他上次拍过一张天空照',
          ),
        },
      );

      expect(prompt, contains('你和他的关系：互关'));
      expect(prompt, contains('他记得：他上次拍过一张天空照'));
    });

    test('共享前缀里有帖子、没有这一批的人物', () {
      final shared = ModelContentGenerator.sharedSystemPrompt(
        _post(content: '正文里有一棵树'),
      );

      expect(shared, contains('正文里有一棵树'));
      expect(shared, contains('不要提到自己是 AI'));
      expect(shared, isNot(contains('这次要评论的人')));
      expect(shared, isNot(contains('JSON')));
    });

    test('批次后缀里有人物，但不重复帖子快照', () {
      final batch = ModelContentGenerator.batchPrompt([
        _persona('persona_001', name: '温柔学姐'),
      ]);

      expect(batch, contains('[1] 温柔学姐'));
      expect(batch, contains('JSON'));
      expect(batch, isNot(contains('帖子正文')));
    });

    test('同一条帖子的共享前缀逐字节一致', () {
      final post = _post(content: '稳定前缀');
      final first = ModelContentGenerator.sharedSystemPrompt(post);
      final second = ModelContentGenerator.sharedSystemPrompt(post);

      expect(first, second);
    });

    test('记忆关掉的人不带记忆，但关系那行还在', () {
      final prompt = ModelContentGenerator.systemPrompt(
        [_persona('persona_001', memoryEnabled: false)],
        relations: {
          'persona_001': const RelationshipState(
            personaId: 'persona_001',
            level: 3,
            memorySummary: '他上次拍过一张天空照',
          ),
        },
      );

      expect(prompt, contains('你和他的关系：熟人'));
      expect(prompt, isNot(contains('他记得：')));
    });
  });

  group('缓存用量', () {
    test('OpenAI：prompt_tokens_details.cached_tokens', () {
      final usage = ModelUsage.fromBody({
        'usage': {
          'prompt_tokens': 2000,
          'completion_tokens': 120,
          'prompt_tokens_details': {'cached_tokens': 1536},
        },
      });

      expect(usage.promptTokens, 2000);
      expect(usage.cachedTokens, 1536);
      expect(usage.cacheHitRate, 77);
    });

    test('DeepSeek：prompt_cache_hit_tokens', () {
      final usage = ModelUsage.fromBody({
        'usage': {
          'prompt_tokens': 1024,
          'completion_tokens': 60,
          'prompt_cache_hit_tokens': 1024,
        },
      });

      expect(usage.cachedTokens, 1024);
      expect(usage.cacheHitRate, 100);
    });

    test('Anthropic：cache_read / cache_creation', () {
      final usage = ModelUsage.fromBody({
        'usage': {
          'input_tokens': 800,
          'output_tokens': 40,
          'cache_read_input_tokens': 640,
          'cache_creation_input_tokens': 160,
        },
      });

      expect(usage.cachedTokens, 640);
      expect(usage.cacheWriteTokens, 160);
      expect(usage.cacheHitRate, 80);
    });

    test('没有 usage 就是零，不编数字', () {
      expect(ModelUsage.fromBody({'choices': []}).hasData, isFalse);
      expect(ModelUsage.fromBody(null).cacheHitRate, 0);
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

    test('同一个编号出现两次时，最后一个写得出内容的胜出', () {
      // 这是重构之前就有的行为，守着它：模型这种输出全是噪音，
      // 怎么解都只是尽量少丢一条，不值得为它换一套规矩
      final personas = [_persona('persona_001')];

      expect(
        ModelContentGenerator.parseComments(
          '[{"index":1,"content":"A"},{"index":1,"content":"B"}]',
          personas,
        )['persona_001'],
        'B',
      );
      expect(
        ModelContentGenerator.parseComments(
          '[{"index":1,"content":"A"},{"index":1,"content":5}]',
          personas,
        )['persona_001'],
        'A',
        reason: '后一条写坏了，前一条该留着',
      );
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

  group('顺手换的签名（B3.5）', () {
    ResidentMoment moment(AiPersona persona) =>
        ResidentMoment(persona: persona, at: DateTime(2026, 9, 30, 21));

    test('样本动态每条都带一句签名——给不给是内容层的事，换不换由规则定', () async {
      final drafts = await SampleContentGenerator(random: Random(1)).residentPosts(
        moments: [moment(_persona('persona_001'))],
      );

      expect(drafts.single.newBio, isNotEmpty);
      expect(
        SampleContentGenerator.genericSignatures,
        contains(drafts.single.newBio),
      );
    });

    test('有圈层的住民，签名从自己那一档里出', () async {
      final drafts = await SampleContentGenerator(random: Random(1)).residentPosts(
        moments: [
          moment(
            const AiPersona(id: 'p', name: '耳机线打成结', circle: '音乐'),
          ),
        ],
      );

      expect(
        SampleContentGenerator.signatureTemplates['音乐'],
        contains(drafts.single.newBio),
      );
    });

    test('动态的提示词里要说明签名怎么写', () {
      final prompt = ModelContentGenerator.residentSystemPrompt([
        moment(_persona('p')),
      ]);

      expect(prompt, contains('签名'));
      expect(prompt, contains('"bio"'));
    });

    test('解析：带签名的动态', () {
      final parsed = ModelContentGenerator.parseIndexedPosts(
        '[{"index":1,"content":"今天风好大","bio":"风大，但还行"},'
        '{"index":2,"content":"第二句"}]',
        2,
      );

      expect(parsed[1]!.content, '今天风好大');
      expect(parsed[1]!.bio, '风大，但还行');
      expect(parsed[2]!.bio, isNull, reason: '没写就是这次不换');
    });

    test('解析：bio 写成空串等于没换，不该留个空签名', () {
      final parsed = ModelContentGenerator.parseIndexedPosts(
        '[{"index":1,"content":"正文","bio":"   "}]',
        1,
      );

      expect(parsed[1]!.bio, isNull);
    });

    test('解析：编号越界和空内容照旧丢掉', () {
      final parsed = ModelContentGenerator.parseIndexedPosts(
        '[{"index":3,"content":"越界"},{"index":1,"content":""}]',
        1,
      );

      expect(parsed, isEmpty);
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

    test('没有模型时不写评论，一次请求都不发', () async {
      final adapter = _FakeAdapter((_) async {
        fail('没有模型不该发请求');
      });
      dio.httpClientAdapter = adapter;

      final result = await buildSource().comments(
        personas: [_persona('persona_001', samples: const ['预置台词'])],
        post: _post(),
      );

      expect(result, isEmpty, reason: 'v3.0 不再用预置台词兜底');
      expect(adapter.calls, 0);
    });

    test('有模型时只返回它写出来的，缺的不用样本补', () async {
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
      expect(
        result.containsKey('persona_002'),
        isFalse,
        reason: 'v3.0 不用样本补缺',
      );
    });

    test('模型报错时整批留空', () async {
      await enableModel();
      dio.httpClientAdapter = _FakeAdapter(
        (_) async => _json('{"error":"boom"}', status: 500),
      );

      final result = await buildSource(config: _config).comments(
        personas: [_persona('persona_001', samples: const ['样本一'])],
        post: _post(),
      );

      expect(result, isEmpty);
    });

    test('模型返回空数组时整批留空', () async {
      await enableModel();
      dio.httpClientAdapter = _FakeAdapter(
        (_) async => _json(_chatReply('[]')),
      );

      final result = await buildSource(config: _config).comments(
        personas: [_persona('persona_001', samples: const ['样本一'])],
        post: _post(),
      );

      expect(result, isEmpty);
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
        relationships: RelationshipRepository(db),
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
            // v3.0：排期不再预填台词，等模型按帖子写
            content: null,
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
      expect(executed.content, isNull, reason: '已经兑现的评论不该被改写');
    });

    test('模型写挂了就取消这条评论，不往外抛', () async {
      generator.error = Exception('boom');
      await scheduleComments({'persona_001': false});

      // 这一步失败不该让调用方（发布流程）看见异常
      await scheduler.upgradeCommentsWithModel(postId);

      final row = await db.select(db.aiInteractions).getSingle();
      expect(row.status, 'cancelled');
      expect(row.content, isNull);
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

  group('AI 接 AI', () {
    test('提示词带楼上那句话、发帖内容与口吻约束', () {
      final prompt = ModelContentGenerator.peerReplyPrompt(
        PeerReplyThread(
          persona: _persona('p', name: '大肥鱼'),
          post: _post(content: '今天抽卡又歪了'),
          targetName: '三楼的灯',
          targetContent: '我也是大保底',
        ),
      );

      expect(prompt, contains('三楼的灯'));
      expect(prompt, contains('我也是大保底'));
      expect(prompt, contains('10—30 字'));
      expect(prompt, contains('只输出这一句'));
    });

    test('去掉引号；空串和超长都不要', () {
      expect(ModelContentGenerator.parsePeerReply('"接一句"'), '接一句');
      expect(ModelContentGenerator.parsePeerReply('  '), isNull);
      expect(
        ModelContentGenerator.parsePeerReply(
          List.filled(81, '啊').join(),
        ),
        isNull,
      );
    });
  });
}
