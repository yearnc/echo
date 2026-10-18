import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/post_voice_repository.dart';
import 'package:echo/domain/models/post_voice.dart';

void main() {
  late AppDatabase db;
  late PostRepository posts;
  late PostVoiceRepository voices;
  late String postId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    posts = PostRepository(db);
    voices = PostVoiceRepository(db);
    postId = await posts.create(content: '一条帖子', scope: 'echo');
  });

  tearDown(() async => db.close());

  PostVoice voice(String id, {String name = '大肥鱼', int seed = 0}) => PostVoice(
    id: id,
    postId: postId,
    kind: PostVoiceKind.ephemeral,
    name: name,
    avatarAsset: PostVoiceRepository.avatarFor(seed: seed),
    avatarSeed: seed,
    bio: '刚下班',
    languageStyle: '短句',
    tone: '随口说',
    createdAt: DateTime(2026, 10, 18, 20, 1),
  );

  test('写进去能按帖子和 id 读出来', () async {
    await voices.insertAll([
      voice('voice_1', name: '大肥鱼', seed: 1),
      voice('voice_2', name: '楼下吉他手', seed: 2),
    ]);

    final list = await voices.byPost(postId);
    expect(list.map((v) => v.name), ['大肥鱼', '楼下吉他手']);

    final one = await voices.findById('voice_2');
    expect(one!.name, '楼下吉他手');
    expect(one.kind, PostVoiceKind.ephemeral);
    expect(one.avatarAsset, contains('avatar_'));
  });

  test('一批 id 一次查完，不存在的 id 不出现', () async {
    await voices.insertAll([
      voice('voice_1'),
      voice('voice_2', name: '另一个人'),
    ]);

    final map = await voices.byIds(['voice_1', 'voice_2', 'missing']);
    expect(map.keys, containsAll(['voice_1', 'voice_2']));
    expect(map.containsKey('missing'), isFalse);
  });

  test('软删之后名单里不再出现，但行还在', () async {
    await voices.insertAll([voice('voice_1')]);

    await voices.softDeleteByPost(postId);

    expect(await voices.byPost(postId), isEmpty);
    final rows = await db.select(db.postVoices).get();
    expect(rows, hasLength(1), reason: '只置 deleted_at，不删行');
    expect(rows.single.deletedAt, isNotNull);
  });

  test('同帖分配头像时尽量不撞', () async {
    final used = <int>{};
    for (var i = 0; i < 10; i++) {
      final asset = PostVoiceRepository.avatarFor(seed: i, used: used);
      final index = int.parse(
        asset.split('avatar_').last.replaceAll('.webp', ''),
      );
      // 池子是 0-based 的序号：avatar_001 对应 0
      expect(used.add(index - 1), isTrue, reason: '前 10 个不该重复');
    }
  });

  test('转成 AiPersona 时不带样例台词和音色', () {
    final persona = voice('voice_1').toPersona();
    expect(persona.id, 'voice_1');
    expect(persona.commentSamples, isEmpty);
    expect(persona.voiceModel, isEmpty);
    expect(persona.activeHours, isEmpty);
  });
}
