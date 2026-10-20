import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../data/repositories/private_message_repository.dart';
import '../../data/repositories/resident_memory_repository.dart';
import '../models/resident_memory.dart';

/// 一次动作的结果。工具调用要把它原样读给模型听。
class ActionOutcome {
  const ActionOutcome({
    required this.ok,
    this.message = '',
    this.data = const {},
  });

  final bool ok;
  final String message;
  final Map<String, dynamic> data;

  String toToolResult() => jsonEncode({
    'ok': ok,
    if (message.isNotEmpty) 'message': message,
    ...data,
  });
}

/// 所有副作用只有一个入口（v3.0 阶段三）。
///
/// 统一做四件事：参数校验、频率限制、幂等、日志。模型可以乱说话，
/// 但不能靠"重试一次"把同一句私信发两遍——`idempotencyKey` 唯一约束
/// 是这里最硬的一堵墙。
class ActionRegistry {
  ActionRegistry({
    required this.db,
    required this.residents,
    required this.memories,
    required this.messages,
    required this.posts,
  });

  final AppDatabase db;
  final CustomResidentRepository residents;
  final ResidentMemoryRepository memories;
  final PrivateMessageRepository messages;
  final PostRepository posts;

  /// 每个固定住民每天最多主动发几条私信、几条动态。
  static const int dailyDmLimit = 3;
  static const int dailyPostLimit = 1;

