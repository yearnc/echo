import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/model_config_repository.dart';
import 'package:echo/domain/models/model_config.dart';
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
        expect(preset.baseUrl, startsWith('https://'));
      }
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
