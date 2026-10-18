import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/resident_memory_repository.dart';
import '../models/post.dart';
import '../models/post_understanding.dart';
import '../models/resident_memory.dart';

/// 固定住民“记住一件事”的入口。
///
/// 只记用户明确表达的事实、偏好、事件；不写推测。
/// 同一条来源只记一次；超过住民自己的上限就把最旧的归档。
class ResidentMemoryService {
  ResidentMemoryService({
    required this.memories,
    required this.residents,
  });

  final ResidentMemoryRepository memories;
  final CustomResidentRepository residents;

  /// 用户发了一条帖子，固定住民记住“他发过这个”。
  Future<bool> rememberPost({
    required String residentId,
    required Post post,
    PostUnderstanding? understanding,
  }) async {
    try {
      final resident = await residents.findById(residentId);
      if (resident == null || !resident.memoryEnabled) return false;
      if (await memories.hasSource(
        residentId: residentId,
        sourceId: post.id,
      )) {
        return false;
      }

      final point = (understanding?.point ?? '').trim();
      final content = post.content.trim();
      if (point.isEmpty && content.isEmpty) return false;

      final summary = point.isNotEmpty
          ? '他发过一条帖子：$point'
          : '他发过一条帖子：${_clip(content, 40)}';
      final now = DateTime.now();

      await memories.add(
        ResidentMemory(
          id: ResidentMemoryRepository.newId(),
          residentId: residentId,
          source: 'post',
          sourceId: post.id,
          summary: summary,
          content: _clip(content, 200),
          tags: _tags(understanding),
          createdAt: now,
          updatedAt: now,
        ),
        limit: resident.memoryLimit,
      );
      return true;
    } catch (error) {
      debugPrint('[记忆] 这条帖子没记住：$error');
      return false;
    }
  }

  /// 用户回了一句，固定住民记住“他跟我说过这个”。
  Future<bool> rememberUserReply({
    required String residentId,
    required String reply,
    String? sourceId,
  }) async {
    try {
      final resident = await residents.findById(residentId);
      if (resident == null || !resident.memoryEnabled) return false;
      final text = reply.trim();
      if (text.isEmpty) return false;

      final key = sourceId ?? 'reply_${DateTime.now().microsecondsSinceEpoch}';
      if (sourceId != null &&
          await memories.hasSource(
            residentId: residentId,
            sourceId: sourceId,
          )) {
        return false;
      }

      final now = DateTime.now();
      await memories.add(
        ResidentMemory(
          id: ResidentMemoryRepository.newId(),
          residentId: residentId,
          source: 'comment',
          sourceId: key,
          summary: '他回我：${_clip(text, 60)}',
          content: _clip(text, 200),
          createdAt: now,
          updatedAt: now,
        ),
        limit: resident.memoryLimit,
      );
      return true;
    } catch (error) {
      debugPrint('[记忆] 这句回复没记住：$error');
      return false;
    }
  }

  static List<String> _tags(PostUnderstanding? understanding) {
    if (understanding == null) return const [];
    return [
      if (understanding.domain.isNotEmpty) understanding.domain,
      ...understanding.entities.take(4),
    ];
  }

  static String _clip(String text, int length) {
    if (text.length <= length) return text;
    return '${text.substring(0, length)}…';
  }
}

final residentMemoryServiceProvider = Provider<ResidentMemoryService>(
  (ref) => ResidentMemoryService(
    memories: ref.watch(residentMemoryRepositoryProvider),
    residents: ref.watch(customResidentRepositoryProvider),
  ),
);