  /// 统一执行。任何异常都变成"动作失败"，不让它冒到心跳外面。
  Future<ActionOutcome> run({
    required String actorId,
    required String actorKind,
    required String action,
    required String idempotencyKey,
    String targetId = '',
    Map<String, dynamic> params = const {},
    String source = 'tool',
    required Future<ActionOutcome> Function() body,
  }) async {
    final existing =
        await (db.select(db.actionLogs)
              ..where((t) => t.idempotencyKey.equals(idempotencyKey)))
            .getSingleOrNull();
    if (existing != null) {
      return ActionOutcome(
        ok: true,
        message: '这一步已经做过了',
        data: {'replayed': true, 'result': existing.result},
      );
    }

    ActionOutcome outcome;
    try {
      outcome = await body();
    } catch (error) {
      debugPrint('[动作] $action 失败：$error');
      outcome = ActionOutcome(ok: false, message: '$error');
    }

    try {
      await db
          .into(db.actionLogs)
          .insert(
            ActionLogsCompanion.insert(
              id: 'act_${DateTime.now().microsecondsSinceEpoch}',
              actorId: actorId,
              actorKind: actorKind,
              action: action,
              targetId: Value(targetId),
              params: Value(jsonEncode(params)),
              source: Value(source),
              idempotencyKey: idempotencyKey,
              result: Value(
                outcome.ok
                    ? (outcome.message.isEmpty ? 'ok' : outcome.message)
                    : 'error: ${outcome.message}',
              ),
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    } catch (error) {
      // 日志写不进去不该让动作本身白做（比如消息已经发出去了）
      debugPrint('[动作] 这条日志没写进去：$error');
    }
    return outcome;
  }

  /// 固定住民主动发一条私信。
  Future<ActionOutcome> sendDirectMessage({
    required String residentId,
    required String content,
    required String idempotencyKey,
    DateTime? at,
    String source = 'tool',
  }) async {
    return run(
      actorId: residentId,
      actorKind: 'resident',
      action: 'send_dm',
      idempotencyKey: idempotencyKey,
      targetId: 'user',
      params: {'content': content},
      source: source,
      body: () async {
        final resident = await residents.findById(residentId);
        if (resident == null) {
          return const ActionOutcome(ok: false, message: '这个固定住民不在了');
        }
        final text = content.trim();
        if (text.isEmpty) {
          return const ActionOutcome(ok: false, message: '消息是空的');
        }
        if (await _todayCount(residentId, 'send_dm') >= dailyDmLimit) {
          return const ActionOutcome(ok: false, message: '今天的私信额度用完了');
        }
        await messages.scheduleIncoming(
          personaId: residentId,
          content: text,
          at: at ?? DateTime.now(),
        );
        return const ActionOutcome(ok: true, message: '已发出');
      },
    );
  }

  /// 固定住民自己发一条动态。
  Future<ActionOutcome> createResidentPost({
    required String residentId,
    required String content,
    required String idempotencyKey,
    String? topicName,
    DateTime? at,
    String source = 'tool',
  }) async {
    return run(
      actorId: residentId,
      actorKind: 'resident',
      action: 'create_post',
      idempotencyKey: idempotencyKey,
      params: {'content': content, 'topic': ?topicName},
      source: source,
      body: () async {
        final resident = await residents.findById(residentId);
        if (resident == null) {
          return const ActionOutcome(ok: false, message: '这个固定住民不在了');
        }
        final text = content.trim();
        if (text.isEmpty) {
          return const ActionOutcome(ok: false, message: '动态是空的');
        }
        if (await _todayCount(residentId, 'create_post') >= dailyPostLimit) {
          return const ActionOutcome(ok: false, message: '今天已经发过一条了');
        }
        final postId = await posts.createResidentPost(
          residentId: residentId,
          content: text,
          topicName: topicName,
          createdAt: at,
        );
        return ActionOutcome(ok: true, message: '已发布', data: {'postId': postId});
      },
    );
  }

  /// 检索记忆（工具调用用）。
  Future<ActionOutcome> searchMemories({
    required String residentId,
    required String query,
    int limit = 5,
    String source = 'tool',
  }) async {
    final resident = await residents.findById(residentId);
    if (resident == null || !resident.memoryEnabled) {
      return const ActionOutcome(ok: false, message: '这个人没有开启记忆');
    }
    final found = await memories.search(residentId, query, limit: limit);
    return ActionOutcome(
      ok: true,
      data: {'memories': [for (final item in found) _memoryJson(item)]},
    );
  }

  /// 读一条记忆的完整内容。
  Future<ActionOutcome> readMemory({
    required String residentId,
    required String memoryId,
  }) async {
    final found = await memories.search(residentId, '', limit: 400);
    for (final item in found) {
      if (item.id == memoryId) {
        return ActionOutcome(ok: true, data: {'memory': _memoryJson(item)});
      }
    }
    return const ActionOutcome(ok: false, message: '没有这条记忆');
  }

  /// 最近记下的几件事。
  Future<ActionOutcome> listRecentMemories({
    required String residentId,
    int limit = 5,
  }) async {
    final resident = await residents.findById(residentId);
    if (resident == null || !resident.memoryEnabled) {
      return const ActionOutcome(ok: false, message: '这个人没有开启记忆');
    }
    final recent = await memories.recent(residentId, limit: limit);
    return ActionOutcome(
      ok: true,
      data: {'memories': [for (final item in recent) _memoryJson(item)]},
    );
  }

  /// 写一条记忆。只有用户明确说"记住"时才允许调用。
  Future<ActionOutcome> writeMemory({
    required String residentId,
    required String summary,
    String content = '',
    List<String> tags = const [],
    String? sourceId,
    required String idempotencyKey,
  }) async {
    return run(
      actorId: residentId,
      actorKind: 'resident',
      action: 'memory_write',
      idempotencyKey: idempotencyKey,
      params: {'summary': summary},
      body: () async {
        final resident = await residents.findById(residentId);
        if (resident == null || !resident.memoryEnabled) {
          return const ActionOutcome(ok: false, message: '这个人没有开启记忆');
        }
        final text = summary.trim();
        if (text.isEmpty) {
          return const ActionOutcome(ok: false, message: '要记的内容是空的');
        }
        if (sourceId != null &&
            await memories.hasSource(
              residentId: residentId,
              sourceId: sourceId,
            )) {
          return const ActionOutcome(ok: true, message: '这件事已经记过了');
        }
        final now = DateTime.now();
        await memories.add(
          ResidentMemory(
            id: ResidentMemoryRepository.newId(),
            residentId: residentId,
            source: 'dm',
            sourceId: sourceId,
            summary: text,
            content: content.trim().isEmpty ? text : content.trim(),
            tags: tags,
            createdAt: now,
            updatedAt: now,
          ),
          limit: resident.memoryLimit,
        );
        return const ActionOutcome(ok: true, message: '记住了');
      },
    );
  }

  Future<int> _todayCount(String actorId, String action) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final count = db.actionLogs.id.count();
    final query = db.selectOnly(db.actionLogs)
      ..addColumns([count])
      ..where(
        db.actionLogs.actorId.equals(actorId) &
            db.actionLogs.action.equals(action) &
            db.actionLogs.createdAt.isBiggerOrEqualValue(start),
      );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  static Map<String, dynamic> _memoryJson(ResidentMemory memory) => {
    'id': memory.id,
    'summary': memory.summary,
    'content': memory.content,
    'tags': memory.tags,
    'at': memory.createdAt.toIso8601String(),
  };
}

final actionRegistryProvider = Provider<ActionRegistry>(
  (ref) => ActionRegistry(
    db: ref.watch(databaseProvider),
    residents: ref.watch(customResidentRepositoryProvider),
    memories: ref.watch(residentMemoryRepositoryProvider),
    messages: ref.watch(privateMessageRepositoryProvider),
    posts: ref.watch(postRepositoryProvider),
  ),
);
