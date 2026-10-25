import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
// drift 也导出了 isNull / isNotNull，与 matcher 重名，藏掉它那份
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/media/media_service.dart';
import 'package:echo/data/repositories/model_config_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/domain/models/model_config.dart';
import 'package:echo/domain/models/resident_post.dart';
import 'package:echo/domain/services/model_gateway.dart';
import 'package:echo/domain/services/resident_photo.dart';
import 'package:flutter_test/flutter_test.dart';

/// 想让它过就过、想让它不过就不过——概率这件事不该靠试种子来测。
class _FixedRandom implements Random {
  _FixedRandom(this.value);

  final double value;

  @override
  double nextDouble() => value;

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

class _MemoryKeyStore implements KeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// 读不出来的钥匙串：用来验证"配置读失败"没有被伪装成"没配"。
class _BrokenKeyStore implements KeyStore {
  @override
  Future<String?> read(String key) async => throw StateError('钥匙串读不出来');

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

/// 图片落盘：这一层要测的是"有没有把图挂上去"，不是文件系统。
class _FakeMedia implements MediaService {
  final List<int> saved = [];
  final List<String> deleted = [];

  @override
  Future<String> saveBytes(Uint8List bytes) async {
    saved.add(bytes.length);
    return 'file:fake/photo.png';
  }

  @override
  Future<String?> pickFromGallery() async => null;

  @override
  Future<String?> pickFromCamera() async => null;

  @override
  Future<void> deleteByRef(String ref) async {
    deleted.add(ref);
  }

