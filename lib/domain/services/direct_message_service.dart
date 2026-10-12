import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/private_message_repository.dart';
import '../../data/repositories/relationship_repository.dart';
import '../models/ai_persona.dart';
import '../models/app_mode.dart';
import 'content_generator.dart';
import 'relationship_rules.dart';

/// 私信什么时候发生（B5）。挂在冷启动与心跳上，和世界 tick 一个待遇。
///
/// 两条路：
/// ① **他主动来找你**：关系到了互关以上的人，会在某个时候发来第一句。
///    陌生人不会来敲你的门——这一条完全靠 B4 的关系数据撑着。
/// ② **接你一句**：你刚说完话，他会回。时间戳落在几分钟之后，
///    所以你发完可以先干别的，回头再看。
///
/// 这里**不排"到点推送"**：不写通知、不打断你。私信是"回来才看见"的东西，
/// 红点在底部导航上等着就够了。
class DirectMessageService {
  DirectMessageService({
    required this.db,
    required this.messages,
    required this.relationships,
    required this.personas,
    required this.generator,
    Random? random,
  }) : _random = random ?? Random();

  final AppDatabase db;
  final PrivateMessageRepository messages;
  final RelationshipRepository relationships;
  final PersonaRepository personas;
  final ContentGenerator generator;

  final Random _random;

  /// 到哪一档才会主动来找你（互关）。
  static const int proactiveTier = 2;

  /// 两条主动私信之间至少隔这么久——不然一开 APP 收到三条"在吗"。
  static const Duration proactiveGap = Duration(hours: 20);

  /// 上一轮已经给谁排了主动私信（水位）。
  static const String lastProactiveKey = 'dm.lastProactiveAt';

  /// 回你一句大概要等多久。真人不会秒回，也不至于让你等到明天。
  static const Duration minReplyDelay = Duration(seconds: 40);
  static const Duration maxReplyDelay = Duration(minutes: 8);

  /// 主动开口的那一句，先搁一会儿再"送到"。
  static const Duration minOpeningDelay = Duration(minutes: 2);
  static const Duration maxOpeningDelay = Duration(minutes: 50);

  /// 一次 tick 最多处理几个"欠着回话"的会话。
  static const int maxRepliesPerTick = 3;

  /// 检查一遍，该发生的写进库。返回这次排了几条。
  Future<int> tick() async {
    if (!await _isEchoMode()) return 0;

    var written = 0;
    written += await _replyToUnanswered();
    written += await _maybeOpen();
    return written;
  }

  /// 你说完话还没人接的那些会话，让他接一句。
  Future<int> _replyToUnanswered() async {
    final awaiting = await messages.personaIdsAwaitingReply();
    if (awaiting.isEmpty) return 0;

    final pool = await personas.loadAll();
    final byId = {for (final persona in pool) persona.id: persona};

    final threads = <DirectThread>[];
    for (final id in awaiting.take(maxRepliesPerTick)) {
      final persona = byId[id];
      if (persona == null) continue;

      final turns = await messages.recentTurns(id);
      threads.add(
        DirectThread(
          persona: persona,
          recent: [
            for (final turn in turns)
              DirectTurn(fromMe: !turn.fromMe, text: turn.content),
          ],
        ),
      );
    }
    if (threads.isEmpty) return 0;

    final lines = await generator.directMessages(
      threads: threads,
      relations: await _relations(),
    );

    var written = 0;
    for (final thread in threads) {
      final line = lines[thread.persona.id]?.trim() ?? '';
      if (line.isEmpty) continue;

      await messages.scheduleIncoming(
        personaId: thread.persona.id,
        content: line,
        at: DateTime.now().add(_randomDuration(minReplyDelay, maxReplyDelay)),
      );
      written++;
    }
    return written;
  }

  /// 关系够近、又还没聊过的人，可能来敲你的门。
  Future<int> _maybeOpen() async {
    final now = DateTime.now();
    final last = await _lastProactiveAt();
    if (last != null && now.difference(last) < proactiveGap) return 0;

    final relations = await _relations();
    final pool = await personas.loadAll();

    final candidates = <AiPersona>[];
    for (final persona in pool) {
      if ((relations[persona.id]?.level ?? 0) < proactiveTier) continue;
      // 聊过的就不再"主动开场"——那是 B4 之前那种一眼假的搭讪
      if (await messages.lastAt(persona.id) != null) continue;
      candidates.add(persona);
    }
    if (candidates.isEmpty) return 0;

    final persona = candidates[_random.nextInt(candidates.length)];
    final lines = await generator.directMessages(
      threads: [DirectThread(persona: persona)],
      relations: relations,
    );
    final line = lines[persona.id]?.trim() ?? '';
    if (line.isEmpty) return 0;

    await messages.scheduleIncoming(
      personaId: persona.id,
      content: line,
      at: now.add(_randomDuration(minOpeningDelay, maxOpeningDelay)),
    );
    await _saveLastProactiveAt(now);
    return 1;
  }

  /// 读一次关系表。读不到就按"都是陌生"走——那意味着没人会来敲门，
  /// 而不是整个功能崩掉。
  Future<Map<String, RelationshipState>> _relations() async {
    try {
      return await relationships.loadAll();
    } catch (error) {
      debugPrint('[私信] 这次没读到关系：$error');
      return const {};
    }
  }

  Duration _randomDuration(Duration min, Duration max) {
    final low = min.inSeconds;
    final high = max.inSeconds;
    if (high <= low) return min;
    return Duration(seconds: low + _random.nextInt(high - low));
  }

  Future<DateTime?> _lastProactiveAt() async {
    final row =
        await (db.select(db.appSettings)
              ..where((t) => t.key.equals(lastProactiveKey)))
            .getSingleOrNull();
    final raw = int.tryParse(row?.value ?? '');
    return raw == null ? null : DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> _saveLastProactiveAt(DateTime at) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: lastProactiveKey,
            value: '${at.millisecondsSinceEpoch}',
            scope: const Value('echo'),
          ),
        );
  }

  /// 清醒模式里不该长出虚拟私信——那不是"安静下来"，那是又冒出一批假的。
  Future<bool> _isEchoMode() async {
    final row =
        await (db.select(db.appSettings)
              ..where((t) => t.key.equals('app.mode')))
            .getSingleOrNull();
    return row?.value != AppMode.clear.scope;
  }
}

final directMessageServiceProvider = Provider<DirectMessageService>(
  (ref) => DirectMessageService(
    db: ref.watch(databaseProvider),
    messages: ref.watch(privateMessageRepositoryProvider),
    relationships: ref.watch(relationshipRepositoryProvider),
    personas: ref.watch(personaRepositoryProvider),
    generator: ref.watch(contentSourceProvider),
  ),
);
