import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/custom_resident_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/resident_memory_repository.dart';
import 'package:echo/domain/models/custom_resident.dart';
import 'package:echo/domain/models/post_understanding.dart';
import 'package:echo/domain/services/resident_memory_service.dart';

void main() {
  late AppDatabase db;
  late CustomResidentRepository residents;
  late ResidentMemoryRepository memories;
  late PostRepository posts;
  late ResidentMemoryService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    residents = CustomResidentRepository(db);
    memories = ResidentMemoryRepository(db);
    posts = PostRepository(db);
    service = ResidentMemoryService(memories: memories, residents: residents);

    await residents.upsert(
      CustomResident(
        id: 'r1',
        name: '小满',
        memoryLimit: 2,
        createdAt: DateTime(2026, 10, 18),
      ),
    );
  });

  tearDown(() async => db.close());

  test('记住一条帖子；同一来源不重复写', () async {
    final postId = await posts.create(content: '今天拍了晚霞', scope: 'echo');
    final post = (await posts.findById(postId))!;

    final first = await service.rememberPost(
      residentId: 'r1',
      post: post,
      understanding: PostUnderstanding(
        postId: postId,
        tone: '分享',
        domain: '生活',
        point: '拍到了晚霞',
        entities: const ['晚霞'],
        confidence: 0.8,
        updatedAt: DateTime(2026, 10, 18),
      ),
    );
    final second = await service.rememberPost(
      residentId: 'r1',
      post: post,
    );

    expect(first, isTrue);
    expect(second, isFalse);
    expect(await memories.count('r1'), 1);

    final list = await memories.recent('r1');
    expect(list.single.summary, contains('拍到了晚霞'));
    expect(list.single.tags, containsAll(['生活', '晚霞']));
  });

  test('带图的帖子会把图片摘要一起记住', () async {
    final postId = await posts.create(content: '今天的天空', scope: 'echo');
    await posts.attachImages(postId, ['file:/tmp/sky.jpg']);
    final post = (await posts.findById(postId))!;

    await service.rememberPost(
      residentId: 'r1',
      post: post,
      understanding: PostUnderstanding(
        postId: postId,
        tone: '分享',
        domain: '生活',
        point: '拍了天空',
        imageSummary: '一片橘色晚霞，云层很薄',
        confidence: 0.8,
        updatedAt: DateTime(2026, 10, 24),
      ),
    );

    final list = await memories.recent('r1');
    expect(list.single.summary, contains('带图'));
    expect(list.single.content, contains('橘色晚霞'));
  });

  test('记忆关掉的住民不写', () async {
    await residents.upsert(
      CustomResident(
        id: 'r2',
        name: '不记事',
        memoryEnabled: false,
        createdAt: DateTime(2026, 10, 18),
      ),
    );
    final postId = await posts.create(content: '一条帖子', scope: 'echo');
    final post = (await posts.findById(postId))!;

    expect(
      await service.rememberPost(residentId: 'r2', post: post),
      isFalse,
    );
    expect(await memories.count('r2'), 0);
  });

  test('记住用户回的那句话；同一父评论只记一次', () async {
    expect(
      await service.rememberUserReply(
        residentId: 'r1',
        reply: '我最近在准备考试',
        sourceId: 'comment_1',
      ),
      isTrue,
    );
    expect(
      await service.rememberUserReply(
        residentId: 'r1',
        reply: '我最近在准备考试',
        sourceId: 'comment_1',
      ),
      isFalse,
    );

    final list = await memories.recent('r1');
    expect(list.single.summary, contains('准备考试'));
  });

  test('超过住民自己的上限时归档最旧的', () async {
    for (var i = 0; i < 3; i++) {
      final postId = await posts.create(content: '第 $i 条', scope: 'echo');
      final post = (await posts.findById(postId))!;
      await service.rememberPost(residentId: 'r1', post: post);
    }

    expect(await memories.count('r1'), 2);
    final rows = await db.select(db.residentMemories).get();
    expect(rows, hasLength(3));
    expect(rows.where((row) => row.archivedAt != null), hasLength(1));
  });
}