  @override
  Future<File> newVoiceFile({String extension = '.wav'}) async =>
      File('fake/voice$extension');
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

ResponseBody _imageReply() => ResponseBody.fromString(
  jsonEncode({
    'data': [
      {'b64_json': base64Encode(const [1, 2, 3, 4, 5])},
    ],
  }),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

const _imageConfig = ModelConfig(
  id: 'img1',
  provider: 'custom',
  label: '文生图',
  baseUrl: 'https://example.com/v1',
  model: 'image-model',
  kind: ModelKind.image,
  enabled: true,
);

AiPersona _persona({
  String id = 'persona_001',
  String name = '跑者阿哲',
  String circle = '运动',
  List<PersonaRoutine> routines = const [],
}) => AiPersona(id: id, name: name, circle: circle, routines: routines);

ResidentMoment _moment(AiPersona persona, DateTime at) =>
    ResidentMoment(persona: persona, at: at);

void main() {
  final at = DateTime(2026, 9, 30, 17);

  group('值不值得拍', () {
    test('家是躺着的地方，不值', () {
      final persona = _persona(
        routines: const [PersonaRoutine(hour: 17, place: '家', activity: '睡午觉')],
      );

      expect(ResidentPhoto.isWorthShooting(persona, at), isFalse);
    });

    test('操场、食堂该拍', () {
      for (final place in const ['操场', '二食堂', '图书馆']) {
        final persona = _persona(
          routines: [PersonaRoutine(hour: 17, place: place, activity: '待着')],
        );
        expect(
          ResidentPhoto.isWorthShooting(persona, at),
          isTrue,
          reason: '$place 有得拍',
        );
      }
    });

    test('楼下别被家这个字一起扫掉', () {
      final persona = _persona(
        routines: const [
          PersonaRoutine(hour: 17, place: '楼下', activity: '拿外卖'),
        ],
      );

      expect(ResidentPhoto.isWorthShooting(persona, at), isTrue);
    });

    test('没有作息的人照样可能拍', () {
      expect(ResidentPhoto.isWorthShooting(_persona(), at), isTrue);
    });
  });

  group('拍在哪儿', () {
    test('有作息就用那个地方', () {
      final persona = _persona(
        routines: const [PersonaRoutine(hour: 17, place: '二食堂', activity: '吃饭')],
      );

      expect(ResidentPhoto.sceneFor(persona, at), '二食堂');
    });

    test('没有作息就按圈层给一个', () {
      expect(ResidentPhoto.sceneFor(_persona(circle: '运动'), at), '跑道和跑道边的树');
      expect(ResidentPhoto.sceneFor(_persona(circle: ''), at), '生活里的一个角落');
    });
  });

  group('挑这次配图的那条动态', () {
    test('刚发过图的就消停一阵', () {
      final moments = [_moment(_persona(), at)];

      for (var i = 0; i < 20; i++) {
        expect(
          ResidentPhoto.pick(
            moments: moments,
            at: at,
            lastAt: at.subtract(const Duration(hours: 2)),
            random: _FixedRandom(0),
          ),
          isNull,
          reason: '冷却期内连抽都不该抽',
        );
      }
    });

    test('冷却过了也不一定拍', () {
      expect(
        ResidentPhoto.pick(
          moments: [_moment(_persona(), at)],
          at: at,
          lastAt: null,
          random: _FixedRandom(1),
        ),
        isNull,
      );
    });

    test('这批人全在家里待着，就一张都不拍', () {
      final sleepy = _persona(
        id: 'p2',
        routines: const [PersonaRoutine(hour: 17, place: '家', activity: '补觉')],
      );

      expect(
        ResidentPhoto.pick(
          moments: [_moment(sleepy, at)],
          at: at,
          lastAt: null,
          random: _FixedRandom(0),
        ),
        isNull,
      );
    });

    test('条件都过得去时，挑出来的一定在这批人里', () {
      final picked = ResidentPhoto.pick(
        moments: [
          _moment(_persona(id: 'a'), at),
          _moment(_persona(id: 'b'), at),
        ],
        at: at,
        lastAt: at.subtract(ResidentPhoto.cooldown),
        random: _FixedRandom(0),
      );

      expect(picked, isNotNull);
      expect(['a', 'b'], contains(picked!.persona.id));
    });
  });

  group('落盘的扩展名', () {
    test('jpeg 头就写成 .jpg', () {
      expect(
        MediaService.extensionOf(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
        '.jpg',
      );
    });

    test('png 头就写成 .png', () {
      expect(
        MediaService.extensionOf(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ),
        '.png',
      );
    });

    test('认不出来就按 png 写', () {
      expect(MediaService.extensionOf(Uint8List.fromList([1, 2, 3])), '.png');
    });
  });

  group('出图的提示词', () {
    final persona = _persona(
      routines: const [PersonaRoutine(hour: 17, place: '操场', activity: '跑步')],
    );

    test('场景、在干什么、什么时候，都交代到', () {
      final prompt = ResidentPhoto.promptFor(persona: persona, at: at);

      expect(prompt, contains('操场'));
      expect(prompt, contains('跑步'));
      expect(prompt, contains('9月30日'));
    });

    test('要主动要那点不完美——不然模型直奔壁纸去', () {
      final prompt = ResidentPhoto.promptFor(persona: persona, at: at);

      expect(prompt, contains('模糊'));
      expect(prompt, contains('噪点'));
      expect(prompt, contains('随手'));
    });

    test('画面里不许有字', () {
      final prompt = ResidentPhoto.promptFor(persona: persona, at: at);

      expect(prompt, contains('不要出现任何文字'));
    });
  });

  group('配图的落地', () {
    late AppDatabase db;
    late PostRepository posts;
    late _FakeMedia media;
    late ModelConfigRepository configs;
    late _FakeAdapter adapter;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      posts = PostRepository(db);
      media = _FakeMedia();
      configs = ModelConfigRepository(db, keyStore: _MemoryKeyStore());
      adapter = _FakeAdapter((_) async => _imageReply());

      // 住民得先在库里：posts.author_persona_id 有外键指着它
      await db
          .into(db.aiPersonas)
          .insert(AiPersonasCompanion.insert(id: 'persona_001', name: '跑者阿哲'));
    });

    tearDown(() async => db.close());

    ResidentPhotoService build({double chance = 0}) => ResidentPhotoService(
      db: db,
      posts: posts,
      media: media,
      gateway: ModelGateway(configs, dio: Dio()..httpClientAdapter = adapter),
      random: _FixedRandom(chance),
    );

    Future<void> enableImageModel() async {
      await configs.save(_imageConfig);
      await configs.writeKey(_imageConfig.id, 'sk-test');
    }

    Future<Map<String, String>> onePost() async {
      final id = await posts.createResidentPost(
        personaId: 'persona_001',
        content: '操场上跑了五圈。',
      );
      return {'persona_001': id};
    }

    Future<List<String>> imagesOf(String postId) async {
      final query = db.select(db.posts)..where((t) => t.id.equals(postId));
      final row = await query.getSingle();
      return (jsonDecode(row.images) as List).cast<String>();
    }

    Future<String?> watermark() async {
      final query = db.select(db.appSettings)
        ..where((t) => t.key.equals(ResidentPhotoService.lastAtKey));
      return (await query.getSingleOrNull())?.value;
    }

    test('没配文生图就只发文字，一次请求都不发', () async {
      final postIds = await onePost();

      final ref = await build().attach(
        postIds: postIds,
        moments: [_moment(_persona(), at)],
        at: at,
      );

      expect(ref, isNull);
      expect(adapter.calls, 0, reason: '没配置就没有请求可发');
      expect(await imagesOf(postIds['persona_001']!), isEmpty);
    });

    test('配好了图就挂到那条动态上', () async {
      await enableImageModel();
      final postIds = await onePost();

      final ref = await build().attach(
        postIds: postIds,
        moments: [_moment(_persona(), at)],
        at: at,
      );

      expect(ref, 'file:fake/photo.png');
      expect(media.saved.single, 5, reason: '模型给的字节要原样落盘');
      expect(await imagesOf(postIds['persona_001']!), ['file:fake/photo.png']);
      expect(await watermark(), '${at.millisecondsSinceEpoch}');
    });

    test('出图失败就当这次是纯文字，什么都别留下', () async {
      await enableImageModel();
      adapter = _FakeAdapter((_) async => ResponseBody.fromString('', 500));
      final postIds = await onePost();

      final ref = await build().attach(
        postIds: postIds,
        moments: [_moment(_persona(), at)],
        at: at,
      );

      expect(ref, isNull);
      expect(await imagesOf(postIds['persona_001']!), isEmpty);
      expect(
        await watermark(),
        isNull,
        reason: '没成的事不该占掉下一次的机会',
      );
    });

    test('帖子不在了，图要收回来——别留个谁也不引用的文件', () async {
      await enableImageModel();

      final ref = await build().attach(
        postIds: const {'persona_001': 'post_已经没了'},
        moments: [_moment(_persona(), at)],
        at: at,
      );

      expect(ref, isNull);
      expect(media.saved.single, 5, reason: '图是真生成出来了');
      expect(media.deleted, ['file:fake/photo.png'], reason: '挂不上就得删掉');
      expect(await watermark(), isNull, reason: '没成的事不占下一次的机会');
    });

    test('配置读不出来时不当作"没配"——那样等于把真问题藏起来', () async {
      // 先正常存一条能用的图片配置，再用读不了的钥匙串去查它
      await enableImageModel();
      final broken = ResidentPhotoService(
        db: db,
        posts: posts,
        media: media,
        gateway: ModelGateway(
          ModelConfigRepository(db, keyStore: _BrokenKeyStore()),
          dio: Dio()..httpClientAdapter = adapter,
        ),
        random: _FixedRandom(0),
      );

      await expectLater(
        broken.attach(
          postIds: await onePost(),
          moments: [_moment(_persona(), at)],
          at: at,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('上一次刚发过图，这次就不发', () async {
      await enableImageModel();
      final postIds = await onePost();
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: ResidentPhotoService.lastAtKey,
              value: '${at.subtract(const Duration(hours: 1)).millisecondsSinceEpoch}',
            ),
          );

      final ref = await build().attach(
        postIds: postIds,
        moments: [_moment(_persona(), at)],
        at: at,
      );

      expect(ref, isNull);
      expect(adapter.calls, 0);
    });
  });
}
