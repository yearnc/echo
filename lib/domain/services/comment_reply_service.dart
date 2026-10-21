import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/post_voice_repository.dart';
import '../../data/repositories/relationship_repository.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../models/ai_persona.dart';
import '../models/custom_resident.dart';
import '../models/post.dart';
import '../models/post_voice.dart';
import 'content_generator.dart';
import 'relationship_rules.dart';
import 'resident_memory_service.dart';

/// 住民接住你那句话（B7）。
///
/// 触发只有一种：**你在评论里回了某位住民**，他隔几分钟回来再说一句。
/// 这一条必须"有上文"——追问的全部意义就是接着上一句；
/// 没有上文的追问，就是一个人对着空气继续说。
///
/// 所以这里没有"随机让某个住民找个帖子追问"这种排期：那正是阶段 A 明令
/// 禁止的（同一个人在同一条帖子下平白多出一条语气不同的评论，一眼假）。
class CommentReplyService {
  CommentReplyService({
    required this.interactions,
    required this.personas,
    required this.relationships,
    required this.generator,
    required this.userProfiles,
    this.residents,
    this.voiceRepo,
    this.residentMemory,
    Random? random,
  }) : _random = random ?? Random();

  final InteractionRepository interactions;
  final PersonaRepository personas;
  final RelationshipRepository relationships;
  final UserProfileRepository userProfiles;

  /// 固定住民：楼主接住你的评论时要用他的人设。
  final CustomResidentRepository? residents;
  final ContentGenerator generator;

  /// 临时网民（v3.0）。可空：老测试和固定住民只走 personas。
  final PostVoiceRepository? voiceRepo;

  /// 固定住民记住“他回了我什么”。
  final ResidentMemoryService? residentMemory;

  final Random _random;

  /// 追问能挂到第几层。1 = 顶层评论的回复（楼上楼下两层，到头了）。
  static const int maxDepth = 1;

  /// 他隔多久回来。真人不会秒回，但楼中楼拖太久就凉了。
  static const Duration minDelay = Duration(minutes: 1);
  static const Duration maxDelay = Duration(minutes: 12);

  /// 你回了某条评论之后调用。返回这次有没有排上。
  Future<bool> maybeFollowUp({
    required String postId,
    required PostComment parent,
    required String myReply,
  }) async {
    final personaId = parent.personaId;
    // 回自己的人不用接；楼中楼只到两层，他已经是在回别人的回复了就不再加
    if (personaId == null || personaId.isEmpty) return false;
    if (parent.parentId != null) return false;

    final reply = myReply.trim();
    if (reply.isEmpty) return false;

    try {
      // 先看这是不是这一帖的临时网民；不是再回固定住民里找。
      final voice = await voiceRepo?.findById(personaId);
      AiPersona? persona = voice?.toPersona();
      if (persona == null) {
        final pool = await personas.loadAll();
        for (final item in pool) {
          if (item.id == personaId) persona = item;
        }
      }
      if (persona == null) return false;

      final lines = await generator.replies(
        threads: [
          ReplyThread(
            persona: persona,
            mine: parent.content ?? '',
            yours: reply,
          ),
        ],
        relations: await _relations(),
      );

      final line = lines[personaId]?.trim() ?? '';
      if (line.isEmpty) return false;

      // 他回的是"我"：评论区要能看出这一层关系，否则就是一句没头没尾的接话
      final myName = (await userProfiles.load())?.displayName ?? '我';

      await interactions.insertFollowUp(
        postId: postId,
        personaId: personaId,
        content: line,
        parentId: parent.id,
        replyToName: myName,
        scheduledAt: DateTime.now().add(_delay()),
      );

      // 固定住民把“他回了我这句”记下来；临时网民不记。
      final residentId = voice?.residentId;
      if (residentId != null) {
        await residentMemory?.rememberUserReply(
          residentId: residentId,
          reply: reply,
          sourceId: parent.id,
        );
      }
      return true;
    } catch (error) {
      // 排不上就排不上：你那条回复已经发出去了，社区少一句追问不算塌天
      debugPrint('[追问] 这次没排上：$error');
      return false;
    }
  }

