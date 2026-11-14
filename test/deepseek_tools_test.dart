import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/model_config_repository.dart';
import 'package:echo/domain/models/model_config.dart';
import 'package:echo/domain/services/asr_service.dart';
import 'package:echo/domain/services/model_gateway.dart';
import 'package:echo/domain/services/ocr_service.dart';
import 'package:echo/domain/services/speech_models.dart';
import 'package:echo/domain/services/web_search.dart';
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
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    // multipart 是从文件流式读的；不把流排空，文件句柄会一直开着，
    // Windows 上接着删临时目录就会报“另一个程序正在使用”。
    if (requestStream != null) await requestStream.drain<void>();
    return reply(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody _bytes(List<int> data, String type) => ResponseBody.fromBytes(
  data,
  200,
  headers: {
    Headers.contentTypeHeader: [type],
  },
);

/// 本机 ASR 模型“没下载”，让服务直接走云端分支。
class _MissingAsrStore extends SpeechModelStore {
  @override
  Future<ReleasedModels> prepareAsr() async =>
      throw const SpeechModelMissing('asr');
}

/// 一段能通过 WavPcm 校验的 16kHz / 16-bit / 单声道 wav。
Uint8List _wav({double seconds = 0.5}) {
  const sampleRate = 16000;
  final frames = (sampleRate * seconds).round();
  final dataBytes = frames * 2;
  final bytes = BytesBuilder();
  bytes.add(utf8.encode('RIFF'));
  bytes.add((36 + dataBytes).toUint32LittleEndian());
  bytes.add(utf8.encode('WAVEfmt '));
  bytes.add(16 .toUint32LittleEndian());
  bytes.add(1 .toUint16LittleEndian()); // PCM
  bytes.add(1 .toUint16LittleEndian()); // mono
  bytes.add(sampleRate.toUint32LittleEndian());
  bytes.add((sampleRate * 2).toUint32LittleEndian());
  bytes.add(2 .toUint16LittleEndian());
  bytes.add(16 .toUint16LittleEndian());
  bytes.add(utf8.encode('data'));
  bytes.add(dataBytes.toUint32LittleEndian());
  bytes.add(Uint8List(dataBytes));
  return bytes.toBytes();
}

extension on int {
  Uint8List toUint16LittleEndian() {
    final data = ByteData(2)..setUint16(0, this, Endian.little);
    return data.buffer.asUint8List();
  }

  Uint8List toUint32LittleEndian() {
    final data = ByteData(4)..setUint32(0, this, Endian.little);
    return data.buffer.asUint8List();
  }
}

void main() {
  late AppDatabase db;
  late ModelConfigRepository repo;
  late Dio dio;
  late _FakeAdapter adapter;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ModelConfigRepository(db, keyStore: _MemoryKeyStore());
    await repo.save(
      const ModelConfig(
        id: 'ds',
        provider: 'deepseek',
        label: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-flash',
      ),
    );
    await repo.writeKey('ds', 'sk-test');
  });

  tearDown(() async => db.close());

  group('DeepSeek TTS', () {
    test('走 /v1/tools/tts，默认音色映射成 stella，返回 wav', () async {
      adapter = _FakeAdapter((_) async => _bytes([1, 2, 3, 4], 'audio/wav'));
      dio = Dio()..httpClientAdapter = adapter;
      final gateway = ModelGateway(repo, dio: dio);

      const config = ModelConfig(
        id: 'tts',
        provider: 'deepseek-tts',
        label: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-tts',
        kind: ModelKind.tts,
      );
      await repo.save(config);
      await repo.writeKey('tts', 'sk-test');
      final bytes = await gateway.speech(
        config: config,
        text: '你好',
        voice: 'alloy',
      );

      expect(bytes, [1, 2, 3, 4]);
      final request = adapter.requests.single;
      expect(request.uri.toString(), 'https://api.deepseek.com/v1/tools/tts');
      final body = request.data as Map<String, dynamic>;
      expect(body['voice_id'], 'stella');
      expect(body['format'], 'wav');
      expect(body['filter_markdown'], isTrue);
      expect(body.containsKey('model'), isFalse);
    });

    test('tide 会原样传下去', () async {
      adapter = _FakeAdapter((_) async => _bytes([9], 'audio/wav'));
      dio = Dio()..httpClientAdapter = adapter;
      final gateway = ModelGateway(repo, dio: dio);

      const config = ModelConfig(
        id: 'tts',
        provider: 'deepseek-tts',
        label: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-tts',
        kind: ModelKind.tts,
      );
      await repo.save(config);
      await repo.writeKey('tts', 'sk-test');
      await gateway.speech(config: config, text: '嗯', voice: 'tide');

      expect((adapter.requests.single.data as Map)['voice_id'], 'tide');
    });
  });

  group('DeepSeek Fetch', () {
    test('打开网页返回标题和正文', () async {
      adapter = _FakeAdapter(
        (_) async => _json({'title': '示例页', 'content': '# 正文\n内容'}),
      );
      dio = Dio()..httpClientAdapter = adapter;
      final service = WebSearchService(configs: repo, db: db, dio: dio);
      await service.setProvider(WebSearchService.providerDeepseek);

      final outcome = await service.fetch('https://example.com/a');

      expect(outcome.ok, isTrue);
      expect(outcome.title, '示例页');
      expect(outcome.content, contains('正文'));
      final request = adapter.requests.single;
      expect(request.uri.toString(), 'https://api.deepseek.com/v1/tools/fetch');
      expect((request.data as Map)['url'], 'https://example.com/a');
    });

    test('非法链接直接拒绝，不发请求', () async {
      adapter = _FakeAdapter((_) async => _json({}));
      dio = Dio()..httpClientAdapter = adapter;
      final service = WebSearchService(configs: repo, db: db, dio: dio);
      await service.setProvider(WebSearchService.providerDeepseek);

      expect((await service.fetch('ftp://example.com/a')).ok, isFalse);
      expect((await service.fetch('不是链接')).ok, isFalse);
      expect(adapter.requests, isEmpty);
    });
  });

  group('DeepSeek OCR', () {
    test('按页拼正文，开关默认关、能存能读', () async {
      final dir = await Directory.systemTemp.createTemp('echo_ocr_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/note.png')..writeAsBytesSync([1, 2, 3]);

      adapter = _FakeAdapter(
        (_) async => _json({
          'page_count': 2,
          'pages': [
            {'index': 0, 'text': '第一页'},
            {'index': 1, 'text': '第二页'},
          ],
        }),
      );
      dio = Dio()..httpClientAdapter = adapter;
      final service = OcrService(configs: repo, db: db, dio: dio);

      expect(await service.enabled(), isFalse, reason: '默认不发图片给云端');
      await service.setEnabled(true);
      expect(await service.enabled(), isTrue);

      final result = await service.recognize(file.path);
      expect(result.text, '第一页\n\n第二页');
      expect(result.pageCount, 2);
      final request = adapter.requests.single;
      expect(request.uri.toString(), 'https://api.deepseek.com/v1/tools/ocr');
      expect(request.data, isA<FormData>());
      expect(
        (request.data as FormData).fields.any(
          (entry) => entry.key == 'purpose' && entry.value == 'text_recognition',
        ),
        isTrue,
      );
    });
  });

  group('DeepSeek 云端 ASR 兜底', () {
    test('本机模型缺失、云端开关打开时走 /v1/tools/asr', () async {
      final dir = await Directory.systemTemp.createTemp('echo_asr_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/speech.wav')
        ..writeAsBytesSync(_wav(seconds: 0.5));

      adapter = _FakeAdapter(
        (_) async => _json({'text': '你好呀', 'duration_ms': 500}),
      );
      dio = Dio()..httpClientAdapter = adapter;
      final service = AsrService(
        store: _MissingAsrStore(),
        db: db,
        configs: repo,
        dio: dio,
      );

      await service.setCloudEnabled(true);
      final result = await service.transcribeWav(file.path);

      expect(result.text, '你好呀');
      expect(result.durationMs, 500);
      final request = adapter.requests.single;
      expect(request.uri.toString(), 'https://api.deepseek.com/v1/tools/asr');
      expect(request.data, isA<FormData>());
    });

    test('云端开关关着时，本机失败就直说没下载', () async {
      final dir = await Directory.systemTemp.createTemp('echo_asr_test2');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/speech.wav')
        ..writeAsBytesSync(_wav(seconds: 0.5));

      adapter = _FakeAdapter((_) async => _json({'text': '不该被调用'}));
      dio = Dio()..httpClientAdapter = adapter;
      final service = AsrService(
        store: _MissingAsrStore(),
        db: db,
        configs: repo,
        dio: dio,
      );

      expect(
        () => service.transcribeWav(file.path),
        throwsA(isA<StateError>()),
      );
      expect(adapter.requests, isEmpty);
    });
  });
}
