import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/model_config_repository.dart';
import 'package:echo/domain/models/model_config.dart';
import 'package:echo/domain/services/model_call_common.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试用的密钥存储：真实实现要走平台通道，单元测试里调不起来。
class _MemoryKeyStore implements KeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  group('地址校验（把问题说在地址上，而不是笼统说"连不上"）', () {
    test('没写协议头：直接点名', () {
      final problem = describeBaseUrlProblem(
        'dashscope.aliyuncs.com/compatible-mode/v1',
      );

      expect(problem, contains('https://'), reason: '手机上手打地址最容易漏这一段');
    });

    test('明文 http：拒绝，并说明密钥会裸奔', () {
      expect(describeBaseUrlProblem('http://api.example.com/v1'), contains('密钥'));
    });

    test('本机与内网放行（那是自己跑的服务）', () {
      expect(describeBaseUrlProblem('http://localhost:8000/v1'), isNull);
      expect(describeBaseUrlProblem('http://192.168.1.10/v1'), isNull);
    });

    test('正常的 https 地址没问题', () {
      expect(describeBaseUrlProblem('https://api.deepseek.com'), isNull);
    });

    test('空地址也要说清楚', () {
      expect(describeBaseUrlProblem('   '), isNotNull);
    });

    test('地址里的多余空格会被吃掉', () {
      expect(describeBaseUrlProblem('  https://api.deepseek.com  '), isNull);
    });
  });

  group('ModelConfig', () {
    test('预设能找到对应服务商，找不到时退回自定义', () {
      expect(ModelConfig.presetOf('deepseek').label, 'DeepSeek');
      expect(ModelConfig.presetOf('openai').model, 'gpt-6-astra');
      expect(ModelConfig.presetOf('不存在的东西').id, 'custom');
    });

    test('预设里的 base_url 都与官方要求一致', () {
      // DeepSeek 官方给的是裸域；智谱的 /api/paas/v4 是地址的一部分
      expect(
        ModelConfig.presetOf('deepseek').baseUrl,
        'https://api.deepseek.com',
      );
      expect(
        ModelConfig.presetOf('zhipu').baseUrl,
        'https://open.bigmodel.cn/api/paas/v4',
      );
      expect(
        ModelConfig.presetOf('openai').baseUrl,
        'https://api.openai.com/v1',
      );
      // 每个预设都得有个默认模型，不能空着
      for (final preset in ModelConfig.presets) {
        if (preset.id == 'custom') continue;
        expect(preset.model, isNotEmpty, reason: '${preset.label} 缺默认模型');
        // 本机/内网服务允许 http（比如自己跑的服务），公网必须是 https。
        expect(
          isSecureBaseUrl(preset.baseUrl),
          isTrue,
          reason: '${preset.label} 的地址不安全',
        );
      }
    });

    test('语音合成是独立用途，预设在语音分组里', () {
      expect(ModelKind.fromId('tts'), ModelKind.tts);
      expect(ModelKind.fromId('不认识'), ModelKind.chat);

      final presets = ModelConfig.presetsOf(ModelKind.tts);
      expect(presets.any((p) => p.id == 'siliconflow-tts'), isTrue);
      expect(
        ModelConfig.presetOf('openai-tts', kind: ModelKind.tts).baseUrl,
        'https://api.openai.com/v1',
      );
      for (final preset in presets) {
        if (preset.id == 'custom') continue;
        expect(preset.model, isNotEmpty, reason: '${preset.label} 缺默认模型');
        expect(
          isSecureBaseUrl(preset.baseUrl),
          isTrue,
          reason: '${preset.label} 的地址不安全',
        );
      }
      // 云端 TTS 里，OpenAI 支持按描述调语气，硅基流动支持参考音频 + 逐字稿。
      final openai = ModelConfig.presetOf('openai-tts', kind: ModelKind.tts);
      expect(openai.ttsVoiceDescription, isTrue);
      final silicon = ModelConfig.presetOf(
        'siliconflow-tts',
        kind: ModelKind.tts,
      );
      expect(silicon.ttsReferenceTranscript, isTrue);
    });

    test('地址和模型名都填了才算完整', () {
      const empty = ModelConfig(
        id: 'a',
        provider: 'custom',
        label: 'x',
        baseUrl: '',
        model: '',
      );
      expect(empty.isComplete, isFalse);

      const half = ModelConfig(
        id: 'a',
        provider: 'custom',
        label: 'x',
        baseUrl: 'https://example.com/v1',
        model: '',
      );
      expect(half.isComplete, isFalse);

      const full = ModelConfig(
        id: 'a',
        provider: 'custom',
        label: 'x',
        baseUrl: 'https://example.com/v1',
        model: 'm',
      );
      expect(full.isComplete, isTrue);
    });
  });

  group('ModelConfigRepository', () {
    late AppDatabase db;
    late ModelConfigRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = ModelConfigRepository(db);
    });

    tearDown(() async => db.close());

    test('保存后能按 id 读回来', () async {
      const config = ModelConfig(
        id: 'm1',
        provider: 'deepseek',
        label: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com/v1',
        model: 'deepseek-chat',
      );

      await repo.save(config);

      final loaded = await repo.findById('m1');
      expect(loaded, isNotNull);
      expect(loaded!.model, 'deepseek-chat');
      expect(loaded.enabled, isFalse, reason: '新建的配置默认不启用');
      expect(loaded.contextWindow, 1000000, reason: '默认按百万上下文');
    });

    test('上下文窗口可以按服务商改小并读回来', () async {
      const config = ModelConfig(
        id: 'm2',
        provider: 'custom',
        label: '小窗口',
        baseUrl: 'https://example.com/v1',
        model: '32k-model',
        contextWindow: 32768,
      );
      await repo.save(config);
      final loaded = await repo.findById('m2');
      expect(loaded!.contextWindow, 32768);
    });

    test('同一时间只有一条配置生效', () async {
      await repo.save(
        const ModelConfig(
          id: 'm1',
          provider: 'a',
          label: 'A',
          baseUrl: 'https://a/v1',
          model: 'm',
        ),
      );
      await repo.save(
        const ModelConfig(
          id: 'm2',
          provider: 'b',
          label: 'B',
          baseUrl: 'https://b/v1',
          model: 'm',
        ),
      );

      await repo.setEnabled('m1');
      expect((await repo.findById('m1'))!.enabled, isTrue);

      await repo.setEnabled('m2');
      expect((await repo.findById('m1'))!.enabled, isFalse);
      expect((await repo.findById('m2'))!.enabled, isTrue);
    });

    test('密钥不进数据库；删配置时连密钥一起清掉', () async {
      final keyStore = _MemoryKeyStore();
      final repo = ModelConfigRepository(db, keyStore: keyStore);

      await repo.save(
        const ModelConfig(
          id: 'm1',
          provider: 'deepseek',
          label: 'DeepSeek',
          baseUrl: 'https://api.deepseek.com',
          model: 'deepseek-flash',
        ),
      );
      await repo.writeKey('m1', 'sk-这是密钥');
      expect(await repo.hasKey('m1'), isTrue);

      // 数据库里只有配置，没有密钥
      final rows = await db.select(db.modelConfigs).get();
      expect(rows.single.toString().contains('sk-这是密钥'), isFalse);

      await repo.delete('m1');

      expect(await repo.findById('m1'), isNull);
      expect(await repo.hasKey('m1'), isFalse);
      expect(keyStore.values, isEmpty, reason: '密钥也要跟着清掉，不留孤儿');
    });
  });
}
