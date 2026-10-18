import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/model_config.dart';
import '../models/post.dart';
import '../models/post_understanding.dart';
import 'content_moderator.dart';
import 'model_gateway.dart';

/// 一个网民这次要做什么。
enum VoiceAction {
  view('view'),
  like('like'),
  comment('comment'),
  likeComment('like_comment');

  const VoiceAction(this.key);
  final String key;

  static VoiceAction? fromKey(String? raw) => switch (raw) {
    'view' => VoiceAction.view,
    'like' => VoiceAction.like,
    'comment' => VoiceAction.comment,
    'like_comment' => VoiceAction.likeComment,
    _ => null,
  };

  bool get wantsLike =>
      this == VoiceAction.like || this == VoiceAction.likeComment;
  bool get wantsComment =>
      this == VoiceAction.comment || this == VoiceAction.likeComment;
}

/// 模型给这一帖想出来的一位网民。
class PostVoiceDraft {
  const PostVoiceDraft({
    required this.name,
    required this.status,
    required this.action,
    this.comment = '',
  });

  final String name;

  /// 此刻的状态，一句话。
  final String status;
  final VoiceAction action;
  final String comment;
}

/// 临时网民生成器。
///
/// 失败就返回空：没有名字、没有内容，就不该硬凑一批人出来。
abstract interface class PostVoiceGenerator {
  Future<List<PostVoiceDraft>> draft({
    required ModelConfig config,
    required Post post,
    required int count,
    required bool allowLurk,
    PostUnderstanding? understanding,
  });
}

class ModelPostVoiceGenerator implements PostVoiceGenerator {
  ModelPostVoiceGenerator(this._gateway);

  final ModelGateway _gateway;

  @override
  Future<List<PostVoiceDraft>> draft({
    required ModelConfig config,
    required Post post,
    required int count,
    required bool allowLurk,
    PostUnderstanding? understanding,
  }) async {
    if (count <= 0) return const [];

    try {
      final raw = await _gateway.complete(
        config: config,
        messages: [
          {'role': 'system', 'content': systemPrompt(allowLurk: allowLurk)},
          {
            'role': 'user',
            'content': userPrompt(
              post: post,
              count: count,
              understanding: understanding,
            ),
          },
        ],
        temperature: 0.95,
        maxTokens: 900,
        timeout: const Duration(seconds: 30),
      );
      return parseDrafts(raw, max: count, allowLurk: allowLurk);
    } catch (error) {
      debugPrint('[临时网民] 这次没生成出来：$error');
      return const [];
    }
  }

  /// 系统提示词：只放**不变**的规则（后续 C2 会把它放进共享前缀）。
  static String systemPrompt({required bool allowLurk}) {
    final buffer = StringBuffer()
      ..writeln('你是「回响」里刷到这条帖子的一群普通人。请为这次围观起几个网名，')
      ..writeln('并决定每个人做什么。不是社区工作人员，也不是来开导谁的。')
      ..writeln()
      ..writeln('规则：')
      ..writeln('- 网名 2—6 个字，像真人网名：具体、有画面感，不要符号堆砌')
      ..writeln('- 每次起新的网名，不要重复固定住民或最近出现过的名字')
      ..writeln('- 不要火星文、冒犯词；几个人之间不能重名')
      ..writeln('- 每人一句「此刻的状态」，10—20 字：刚下班、在等车、睡不着、吃完在阳台站着')
      ..writeln('- 动作四选一：view（只看看）/ like（只点赞）/ comment（只评论）/ like_comment（点赞并评论）')
      ..writeln('- 动作大致比例：只读最多四分之一，至少一半的人要点赞或评论')
      ..writeln('- 人数 ≥ 4 时，至少 2 个人留下评论')
      ..writeln('- 评论 10—40 字，**必须接住帖子里的具体东西**（物件、动作、情绪、梗）')
      ..writeln('- 评论可以从这些角度挑：共鸣 / 吐槽 / 好奇提问 / 玩梗 / 说自己也这样 / 一句短评')
      ..writeln('- 如果给了「这条帖子已经看懂了」，顺着它写：玩梗就接梗，感伤就接情绪，游戏/行业用圈内角度')
      ..writeln('- 理解不确定时，宁可提问或围观，不要装懂')
      ..writeln('- 不总结、不升华、不说教；不用「加油哦」「抱抱你」「一切都会好的」「希望你能」')
      ..writeln('- 不要提到自己是 AI，不要解释自己在做什么');
    if (allowLurk) {
      buffer.writeln('- 允许有一部分人只是看看、不点赞也不评论');
    } else {
      buffer.writeln('- 每个人至少要点赞或评论，不能只看不说话');
    }
    buffer
      ..writeln()
      ..writeln('只输出一个 JSON 数组，不要代码块、不要任何解释：')
      ..writeln(
        '[{"name":"网名","status":"此刻的状态","action":"view|like|comment|like_comment","comment":"评论，没评论就留空"}]',
      );
    return buffer.toString();
  }

