import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/notification_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/post_voice_repository.dart';
import 'package:echo/domain/models/echo_settings.dart';
import 'package:echo/domain/models/model_config.dart';
import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/models/post_understanding.dart';
import 'package:echo/domain/services/audience_service.dart';
import 'package:echo/domain/services/content_generator.dart';
import 'package:echo/domain/services/post_voice_generator.dart';

class _FakeGenerator implements PostVoiceGenerator {
  _FakeGenerator({this.drafts = const [], this.returnsEmpty = false});

  List<PostVoiceDraft> drafts;
  bool returnsEmpty;
  bool shouldThrow = false;
  int calls = 0;
  bool? lastAllowLurk;

  @override
  Future<List<PostVoiceDraft>> draft({
    required ModelConfig config,
    required Post post,
    required int count,
    required bool allowLurk,
    PostUnderstanding? understanding,
    DateTime? at,
    Set<String> avoidNames = const {},
    bool sendImagesDirectly = false,
  }) async {
    calls++;
    lastAllowLurk = allowLurk;
    if (shouldThrow) throw Exception('boom');
    if (returnsEmpty) return const [];
    // 逐人请求：每次交出一个还没用过的草稿。
    final available = drafts
        .where((draft) => !avoidNames.contains(draft.name))
        .take(count)
        .toList(growable: false);
    drafts = drafts
        .where((draft) => !available.contains(draft))
        .toList(growable: false);
    return available;
  }
}

void main() {
  late AppDatabase db;
  late PostRepository posts;
  late PostVoiceRepository voices;
  late InteractionRepository interactions;
  late String postId;

  const config = ModelConfig(
    id: 'chat',
    provider: 'deepseek',
    label: '测试',
    baseUrl: 'https://api.example.com',
    model: 'test-model',
    enabled: true,
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    posts = PostRepository(db);
    voices = PostVoiceRepository(db);
    interactions = InteractionRepository(db);
    postId = await posts.create(content: '第一颗钻石', scope: 'echo');
  });

  tearDown(() async => db.close());

  AudienceService build(
    _FakeGenerator generator, {
    ModelConfig? active,
    NotificationRepository? notifications,
    ContentGenerator? contentGenerator,
  }) => AudienceService(
    posts: posts,
    voices: voices,
    interactions: interactions,
    generator: generator,
    activeConfig: () async => active,
    notifications: notifications,
    contentGenerator: contentGenerator,
  );

  test('三个人：一个只读、一个只赞、一个评论', () async {
    final generator = _FakeGenerator(
      drafts: const [
        PostVoiceDraft(
          name: '只看不说话',
          status: '路过',
          action: VoiceAction.view,
        ),
        PostVoiceDraft(name: '点个赞', status: '刚下班', action: VoiceAction.like),
        PostVoiceDraft(
          name: '大肥鱼',
          status: '在等车',
          action: VoiceAction.likeComment,
          comment: '这颗钻石也太大了吧',
        ),
      ],
    );

    final count = await build(
      generator,
      active: config,
    ).prepare(postId: postId, density: ReplyDensity.auto);

    expect(count, 3);
    expect(await voices.byPost(postId), hasLength(3));
    expect(
      await voices.viewCount(postId),
      0,
      reason: '浏览到点才记，不在发帖瞬间 +8',
    );

    final rows = await db.select(db.aiInteractions).get();
    expect(
      rows,
      hasLength(6),
      reason: '三个人各一条浏览；评论的人也要点赞，所以点赞和评论各两条',
    );
    expect(rows.map((r) => r.type), containsAll(['view', 'like', 'comment']));
    final comment = rows.firstWhere((r) => r.type == 'comment');
    expect(comment.content, '这颗钻石也太大了吧');
    expect(
      rows.where((r) => r.type == 'like').map((r) => r.personaId),
      contains(comment.personaId),
      reason: '不再有“只评论不点赞”的旁路',
    );
  });

  test('同一条帖子只准备一次', () async {
    final generator = _FakeGenerator(
      drafts: const [
        PostVoiceDraft(name: '点个赞', status: '路过', action: VoiceAction.like),
      ],
    );
    final service = build(generator, active: config);

    await service.prepare(postId: postId, density: ReplyDensity.low);
    final callsAfterFirst = generator.calls;
    final second = await service.prepare(
      postId: postId,
      density: ReplyDensity.low,
    );

    expect(second, 1);
    expect(generator.calls, callsAfterFirst, reason: '第二次不该再请求模型');
    expect(await voices.byPost(postId), hasLength(1));
  });

  test('没有模型就一个人都不来', () async {
    final generator = _FakeGenerator(
      drafts: const [
        PostVoiceDraft(name: '点个赞', status: '路过', action: VoiceAction.like),
      ],
    );

    final count = await build(
      generator,
    ).prepare(postId: postId, density: ReplyDensity.auto);

    expect(count, 0);
    expect(generator.calls, 0);
    expect(await voices.byPost(postId), isEmpty);
  });

  test('模型没生出人就安静收场', () async {
    final generator = _FakeGenerator(returnsEmpty: true);
    final count = await build(
      generator,
      active: config,
    ).prepare(postId: postId, density: ReplyDensity.auto);

    expect(count, 0);
    expect(await voices.byPost(postId), isEmpty);
    expect(await db.select(db.aiInteractions).get(), isEmpty);
  });

  test('只读开关会传给生成器', () async {
    final generator = _FakeGenerator(returnsEmpty: true);
    await build(
      generator,
      active: config,
    ).prepare(postId: postId, density: ReplyDensity.low, allowLurk: false);

    expect(generator.lastAllowLurk, isFalse);
  });

  test('连续三次失败会在通知页留一条提醒', () async {
    final generator = _FakeGenerator()..shouldThrow = true;
    final notifications = NotificationRepository(db);
    final service = build(
      generator,
      active: config,
      notifications: notifications,
    );

    for (var i = 0; i < 3; i++) {
      await service.prepare(postId: postId, density: ReplyDensity.low);
    }

    final rows = await db.select(db.notificationLogs).get();
    expect(rows, isNotEmpty);
    expect(rows.first.title, contains('AI 回复暂时不可用'));
  });
}
