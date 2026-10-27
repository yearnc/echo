import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/resident_memory_repository.dart';
import '../models/custom_resident.dart';
import '../models/resident_memory.dart';
import 'chat_transcript_import.dart';
import 'model_gateway.dart';

class MemoryImportException implements Exception {
  const MemoryImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 把导入的聊天记录交给这位住民，让它自己整理成长期记忆（v3.9）。
///
/// 平台不替它挑哪句重要：这里只做两件事——把对话按“我说 / 你说”铺好，
/// 再把它写下来的条目落库。和平时唤醒里的记忆一样，来源标成 `import`，
/// 记忆页能看出“这些是从一段旧聊天里读来的”。
class ResidentMemoryImportService {
  const ResidentMemoryImportService({
    required this.memories,
    required this.gateway,
  });

  final ResidentMemoryRepository memories;
  final ModelGateway gateway;

  Future<int> import({
    required CustomResident resident,
    required List<ImportedTurn> turns,
  }) async {
    if (turns.isEmpty) {
      throw const MemoryImportException('没有可导入的对话');
    }
    final config = await gateway.configFor(configId: resident.modelConfigId);
    if (config == null) {
      throw const MemoryImportException('还没有配置可用的对话模型');
    }

    final transcript = StringBuffer();
    for (final turn in turns) {
      transcript.writeln('${turn.fromUser ? '我' : '你'}：${turn.text.trim()}');
    }

    final raw = await gateway.completeRich(
      config: config,
      temperature: 0.3,
      maxTokens: 2200,
      timeout: const Duration(seconds: 90),
      messages: [
        {
          'role': 'system',
          'content':
              '你在帮一个人把一段旧聊天整理成长期记忆。'
              '只挑关于“我”（对方）值得长期记住的事：偏好、经历、'
              '重要的人和地点、约定、情绪变化。'
              '不要记寒暄（你好、在吗）、不要逐句复述、不要编造。'
              '输出 JSON 数组，每项形如 '
              '{"summary":"一句话摘要","content":"细节","tags":["标签"]}，'
              '最多 25 条；没有值得记的就输出 []。只输出 JSON，不要解释。',
        },
        {'role': 'user', 'content': '聊天记录如下：\n$transcript'},
      ],
    );

    final items = _parseItems(raw);
    if (items.isEmpty) return 0;

    var written = 0;
    for (final item in items) {
      final summary = (item['summary'] as String?)?.trim() ?? '';
      final content = (item['content'] as String?)?.trim() ?? '';
      if (summary.isEmpty && content.isEmpty) continue;
      // 用内容本身派生 id：同一段对话再导入一次不会变成两份记忆。
      final stable = _stableId('$summary|$content');
      final id = 'mem_import_${resident.id}_$stable';
      final sourceId = 'import_$stable';
      if (await memories.hasSource(
        residentId: resident.id,
        sourceId: sourceId,
      )) {
        continue;
      }
      final now = DateTime.now();
      try {
        await memories.add(
          ResidentMemory(
            id: id,
            residentId: resident.id,
            source: 'import',
            sourceId: sourceId,
            summary: _clip(summary.isEmpty ? content : summary, 200),
            content: _clip(content, 2000),
            tags: _tags(item['tags']),
            createdAt: now,
            updatedAt: now,
          ),
          limit: resident.memoryLimit,
        );
        written += 1;
      } catch (error) {
        debugPrint('[导入] 这条记忆没写进去：$error');
      }
    }
    return written;
  }

  static List<Map<String, Object?>> _parseItems(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      // 模型爱把 JSON 包进代码块；把第一行和最后一个 ``` 去掉。
      final firstBreak = text.indexOf('\n');
      if (firstBreak >= 0) text = text.substring(firstBreak + 1);
      final end = text.lastIndexOf('```');
      if (end >= 0) text = text.substring(0, end);
      text = text.trim();
    }
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) {
      throw const MemoryImportException('模型没有按格式返回记忆，再试一次吧');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text.substring(start, end + 1));
    } catch (_) {
      throw const MemoryImportException('模型返回的记忆不是有效 JSON');
    }
    if (decoded is! List) return const [];
    return [
      for (final item in decoded.take(25))
        if (item is Map) item.cast<String, Object?>(),
    ];
  }

  static List<String> _tags(Object? raw) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is String && item.trim().isNotEmpty) _clip(item.trim(), 16),
      ].take(6).toList(growable: false);
    }
    if (raw is String) {
      return raw
          .split(RegExp(r'[,，\s]+'))
          .where((tag) => tag.trim().isNotEmpty)
          .map((tag) => _clip(tag.trim(), 16))
          .take(6)
          .toList(growable: false);
    }
    return const [];
  }

  /// 32 位 FNV-1a。只用来做去重键，不需要密码学强度。
  static String _stableId(String text) {
    var hash = 0x811c9dc5;
    for (final code in text.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String _clip(String text, int max) {
    final clean = text.trim();
    return clean.length <= max ? clean : '${clean.substring(0, max)}…';
  }
}

final residentMemoryImportServiceProvider =
    Provider<ResidentMemoryImportService>(
      (ref) => ResidentMemoryImportService(
        memories: ref.watch(residentMemoryRepositoryProvider),
        gateway: ref.watch(modelGatewayProvider),
      ),
    );