  /// 用户提示词：这一帖的快照 + 这次要几个人。
  static String userPrompt({
    required Post post,
    required int count,
    PostUnderstanding? understanding,
  }) {
    final buffer = StringBuffer()
      ..writeln('帖子正文：')
      ..writeln(post.content);

    final topic = post.topicName;
    if (topic != null && topic.trim().isNotEmpty) {
      buffer.writeln('（话题：#$topic）');
    }
    if (post.hasImages) {
      buffer.writeln(
        '（这条帖子还带了 ${post.images.length} 张图；你看不到图，'
        '只能根据文字和话题猜）',
      );
    }
    buffer.writeln('（发帖人：这个社区里的一个普通用户）');
    if (understanding != null) {
      buffer.writeln();
      buffer.writeln(understanding.toPromptBlock());
    }
    buffer.writeln();
    buffer.writeln('这次请生成 $count 个网民。');
    return buffer.toString();
  }

  /// 解析并做程序侧校验。
  ///
  /// 认不出来的条目宁可丢掉，也不猜：名字挂错人比少一个人糟糕。
  static List<PostVoiceDraft> parseDrafts(
    String raw, {
    required int max,
    required bool allowLurk,
  }) {
    final drafts = <PostVoiceDraft>[];
    final names = <String>{};

    // 模型很容易一口气生成一堆“只看看”。真实评论区里沉默的人多，
    // 但首屏全是零互动太冷清——只读最多占四分之一，多出来的转成点赞。
    final maxLurk = allowLurk ? (max / 4).ceil().clamp(1, 3) : 0;
    var lurkCount = 0;

    for (final item in _parseItems(raw, max)) {
      final name = _string(item['name']);
      if (name == null || name.runes.length < 2 || name.runes.length > 6) {
        continue;
      }
      if (!names.add(name)) continue;

      var action = VoiceAction.fromKey(_string(item['action']));
      if (action == null) continue;
      if (action == VoiceAction.view) {
        if (!allowLurk) continue;
        if (lurkCount >= maxLurk) {
          action = VoiceAction.like;
        } else {
          lurkCount++;
        }
      }

      final status = _string(item['status']) ?? '';
      var comment = _string(item['comment']) ?? '';

      if (action.wantsComment) {
        if (comment.isEmpty ||
            comment.runes.length > 60 ||
            ContentModerator.checkLocally(comment) != null) {
          // 评论不合格就退化成只点赞；不拿别的句子顶上。
          action = VoiceAction.like;
          comment = '';
        }
      } else {
        comment = '';
      }

      drafts.add(
        PostVoiceDraft(
          name: name,
          status: status,
          action: action,
          comment: comment,
        ),
      );
      if (drafts.length >= max) break;
    }

    return drafts;
  }

  static List<Map<String, dynamic>> _parseItems(String raw, int max) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];

    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String? _string(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

final modelPostVoiceGeneratorProvider = Provider<ModelPostVoiceGenerator>(
  (ref) => ModelPostVoiceGenerator(ref.watch(modelGatewayProvider)),
);
