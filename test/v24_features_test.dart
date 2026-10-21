import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/media/media_service.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/post_voice_repository.dart';
import 'package:echo/data/repositories/sticker_repository.dart';
import 'package:echo/domain/models/post_voice.dart';
import 'package:echo/domain/models/sticker.dart';
import 'package:echo/domain/models/user_profile.dart';
import 'package:echo/domain/services/post_voice_generator.dart';
import 'package:echo/domain/services/user_identity_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('身份前缀', () {
    test('只写填过的字段，并带上称呼和性别', () {
      const profile = UserProfile(
        nickname: '程程',
        gender: 'male',
        occupation: '软件工程学生',
        city: '大连',
        preferredName: '小林',
      );

      final text = UserIdentityPrompt.build(profile);

      expect(text, contains('称呼他：小林'));
      expect(text, contains('性别：男'));
      expect(text, contains('身份／职业：软件工程学生'));
      expect(text, contains('所在城市：大连'));
      expect(text, isNot(contains('年龄段')));
    });

    test('什么都没填时返回空串，不往提示词里塞空壳', () {
      expect(UserIdentityPrompt.build(const UserProfile()), isEmpty);
    });
  });

  group('表情包选择', () {
    const comfort = StickerItem(
      id: 's1',
      name: '抱抱',
      category: 'custom',
      path: 'file:/tmp/comfort.png',
      tags: ['安慰', '抱抱'],
    );
    const roast = StickerItem(
      id: 's2',
      name: '就这',
      category: 'custom',
      path: 'file:/tmp/roast.png',
      tags: ['吐槽'],
    );

    test('求助语气只允许安慰类', () {
      final drafts = ModelPostVoiceGenerator.parseDrafts(
        '[{"name":"小满","status":"刚下班","action":"comment","comment":"抱抱你","sticker_id":"s2"}]',
        max: 1,
        allowLurk: false,
        stickers: const [comfort, roast],
        tone: '求助',
      );

      expect(drafts, hasLength(1));
      expect(drafts.single.stickerId, isNull);
      expect(drafts.single.comment, '抱抱你');
    });

    test('正常语气可以用吐槽类，并带上图片引用', () {
      final drafts = ModelPostVoiceGenerator.parseDrafts(
        '[{"name":"小满","status":"在等车","action":"comment","comment":"哈哈哈","sticker_id":"s2"}]',
        max: 1,
        allowLurk: false,
        stickers: const [comfort, roast],
        tone: '日常',
      );

      expect(drafts.single.stickerId, 's2');
      expect(drafts.single.stickerRef, 'file:/tmp/roast.png');
    });
  });

  group('浏览记录', () {
    late AppDatabase db;
    late PostRepository posts;
    late PostVoiceRepository voices;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      posts = PostRepository(db);
      voices = PostVoiceRepository(db);
    });

    tearDown(() async => db.close());

    test('我自己看过的帖子也算一个浏览者', () async {
      final postId = await posts.create(content: '今天天气不错');

      await voices.recordUserView(postId);
      await voices.recordUserView(postId);

      expect(await voices.viewCount(postId), 1);
      final viewers = await voices.viewers(postId);
      expect(viewers, hasLength(1));
      expect(viewers.single.isMe, isTrue);
      expect(viewers.single.voice.kind, PostVoiceKind.ephemeral);
    });

    test('别人的浏览和我各算一行', () async {
      final postId = await posts.create(content: '今天天气不错');
      await voices.insertAll([
        PostVoice(
          id: 'voice_1',
          postId: postId,
          kind: PostVoiceKind.ephemeral,
          name: '小满',
          createdAt: DateTime.now(),
        ),
      ]);
      await voices.recordView(postId: postId, voiceId: 'voice_1');
      await voices.recordUserView(postId);

      expect(await voices.viewCount(postId), 2);
      expect((await voices.viewers(postId)).length, 2);
    });
  });

  group('表情包仓库', () {
    late AppDatabase db;
    late StickerRepository stickers;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      stickers = StickerRepository(db, const MediaService());
    });

    tearDown(() async => db.close());

    test('只有带标签的表情会进 AI 目录', () async {
      await db
          .into(db.stickers)
          .insert(
            StickersCompanion.insert(
              id: 'tagged',
              name: '抱抱',
              category: 'custom',
              path: 'file:/tmp/a.png',
              tags: const Value('["安慰"]'),
              isUser: const Value(true),
            ),
          );
      await db
          .into(db.stickers)
          .insert(
            StickersCompanion.insert(
              id: 'untagged',
              name: '不知道啥',
              category: 'custom',
              path: 'file:/tmp/b.png',
              isUser: const Value(true),
            ),
          );

      final items = await stickers.taggedItems();

      expect(items.map((item) => item.id), ['tagged']);
      expect(items.single.tags, ['安慰']);
    });
  });
}
