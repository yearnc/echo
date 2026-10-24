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
      final imageSummary = (understanding?.imageSummary ?? '').trim();
      final hasImage = post.hasImages || imageSummary.isNotEmpty;
      if (point.isEmpty && content.isEmpty && !hasImage) return false;

      // 图片也是记忆的一部分：住民下次聊起这条帖子时，
      // 应该知道“他发过一张图，图里是……”，而不是只记得一行字。
      final what = point.isNotEmpty
          ? point
          : _clip(content, 40);
      final summary = hasImage
          ? '他发过一条带图的帖子：${what.isEmpty ? '没有文字说明' : what}'
          : '他发过一条帖子：$what';
      final memoryContent = [
        content,
        if (hasImage)
          '图片：${imageSummary.isEmpty ? '（没能识别出内容）' : _clip(imageSummary, 120)}',
      ].where((part) => part.trim().isNotEmpty).join('\n');
      final now = DateTime.now();

      await memories.add(
        ResidentMemory(
          id: ResidentMemoryRepository.newId(),
          residentId: residentId,
          source: 'post',
          sourceId: post.id,
          summary: summary,
          content: _clip(memoryContent, 240),
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
    /// 这句话从哪来：评论还是私信。记忆页按它显示来源，
    /// 以前不管从哪来都写死成 comment，私信内容会显示“来自评论”。
    String source = 'comment',

    /// 这条内容带图时的图片摘要。私信图片、评论表情包都走这里。
    String imageSummary = '',
  }) async {
    try {
      final resident = await residents.findById(residentId);
      if (resident == null || !resident.memoryEnabled) return false;
      final text = reply.trim();
      if (text.isEmpty && imageSummary.trim().isEmpty) return false;

      final key = sourceId ?? 'reply_${DateTime.now().microsecondsSinceEpoch}';
      if (sourceId != null &&
          await memories.hasSource(
            residentId: residentId,
            sourceId: sourceId,
          )) {
        return false;
      }

      final note = imageSummary.trim();
      final body = note.isEmpty
          ? _clip(text, 60)
          : '${_clip(text, 40)}（图片：${_clip(note, 80)}）';
      final now = DateTime.now();
      await memories.add(
        ResidentMemory(
          id: ResidentMemoryRepository.newId(),
          residentId: residentId,
          source: source,
          sourceId: key,
          summary: source == 'dm'
              ? '他私信你：$body'
              : '他回我：$body',
          content: _clip(note.isEmpty ? text : '$text\n图片：$note', 240),
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

  /// 记住“我自己做过什么”：发了哪条帖子、回了谁、给谁发了私信。
  ///
  /// 以前记忆里只有用户说过的话，所以住民醒来时只记得“对方”，不记得
  /// “我上次回了什么、他后来有没有再回我”。自己的行为也要进记忆，
  /// 一个人才像有连续的生活。
  Future<bool> rememberOwnAction({
    required String residentId,
    required String summary,
    required String sourceId,
    String source = 'self',
  }) async {
    try {
      final resident = await residents.findById(residentId);
      if (resident == null || !resident.memoryEnabled) return false;
      final text = summary.trim();
      if (text.isEmpty) return false;
      if (await memories.hasSource(
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
          source: source,
          sourceId: sourceId,
          summary: _clip(text, 60),
          content: _clip(text, 240),
          createdAt: now,
          updatedAt: now,
        ),
        limit: resident.memoryLimit,
      );
      return true;
    } catch (error) {
      debugPrint('[记忆] 自己的动作没记住：$error');
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
