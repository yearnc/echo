import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/private_message_repository.dart';
import '../../data/repositories/relationship_repository.dart';
import '../../data/repositories/resident_memory_repository.dart';
import '../models/ai_persona.dart';
import '../models/app_mode.dart';
import '../models/custom_resident.dart';
import '../models/model_config.dart';
import 'content_generator.dart';
import 'model_gateway.dart';
import 'relationship_rules.dart';
import 'resident_tool_session.dart';

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
    required this.residents,
    required this.memories,
    required this.generator,
    this.activeConfig,
    this.toolSession,
    Random? random,
  }) : _random = random ?? Random();

  final AppDatabase db;
  final PrivateMessageRepository messages;
  final RelationshipRepository relationships;
  final PersonaRepository personas;

  /// 固定住民（v3.0）：他们的私信不靠关系门槛，靠用户自己配置。
  final CustomResidentRepository residents;
  final ResidentMemoryRepository memories;
  final ContentGenerator generator;

  /// 固定住民回复时的 tool calling（可空：测试和没配模型时走批量生成）。
  final Future<ModelConfig?> Function()? activeConfig;
  final ResidentToolSession? toolSession;

  /// 服务商不支持 tools 时不再反复试：一次 400 之后整轮退回预检索。
  bool _toolsUnavailable = false;

  final Random _random;

  /// 到哪一档才会主动来找你（互关）。
  static const int proactiveTier = 2;

  /// 两条主动私信之间至少隔这么久——不然一开 APP 收到三条"在吗"。
  static const Duration proactiveGap = Duration(hours: 20);

  /// 上一轮已经给谁排了主动私信（水位）。
  static const String lastProactiveKey = 'dm.lastProactiveAt';

  /// 固定住民每人一条水位：一个人开过口了，不该挡住别人。
  static const String residentOpenedPrefix = 'dm.openedAt.';

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
  ///
  /// 会话对象有两种：用户自己配置的固定住民，和旧版本那批住民。
  /// 前者走人设 + 记忆，后者走原来那套关系数据。
  Future<int> _replyToUnanswered() async {
    final awaiting = await messages.personaIdsAwaitingReply();
    if (awaiting.isEmpty) return 0;

    final pool = await personas.loadAll();
    final byId = {for (final persona in pool) persona.id: persona};
    final residentById = {
      for (final resident in await residents.all()) resident.id: resident,
    };

    final threads = <DirectThread>[];
    final threadRelations = <String, RelationshipState>{};
    for (final id in awaiting.take(maxRepliesPerTick)) {
      final resident = residentById[id];
      final persona = resident?.toPersona() ?? byId[id];
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
      if (resident != null) {
        threadRelations[id] = RelationshipState(
          personaId: id,
          // 固定住民是用户自己请来的，不存在"陌生人不能聊"
          level: 1,
          memorySummary: await _memorySummary(id),
        );
      }
    }
    if (threads.isEmpty) return 0;

    // 固定住民先走 tool calling：能查记忆、能记事情、能自己发动态。
    // 模型不支持或这一步失败，就退回批量生成（人设 + 预检索的记忆摘要）。
    final lines = <String, String>{};
    final batch = <DirectThread>[];
    final config = _toolsUnavailable ? null : await activeConfig?.call();
    for (final thread in threads) {
      final resident = residentById[thread.persona.id];
      if (resident == null || config == null || toolSession == null) {
        batch.add(thread);
        continue;
      }
      try {
        final said = thread.recent.isEmpty
            ? ''
            : thread.recent.last.text;
        final line =
            (await toolSession!.reply(
              resident: resident,
              config: config,
              recent: thread.recent,
              latestUserMessage: said,
            ))?.trim() ??
            '';
        if (line.isEmpty) {
          batch.add(thread);
        } else {
          lines[thread.persona.id] = line;
        }
      } catch (error) {
        debugPrint('[私信] ${resident.name} 的工具调用没成，退回批量生成：$error');
        _toolsUnavailable = true;
        batch.add(thread);
      }
    }

    if (batch.isNotEmpty) {
      lines.addAll(
        await generator.directMessages(
          threads: batch,
          relations: {...await _relations(), ...threadRelations},
        ),
      );
    }

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

  /// 固定住民先来敲门：不靠关系门槛，靠用户自己配置。
  ///
  /// 配了开场白就用那句原话——它是用户替 TA 写的，模型再润色就变味了；
  /// 没配才让模型按人设起个头。
  Future<int> _maybeOpenResident() async {
    final now = DateTime.now();
    final all = await residents.all();
    if (all.isEmpty) return 0;

    final candidates = <CustomResident>[];
    for (final resident in all) {
      if (await messages.lastAt(resident.id) != null) continue;
      if (await _openedRecently(resident.id, now)) continue;
      candidates.add(resident);
    }
    if (candidates.isEmpty) return 0;

    final resident = candidates[_random.nextInt(candidates.length)];
    var line = resident.firstMessage.trim();
    if (line.isEmpty) {
      try {
        final lines = await generator.directMessages(
          threads: [DirectThread(persona: resident.toPersona())],
        );
        line = lines[resident.id]?.trim() ?? '';
      } catch (error) {
        debugPrint('[私信] ${resident.name} 的开场白没写出来：$error');
        return 0;
      }
    }
    if (line.isEmpty) return 0;

    await messages.scheduleIncoming(
      personaId: resident.id,
      content: line,
      at: now.add(_randomDuration(minOpeningDelay, maxOpeningDelay)),
    );
    await _saveOpenedAt(resident.id, now);
    return 1;
  }

  /// 关系够近、又还没聊过的人，可能来敲你的门。
  Future<int> _maybeOpen() async {
    final now = DateTime.now();
    if (await _maybeOpenResident() > 0) return 1;

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

  Future<bool> _openedRecently(String residentId, DateTime now) async {
    final row =
        await (db.select(db.appSettings)
              ..where((t) => t.key.equals('$residentOpenedPrefix$residentId')))
            .getSingleOrNull();
    final raw = int.tryParse(row?.value ?? '');
    if (raw == null) return false;
    return now.difference(DateTime.fromMillisecondsSinceEpoch(raw)) <
        proactiveGap;
  }

  Future<void> _saveOpenedAt(String residentId, DateTime at) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: '$residentOpenedPrefix$residentId',
            value: '${at.millisecondsSinceEpoch}',
            scope: const Value('echo'),
          ),
        );
  }

  /// 固定住民的记忆摘要：最多 5 条、300 字，只放这次对话里用得到的那几段。
  Future<String> _memorySummary(String residentId) async {
    final recent = await memories.recent(residentId, limit: 5);
    if (recent.isEmpty) return '';
    final text = recent.map((memory) => memory.toPromptLine()).join('；');
    return text.length > 300 ? '${text.substring(0, 300)}…' : text;
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
    residents: ref.watch(customResidentRepositoryProvider),
    memories: ref.watch(residentMemoryRepositoryProvider),
    generator: ref.watch(contentSourceProvider),
    activeConfig: ref.watch(modelGatewayProvider).activeConfig,
    toolSession: ref.watch(residentToolSessionProvider),
  ),
);
