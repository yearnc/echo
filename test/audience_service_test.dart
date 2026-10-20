import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/custom_resident_repository.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/notification_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/post_voice_repository.dart';
import 'package:echo/data/repositories/resident_memory_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/domain/models/custom_resident.dart';
import 'package:echo/domain/models/echo_settings.dart';
import 'package:echo/domain/models/resident_post.dart';
import 'package:echo/domain/models/model_config.dart';
import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/models/post_understanding.dart';
import 'package:echo/domain/models/post_voice.dart';
import 'package:echo/domain/models/resident_memory.dart';
import 'package:echo/domain/services/audience_service.dart';
import 'package:echo/domain/services/content_generator.dart';
import 'package:echo/domain/services/post_voice_generator.dart';
import 'package:echo/domain/services/relationship_rules.dart';

class _FakeContent implements ContentGenerator {
  Map<String, RelationshipState>? lastRelations;

  @override
  Future<Map<String, String>> comments({
    required List<AiPersona> personas,
    required Post post,
    Map<String, RelationshipState> relations = const {},
  }) async {
    lastRelations = relations;
    return {for (final persona in personas) persona.id: '固定住民的评论'};
  }

  @override
  Future<List<ResidentPostDraft>> residentPosts({
    required List<ResidentMoment> moments,
  }) async => const [];

  @override
  Future<Map<String, String>> directMessages({
    required List<DirectThread> threads,
    Map<String, RelationshipState> relations = const {},
  }) async => const {};

  @override
  Future<Map<String, String>> replies({
    required List<ReplyThread> threads,
    Map<String, RelationshipState> relations = const {},
  }) async => const {};

  @override
  Future<String?> peerReply({required PeerReplyThread thread}) async => null;

  @override
  Future<void> prewarm({required Post post}) async {}
}

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
  }) async {
    calls++;
    lastAllowLurk = allowLurk;
    if (shouldThrow) throw Exception('boom');
    if (returnsEmpty) return const [];
    return drafts;
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
    CustomResidentRepository? customResidents,
    ResidentMemoryRepository? memories,
    ContentGenerator? contentGenerator,
  }) => AudienceService(
    posts: posts,
    voices: voices,
    interactions: interactions,
    generator: generator,
    activeConfig: () async => active,
    notifications: notifications,
    customResidents: customResidents,
    memories: memories,
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
          action: VoiceAction.comment,
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
      hasLength(5),
      reason: '三个人各一条浏览，另加一条点赞和一条评论',
    );
    expect(rows.map((r) => r.type), containsAll(['view', 'like', 'comment']));
    final comment = rows.firstWhere((r) => r.type == 'comment');
    expect(comment.content, '这颗钻石也太大了吧');
  });

  test('同一条帖子只准备一次', () async {
    final generator = _FakeGenerator(
      drafts: const [
        PostVoiceDraft(name: '点个赞', status: '路过', action: VoiceAction.like),
      ],
    );
    final service = build(generator, active: config);

    await service.prepare(postId: postId, density: ReplyDensity.low);
    final second = await service.prepare(
      postId: postId,
      density: ReplyDensity.low,
    );

    expect(second, 1);
    expect(generator.calls, 1, reason: '第二次不该再请求模型');
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

  test('固定住民每帖出现，带浏览和评论，并把记忆写进上下文', () async {
    final customRepo = CustomResidentRepository(db);
    final memoryRepo = ResidentMemoryRepository(db);
    final content = _FakeContent();
    final now = DateTime(2026, 10, 18, 21);
    await customRepo.upsert(
      CustomResident(
        id: 'r1',
        name: '小满',
        bio: '住楼下，爱拍照',
        alwaysShow: true,
        createdAt: now,
      ),
    );
    await memoryRepo.add(
      ResidentMemory(
        id: 'm1',
        residentId: 'r1',
        summary: '喜欢拍天空',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final count = await build(
      _FakeGenerator(returnsEmpty: true),
      active: config,
      customResidents: customRepo,
      memories: memoryRepo,
      contentGenerator: content,
    ).prepare(postId: postId, density: ReplyDensity.low);

    expect(count, 1);
    final list = await voices.byPost(postId);
    expect(list.single.kind, PostVoiceKind.custom);
    expect(list.single.residentId, 'r1');

    final rows = await db.select(db.aiInteractions).get();
    expect(
      rows.map((row) => row.type),
      containsAll(['view', 'comment']),
    );
    expect(
      content.lastRelations!.values.single.memorySummary,
      contains('喜欢拍天空'),
    );
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
