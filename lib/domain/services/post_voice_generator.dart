import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media/image_payload.dart';
import '../../data/repositories/sticker_repository.dart';
import '../models/model_config.dart';
import '../models/post.dart';
import '../models/post_understanding.dart';
import '../models/sticker.dart';
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
    this.stickerId,
    this.stickerRef,
  });

  final String name;

  /// 此刻的状态，一句话。
  final String status;
  final VoiceAction action;
  final String comment;

  /// AI 选中的表情包（可选）。content 会写 stickerRef。
  final String? stickerId;
  final String? stickerRef;

  PostVoiceDraft copyWith({VoiceAction? action}) => PostVoiceDraft(
    name: name,
    status: status,
    action: action ?? this.action,
    comment: comment,
    stickerId: stickerId,
    stickerRef: stickerRef,
  );
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
    DateTime? at,
    Set<String> avoidNames = const {},
    bool sendImagesDirectly = false,
  });
}

class ModelPostVoiceGenerator implements PostVoiceGenerator {
  ModelPostVoiceGenerator(this._gateway, {this.stickers});

  final ModelGateway _gateway;
  final StickerRepository? stickers;

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
    if (count <= 0) return const [];

    final catalog = await stickers?.taggedItems() ?? const <StickerItem>[];
    try {
      final system = systemPrompt(allowLurk: allowLurk);
      final user = userPrompt(
        post: post,
        count: count,
        understanding: understanding,
        at: at,
        avoidNames: avoidNames,
        stickers: catalog,
      );
      final images = sendImagesDirectly && post.hasImages
          ? await ImagePayload.partsFromRefs(post.images)
          : const <Map<String, dynamic>>[];

      final raw = images.isEmpty
          ? await _gateway.complete(
              config: config,
              messages: [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': user},
              ],
              // 逐人请求时输出很小，温度略高一点，人与人之间更容易分开
              temperature: count == 1 ? 1.0 : 0.95,
              maxTokens: count == 1 ? 420 : 900,
              timeout: const Duration(seconds: 30),
            )
          : await _gateway.completeRich(
              config: config,
              messages: [
                {'role': 'system', 'content': system},
                {
                  'role': 'user',
                  'content': [
                    {'type': 'text', 'text': user},
                    ...images,
                  ],
                },
              ],
              temperature: count == 1 ? 1.0 : 0.95,
              maxTokens: count == 1 ? 420 : 900,
              timeout: const Duration(seconds: 30),
            );
      return parseDrafts(
        raw,
        max: count,
        allowLurk: allowLurk,
        stickers: catalog,
        tone: understanding?.tone ?? '',
      );
    } catch (error) {
      debugPrint('[临时网民] 这次没生成出来：$error');
      return const [];
    }
  }

  /// 系统提示词：只放**不变**的规则（后续 C2 会把它放进共享前缀）。
  static String systemPrompt({required bool allowLurk}) {
    final buffer = StringBuffer()
      ..writeln('你是「回响」里刷到这条帖子的一群普通人。请为这次围观起网名，')
      ..writeln('并决定每个人做什么。不是社区工作人员，也不是来开导谁的。')
      ..writeln()
      ..writeln('规则：')
      ..writeln('- 网名 2—6 个字，像真人网名：具体、有画面感，不要符号堆砌')
      ..writeln('- 每次起新的网名，不要重复固定住民或最近出现过的名字')
      ..writeln('- 不要火星文、冒犯词；几个人之间不能重名')
      ..writeln('- 每人一句「此刻的状态」，10—20 字：刚下班、在等车、睡不着、吃完在阳台站着')
      ..writeln('- 动作四选一：view（只看看）/ like（只点赞）/ comment（只评论）/ like_comment（点赞并评论）')
      ..writeln('- 动作大致比例：只读最多四分之一，至少一半的人要点赞或评论')
      ..writeln('- 评论 10—40 字，**必须接住帖子里的具体东西**（物件、动作、情绪、梗）')
      ..writeln('- 可以顺手带一张表情包（sticker_id），但只在真的合适时；没有合适的就留空')
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
        '[{"name":"网名","status":"此刻的状态","action":"view|like|comment|like_comment","comment":"评论，没评论就留空","sticker_id":"从给定列表里选，或留空"}]',
      );
    return buffer.toString();
  }

  /// 用户提示词：这一帖的快照 + 这次要几个人。
  ///
  /// 所有**会变**的东西都放这里：当前时间、已出现名单、这次几个人、
  /// 表情包目录。system 保持逐字节一致，缓存前缀才不会每请求分叉。
  static String userPrompt({
    required Post post,
    required int count,
    PostUnderstanding? understanding,
    DateTime? at,
    Set<String> avoidNames = const {},
    List<StickerItem> stickers = const [],
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
        understanding?.imageSummary.isNotEmpty == true
            ? '（这条帖子带了 ${post.images.length} 张图；画面内容见下面的“看懂了”）'
            : '（这条帖子还带了 ${post.images.length} 张图；这次看不到图，'
                  '只能根据文字和话题猜）',
      );
    }
    buffer.writeln('（发帖人：这个社区里的一个普通用户）');

    final moment = at ?? DateTime.now();
    buffer.writeln('（现在：${_timeLabel(moment)}）');

    if (understanding != null) {
      buffer.writeln();
      buffer.writeln(understanding.toPromptBlock());
    }

    if (avoidNames.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(
        '这一帖已经出现过的人：${avoidNames.take(24).join('、')}。'
        '请不要再用这些名字，也不要重复他们的角度。',
      );
    }

    if (stickers.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('可用表情包（只在真的合适时选一张，没有合适的就留空）：');
      for (final sticker in stickers.take(24)) {
        buffer.writeln(
          '- id=${sticker.id}｜标签=${sticker.tagLine}｜名称=${sticker.name}',
        );
      }
      buffer.writeln(
        '规则：sticker_id 只能从上面选；求助/难过时只选安慰、抱抱、陪伴、'
        '鼓励这类标签，不要用吐槽/看戏类；不要每条都发。',
      );
    }

    buffer.writeln();
    buffer.writeln('这次请生成 $count 个网民。');
    if (count <= 1) {
      buffer.writeln('只输出一个元素的数组，不要凑人头。');
    }
    return buffer.toString();
  }

  static String _timeLabel(DateTime at) {
    final phase = switch (at.hour) {
      >= 5 && < 8 => '清晨',
      >= 8 && < 11 => '上午',
      >= 11 && < 14 => '中午',
      >= 14 && < 17 => '下午',
      >= 17 && < 19 => '傍晚',
      >= 19 && < 23 => '晚上',
      _ => '深夜',
    };
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '${at.month}月${at.day}日 $phase $hh:$mm';
  }

  /// 解析并做程序侧校验。
  ///
  /// 认不出来的条目宁可丢掉，也不猜：名字挂错人比少一个人糟糕。
  static List<PostVoiceDraft> parseDrafts(
    String raw, {
    required int max,
    required bool allowLurk,
    List<StickerItem> stickers = const [],
    String tone = '',
  }) {
    final drafts = <PostVoiceDraft>[];
    final names = <String>{};
    final catalog = {for (final sticker in stickers) sticker.id: sticker};

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

      StickerItem? sticker;
      if (action.wantsComment) {
        final chosen = catalog[_string(item['sticker_id']) ?? ''];
        if (chosen != null && _stickerAllowed(chosen, tone)) {
          sticker = chosen;
        }
        final commentInvalid =
            comment.runes.length > 60 ||
            ContentModerator.checkLocally(comment) != null;
        if (commentInvalid) comment = '';
        if (comment.isEmpty && sticker == null) {
          // 既没有能用的评论、也没有合适的表情，就退化成只点赞；
          // 不拿别的句子顶上。
          action = VoiceAction.like;
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
          stickerId: sticker?.id,
          stickerRef: sticker?.path,
        ),
      );
      if (drafts.length >= max) break;
    }

    return drafts;
  }

  /// 难过/求助时只允许安慰类标签；正常语气不限制。
  static bool _stickerAllowed(StickerItem sticker, String tone) {
    final sad = const ['求助', '感伤', '难过', '低落', '丧', '焦虑']
        .any(tone.contains);
    if (!sad) return true;
    const comfort = ['安慰', '抱抱', '摸摸头', '陪伴', '鼓励', '递纸巾', '温柔'];
    return sticker.tags.any(
      (tag) => comfort.any((word) => tag.contains(word)),
    );
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
  (ref) => ModelPostVoiceGenerator(
    ref.watch(modelGatewayProvider),
    stickers: ref.watch(stickerRepositoryProvider),
  ),
);
