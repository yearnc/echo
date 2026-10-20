import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/interaction_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/post_voice_repository.dart';
import '../../data/repositories/relationship_repository.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../models/ai_persona.dart';
import '../models/post.dart';
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
    this.voiceRepo,
    this.residentMemory,
    Random? random,
  }) : _random = random ?? Random();

  final InteractionRepository interactions;
  final PersonaRepository personas;
  final RelationshipRepository relationships;
  final UserProfileRepository userProfiles;
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
    voiceRepo: ref.watch(postVoiceRepositoryProvider),
    residentMemory: ref.watch(residentMemoryServiceProvider),
  ),
);
