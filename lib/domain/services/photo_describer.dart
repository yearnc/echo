import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media/image_payload.dart';
import '../models/model_config.dart';
import 'model_gateway.dart';

/// 给一张本机图片写一句“它是什么”。
///
/// 以前私信图片进记忆时只写“对方发来一张图片”——这句话对下次聊天毫无用处，
/// 住民既不知道你在哪、也不知道你拍的是什么。现在发图时先用视觉模型
/// 描述一遍，再把描述写进记忆；模型看不懂图（没配 vision）时返回空，
/// 调用方仍然保留原来那句兜底。
class PhotoDescriber {
  const PhotoDescriber(this._gateway);

  final ModelGateway _gateway;

  Future<String> describe(String imageRef) async {
    if (imageRef.trim().isEmpty) return '';
    try {
      final config = await _pickConfig();
      if (config == null) return '';

      final part = await ImagePayload.partFromRef(imageRef);
      if (part == null) return '';

      final text = await _gateway.completeRich(
        config: config,
        messages: [
          {
            'role': 'system',
            'content':
                '你看图，然后只写一句客观描述，给一个没看过这张图的人听。'
                '不超过 40 字，中文。说清画面主体、正在发生什么、环境或氛围；'
                '不要猜人物身份、不要编地点、不要说“这张图片里”。',
          },
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': '描述这张图。'},
              part,
            ],
          },
        ],
        temperature: 0.2,
        maxTokens: 120,
        timeout: const Duration(seconds: 25),
      );
      return _clean(text);
    } catch (error) {
      // 描述失败不该让“图片已经发出去”这件事失败。
      debugPrint('[图片] 这次没描述成：$error');
      return '';
    }
  }

  /// 优先用专门配置的图片理解模型；没有时，用开了 supportsVision 的对话模型。
  Future<ModelConfig?> _pickConfig() async {
    final vision = await _gateway.activeConfig(kind: ModelKind.vision);
    if (vision != null) return vision;
    final chat = await _gateway.activeConfig();
    if (chat != null && chat.supportsVision) return chat;
    return null;
  }

  static String _clean(String raw) {
    var text = raw.trim();
    // 模型偶尔会带引号或“描述：”前缀，写进记忆时不好看。
    text = text.replaceFirst(RegExp(r'^(描述|图片描述)[：:]\s*'), '');
    text = text.replaceAll(RegExp(r'^["“”]|["“”]$'), '');
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    return text.length > 60 ? '${text.substring(0, 60)}…' : text;
  }
}

final photoDescriberProvider = Provider<PhotoDescriber>(
  (ref) => PhotoDescriber(ref.watch(modelGatewayProvider)),
);
