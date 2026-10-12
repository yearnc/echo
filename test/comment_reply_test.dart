import 'dart:math';

import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/persona_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/relationship_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/services/comment_reply_service.dart';
import 'package:echo/domain/services/content_generator.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedPersonas implements PersonaRepository {
  _FixedPersonas(this.pool);

  final List<AiPersona> pool;

  @override
  Future<List<AiPersona>> loadAll() async => pool;
}

void main() {
  const persona = AiPersona(
    id: 'persona_001',
    name: '住民一',
    commentSamples: ['台词'],
  );

  late AppDatabase db;
  late PostRepository posts;
  late InteractionRepository interactions;
  late CommentReplyService service;
  late String postId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    posts = PostRepository(db);
    interactions = InteractionRepository(db);
    service = CommentReplyService(
      interactions: interactions,
      personas: _FixedPersonas(const [persona]),
      relationships: RelationshipRepository(db),
      generator: SampleContentGenerator(random: Random(5)),
      random: Random(5),
    );

    await db
        .into(db.aiPersonas)
        .insert(AiPersonasCompanion.insert(id: persona.id, name: persona.name));
    postId = await posts.create(content: '帖子', scope: 'echo');
  });

  tearDown(() async => db.close());

  PostComment theirs({String? parentId}) => PostComment(
    id: 'c1',
    postId: postId,
    personaId: persona.id,
    content: '我原来那句',
    parentId: parentId,
    createdAt: DateTime.now(),
  );

  Future<bool> followUp(PostComment parent) => service.maybeFollowUp(
    postId: postId,
    parent: parent,
    myReply: '我也是这么想的',
  );

  test('你回住民的评论，他会接一句（先搁几分钟）', () async {
    expect(await followUp(theirs()), isTrue);

    final rows = await db.select(db.aiInteractions).get();
    expect(rows.length, 1);
    expect(rows.single.parentId, 'c1', reason: '挂在你回的那条下面');
    expect(rows.single.status, 'pending');
    expect(
      rows.single.scheduledAt,
      greaterThan(DateTime.now().millisecondsSinceEpoch),
      reason: '真人不会秒回',
    );
  });

  test('你回自己说的话，没人需要接', () async {
    final mine = PostComment(
      id: 'c2',
      postId: postId,
      content: '我自己嘟囔一句',
      createdAt: DateTime.now(),
    );

    expect(await followUp(mine), isFalse);
    expect(await interactions.countPending(), 0);
  });

  test('楼只到两层：已经在回别人的回复了，就不再往下叠', () async {
    expect(await followUp(theirs(parentId: 'c0')), isFalse);
    expect(await interactions.countPending(), 0);
  });

  test('空的回复不排——他没什么可接的', () async {
    expect(
      await service.maybeFollowUp(
        postId: postId,
        parent: theirs(),
        myReply: '   ',
      ),
      isFalse,
    );
  });

  test('住民不在名单里时安静收场，不往外抛', () async {
    final stranger = PostComment(
      id: 'c3',
      postId: postId,
      personaId: 'persona_不存在',
      content: '我说了句什么',
      createdAt: DateTime.now(),
    );

    expect(await followUp(stranger), isFalse);
  });
}
