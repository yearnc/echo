import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media/image_payload.dart';
import '../../data/repositories/model_config_repository.dart';
import '../models/model_config.dart';
import '../models/post.dart';
import '../models/post_understanding.dart';
import 'model_gateway.dart';

/// 帖子解析：先看懂，再让网民说话。
///
/// 只做理解，不写评论；结果一次落库，所有临时网民共享。
class PostAnalyzer {
  PostAnalyzer(this._gateway);

  final ModelGateway _gateway;

  Future<PostUnderstanding?> analyze({
    required ModelConfig config,
    required Post post,
    ModelConfig? visionConfig,
  }) async {
    try {
      final raw = await _analyzeRaw(
        config: visionConfig ?? config,
        post: post,
        useImages: visionConfig != null,
      );
      return parse(
        raw,
        postId: post.id,
        model: (visionConfig ?? config).model,
      );
    } catch (error) {
      // 视觉模型不可用/不支持图片时退回纯文字，不让整条帖子解析失败。
      debugPrint('[解析] 带图解析失败，退回文字：$error');
      try {
        final raw = await _analyzeRaw(
          config: config,
          post: post,
          useImages: false,
        );
        return parse(raw, postId: post.id, model: config.model);
      } catch (fallbackError) {
        // 解析失败不算塌天：评论照常生成，只是不硬接梗。
        debugPrint('[解析] 这条帖子没看懂：$fallbackError');
        return null;
      }
    }
  }

  Future<String> _analyzeRaw({
    required ModelConfig config,
    required Post post,
    required bool useImages,
  }) async {
    final parts = useImages
        ? await ImagePayload.partsFromRefs(post.images)
        : const <Map<String, dynamic>>[];
    final text = userPrompt(post, imagesAttached: parts.isNotEmpty);

    if (parts.isEmpty) {
      return _gateway.complete(
        config: config,
        messages: [
          {'role': 'system', 'content': systemPrompt()},
          {'role': 'user', 'content': text},
        ],
        temperature: 0.2,
        maxTokens: 600,
        timeout: const Duration(seconds: 25),
      );
    }

    return _gateway.completeRich(
      config: config,
      messages: [
        {'role': 'system', 'content': systemPrompt()},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': text},
            ...parts,
          ],
        },
      ],
      temperature: 0.2,
      maxTokens: 600,
      timeout: const Duration(seconds: 30),
    );
  }

  static String systemPrompt() {
    return '''
你是一个“看懂帖子”的助手，只做理解，不写评论、不建议、不评价。

读帖子，输出一个 JSON：
- tone：玩梗 / 感伤 / 分享 / 吐槽 / 求助 / 炫耀 / 日常（选一个最贴近的）
- domain：游戏 / 行业 / 生活 / 情感 / 知识 / 其他
- entities：帖子提到的游戏名、角色、术语、梗名，最多 8 个
- point：一句话说清这条帖子在说什么（20 字以内）
- image_summary：如果帖子带了图，用 1—2 句写清画面里有什么、氛围/笑点在哪；没图或看不到图就留空
- joke_mechanism：如果是玩梗，笑点是什么（谐音 / 反差 / 自嘲 / 圈内黑话 / 剧情梗）；不是玩梗留空
- emotion：如果是感伤，情绪落在哪件事上；不是留空
- insider_angle：如果是游戏或行业，圈内人真正会接的那个点；不是留空
- angles：3—5 个**不同的人**可能接话的角度，每条 8 字以内，彼此不要重复
  （例：加班的共鸣 / 反讽吐槽 / 好奇问细节 / 自嘲更惨 / 圈内接梗 / 一句短评）
- needs_web：是否必须靠外部实时信息才能理解（新活动、新闻、刚发生的事）
- confidence：0—1，拿不准就写低

只输出 JSON，不要代码块、不要解释。''';
  }

  static String userPrompt(Post post, {bool imagesAttached = false}) {
    final buffer = StringBuffer()
      ..writeln('帖子正文：')
      ..writeln(post.content);
    final topic = post.topicName;
    if (topic != null && topic.trim().isNotEmpty) {
      buffer.writeln('（话题：#$topic）');
    }
    if (post.hasImages) {
      buffer.writeln(
        imagesAttached
            ? '（这条帖子还带了 ${post.images.length} 张图，图片已经附在这条消息里）'
            : '（这条帖子还带了 ${post.images.length} 张图；这次看不到图，'
                  '只能根据文字和话题判断，image_summary 留空）',
      );
    }
    return buffer.toString();
  }

  /// 解析并做基础校验。拿不准的字段留空，不猜。
  static PostUnderstanding? parse(
    String raw, {
    required String postId,
    required String model,
  }) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;

    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is! Map) return null;
      final data = Map<String, dynamic>.from(decoded);

      final tone = _string(data['tone']);
      final domain = _string(data['domain']);
      final point = _string(data['point']);
      if (tone == null && domain == null && point == null) return null;

      final entities = <String>[];
      final rawEntities = data['entities'];
      if (rawEntities is List) {
        for (final item in rawEntities) {
          if (item is! String) continue;
          final value = item.trim();
          if (value.isEmpty || entities.contains(value)) continue;
          entities.add(value);
          if (entities.length >= 8) break;
        }
      }

      final angles = <String>[];
      final rawAngles = data['angles'];
      if (rawAngles is List) {
        for (final item in rawAngles) {
          if (item is! String) continue;
          final value = item.trim();
          if (value.isEmpty || angles.contains(value)) continue;
          angles.add(value);
          if (angles.length >= 5) break;
        }
      }

      final confidenceRaw = data['confidence'];
      final confidence = confidenceRaw is num
          ? confidenceRaw.toDouble().clamp(0.0, 1.0)
          : 0.0;

      return PostUnderstanding(
        postId: postId,
        tone: tone ?? '',
        domain: domain ?? '',
        entities: entities,
        point: point ?? '',
        imageSummary: _string(data['image_summary']) ?? '',
        jokeMechanism: _string(data['joke_mechanism']) ?? '',
        emotion: _string(data['emotion']) ?? '',
        insiderAngle: _string(data['insider_angle']) ?? '',
        angles: angles,
        needsWeb: data['needs_web'] == true,
        confidence: confidence,
        model: model,
        updatedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _string(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }
}

final postAnalyzerProvider = Provider<PostAnalyzer>(
  (ref) => PostAnalyzer(ref.watch(modelGatewayProvider)),
);

/// 当前可用的图片理解配置；没配就是 null（帖子图片退回文字解析）。
final visionConfigProvider = FutureProvider<ModelConfig?>((ref) {
  ref.watch(modelConfigsProvider);
  return ref.watch(modelGatewayProvider).activeConfig(kind: ModelKind.vision);
});
