import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/model_config_repository.dart';
import 'package:echo/domain/models/model_config.dart';
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

  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    paths.add(options.uri.toString());
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

ResponseBody _bytes(List<int> data) => ResponseBody.fromBytes(
  data,
  200,
  headers: {
    Headers.contentTypeHeader: ['image/png'],
  },
);

const _chat = ModelConfig(
  id: 'chat1',
  provider: 'custom',
  label: '聊天',
  baseUrl: 'https://example.com/v1',
  model: 'chat-model',
);

const _image = ModelConfig(
  id: 'img1',
  provider: 'custom',
  label: '文生图',
  baseUrl: 'https://example.com/v1',
  model: 'image-model',
  kind: ModelKind.image,
);

void main() {
  group('模型配置的用途', () {
    late AppDatabase db;
    late ModelConfigRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = ModelConfigRepository(db, keyStore: _MemoryKeyStore());
    });

    tearDown(() async => db.close());

    test('新配置默认是聊天', () async {
      await repo.save(
        const ModelConfig(
          id: 'm1',
          provider: 'custom',
          label: 'x',
          baseUrl: 'https://a/v1',
          model: 'm',
        ),
      );
      expect((await repo.findById('m1'))!.kind, ModelKind.chat);
    });

    test('用途存得住', () async {
      await repo.save(_image);
      expect((await repo.findById('img1'))!.kind, ModelKind.image);
    });

    test('启用一条不会关掉另一个用途的配置', () async {
      await repo.save(_chat);
      await repo.save(_image);

      await repo.setEnabled('chat1');
      await repo.setEnabled('img1');

      expect(
        (await repo.findById('chat1'))!.enabled,
        isTrue,
        reason: '配文生图不该把好不容易调好的聊天配置顺手关掉',
      );
      expect((await repo.findById('img1'))!.enabled, isTrue);
    });

    test('同一个用途里仍然只有一条生效', () async {
      await repo.save(_chat);
      await repo.save(
        const ModelConfig(
          id: 'chat2',
          provider: 'custom',
          label: '聊天2',
          baseUrl: 'https://b/v1',
          model: 'm',
        ),
      );

      await repo.setEnabled('chat1');
      await repo.setEnabled('chat2');

      expect((await repo.findById('chat1'))!.enabled, isFalse);
      expect((await repo.findById('chat2'))!.enabled, isTrue);
    });
  });

  group('按用途找当前配置', () {
    late AppDatabase db;
    late ModelConfigRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = ModelConfigRepository(db, keyStore: _MemoryKeyStore());
    });

    tearDown(() async => db.close());

    Future<void> enable(ModelConfig config) async {
      await repo.save(config);
      await repo.setEnabled(config.id);
      await repo.writeKey(config.id, 'sk-test');
    }

    test('只有文生图配置时，聊天那边找不到', () async {
      await enable(_image);
      final gateway = ModelGateway(repo);

      expect((await gateway.activeConfig(kind: ModelKind.image))?.id, 'img1');
      expect(
        await gateway.activeConfig(),
        isNull,
        reason: '不带参数时找的是聊天配置',
      );
    });

    test('只配了聊天时，文生图那边找不到', () async {
      await enable(_chat);
      final gateway = ModelGateway(repo);

      expect(await gateway.activeConfig(kind: ModelKind.image), isNull);
      expect((await gateway.activeConfig())?.id, 'chat1');
    });
  });

  group('生成图片', () {
    late AppDatabase db;
    late ModelConfigRepository repo;
    late Dio dio;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = ModelConfigRepository(db, keyStore: _MemoryKeyStore());
      dio = Dio();
    });

    tearDown(() async => db.close());

    Future<void> enable(ModelConfig config) async {
      await repo.save(config);
      await repo.setEnabled(config.id);
      await repo.writeKey(config.id, 'sk-test');
    }

    Future<Uint8List> generate({String? prompt}) => ModelGateway(
      repo,
      dio: dio,
    ).generateImage(config: _image, prompt: prompt ?? '一只猫');

    test('服务端给 base64 时直接解出来', () async {
      await enable(_image);
      final png = [137, 80, 78, 71, 13, 10, 26, 10];
      dio.httpClientAdapter = _FakeAdapter(
        (_) async => _json(
          jsonEncode({
            'data': [
              {'b64_json': base64Encode(png)},
            ],
          }),
        ),
      );

      expect(await generate(), png);
    });

    test('服务端给链接时再取一次', () async {
      await enable(_image);
      final png = [1, 2, 3, 4];
      final adapter = _FakeAdapter((options) async {
        if (options.uri.path.contains('images/generations')) {
          return _json(
            jsonEncode({
              'data': [
                {'url': 'https://cdn.example.com/a.png'},
              ],
            }),
          );
        }
        return _bytes(png);
      });
      dio.httpClientAdapter = adapter;

      expect(await generate(), png);
      expect(adapter.paths.length, 2, reason: '先要图，再下载');
      expect(adapter.paths.last, 'https://cdn.example.com/a.png');
    });

    test('硅基流动那种 images[].url 的形状也认', () async {
      await enable(_image);
      final png = [9, 9, 9];
      final adapter = _FakeAdapter((options) async {
        if (options.uri.path.contains('images/generations')) {
          return _json(
            jsonEncode({
              'images': [
                {'url': 'https://cdn.example.com/b.png'},
              ],
            }),
          );
        }
        return _bytes(png);
      });
      dio.httpClientAdapter = adapter;

      expect(await generate(), png);
      expect(adapter.paths.last, 'https://cdn.example.com/b.png');
    });

    test('不发 n 也不发 response_format（不是每家都认）', () async {
      await enable(_image);
      late Map<String, dynamic> sent;
      dio.httpClientAdapter = _FakeAdapter((options) async {
        sent = options.data as Map<String, dynamic>;
        return _json(
          jsonEncode({
            'data': [
              {'b64_json': base64Encode([1])},
            ],
          }),
        );
      });

      await generate();

      expect(sent.keys, containsAll(['model', 'prompt']));
      expect(sent.containsKey('n'), isFalse);
      expect(sent.containsKey('response_format'), isFalse);
    });

    test('请求打在 /images/generations 上，而不是对话那条路径', () async {
      await enable(_image);
      final adapter = _FakeAdapter(
        (_) async => _json(
          jsonEncode({
            'data': [
              {'b64_json': base64Encode([1])},
            ],
          }),
        ),
      );
      dio.httpClientAdapter = adapter;

      await generate();

      expect(adapter.paths.single, 'https://example.com/v1/images/generations');
    });

    test('返回里什么都没有时报一句人话', () async {
      await enable(_image);
      dio.httpClientAdapter = _FakeAdapter((_) async => _json('{"data":[]}'));

      expect(
        generate,
        throwsA(
          isA<ModelCallException>().having(
            (e) => e.message,
            'message',
            contains('图片'),
          ),
        ),
      );
    });

    test('明文 http 的地址被拦下', () async {
      const insecure = ModelConfig(
        id: 'img2',
        provider: 'custom',
        label: '明文',
        baseUrl: 'http://example.com/v1',
        model: 'm',
        kind: ModelKind.image,
      );
      await enable(insecure);
      dio.httpClientAdapter = _FakeAdapter((_) async {
        fail('明文 http 不该发请求');
      });

      expect(
        () => ModelGateway(
          repo,
          dio: dio,
        ).generateImage(config: insecure, prompt: 'x'),
        throwsA(isA<ModelCallException>()),
      );
    });

    test('没填密钥时给一句人话', () async {
      await repo.save(_image);
      dio.httpClientAdapter = _FakeAdapter((_) async {
        fail('没有密钥不该发请求');
      });

      expect(
        () => ModelGateway(
          repo,
          dio: dio,
        ).generateImage(config: _image, prompt: 'x'),
        throwsA(
          isA<ModelCallException>().having(
            (e) => e.message,
            'message',
            contains('API Key'),
          ),
        ),
      );
    });
  });
}