  /// 你在固定住民的帖子下面直接评论（不是在回某条），楼主接一句。
  ///
  /// 和楼中楼共用同一套 `/replies` 提示词：把**帖子正文**当成楼主
  /// 说过的那句话，把**你的评论**当成别人回他的那句——语义刚好对得上。
  /// 这条以前完全没有：固定住民的帖子下面根本没有他的 voice 快照，
  /// 追问服务找不到人，评论区就一直静着。
  Future<bool> maybeAuthorReply({
    required String postId,
    required String residentId,
    required String postContent,
    required String myCommentId,
    required String myReply,
  }) async {
    final reply = myReply.trim();
    if (reply.isEmpty) return false;

    try {
      final resident = await residents?.findById(residentId);
      if (resident == null) return false;

      final voice = await _ensureVoice(postId: postId, resident: resident);
      final persona = voice?.toPersona() ?? resident.toPersona();

      final lines = await generator.replies(
        threads: [
          ReplyThread(
            persona: persona,
            mine: postContent,
            yours: reply,
          ),
        ],
      );
      final line = lines[persona.id]?.trim() ?? '';
      if (line.isEmpty) return false;

      final myName = (await userProfiles.load())?.displayName ?? '我';
      await interactions.insertFollowUp(
        postId: postId,
        personaId: persona.id,
        content: line,
        parentId: myCommentId,
        replyToName: myName,
        scheduledAt: DateTime.now().add(_delay()),
      );

      await residentMemory?.rememberUserReply(
        residentId: residentId,
        reply: reply,
        sourceId: myCommentId,
      );
      return true;
    } catch (error) {
      debugPrint('[楼主回复] 这次没排上：$error');
      return false;
    }
  }

  /// 保证楼主在这条帖子下有一个 voice 快照。
  ///
  /// 老帖子可能是在 v3.0 之前发的，作者没进 post_voices；
  /// 补一条之后，评论区的名字/头像、以及后续的追问都能认出来。
  Future<PostVoice?> _ensureVoice({
    required String postId,
    required CustomResident resident,
  }) async {
    final repo = voiceRepo;
    if (repo == null) return null;

    final id = 'voice_${resident.id}_$postId';
    final existing = await repo.findById(id);
    if (existing != null) return existing;

    final voice = PostVoice(
      id: id,
      postId: postId,
      kind: PostVoiceKind.custom,
      residentId: resident.id,
      name: resident.name,
      avatarAsset: resident.avatarAsset,
      bio: [resident.bio, resident.description, resident.scenario]
          .where((part) => part.trim().isNotEmpty)
          .join('\n'),
      languageStyle: [resident.languageStyle, resident.exampleDialogue]
          .where((part) => part.trim().isNotEmpty)
          .join('\n'),
      tone: [resident.tone, resident.extraInstructions]
          .where((part) => part.trim().isNotEmpty)
          .join('；'),
      createdAt: DateTime.now(),
    );
    await repo.insertAll([voice]);
    return voice;
  }

  Duration _delay() {
    final low = minDelay.inSeconds;
    final high = maxDelay.inSeconds;
    return Duration(seconds: low + _random.nextInt(high - low));
  }

  Future<Map<String, RelationshipState>> _relations() async {
    try {
      return await relationships.loadAll();
    } catch (error) {
      debugPrint('[追问] 这次没读到关系：$error');
      return const {};
    }
  }
}

final commentReplyServiceProvider = Provider<CommentReplyService>(
  (ref) => CommentReplyService(
    interactions: ref.watch(interactionRepositoryProvider),
    personas: ref.watch(personaRepositoryProvider),
    relationships: ref.watch(relationshipRepositoryProvider),
    generator: ref.watch(contentSourceProvider),
    userProfiles: ref.watch(userProfileRepositoryProvider),
    residents: ref.watch(customResidentRepositoryProvider),
    voiceRepo: ref.watch(postVoiceRepositoryProvider),
    residentMemory: ref.watch(residentMemoryServiceProvider),
  ),
);
