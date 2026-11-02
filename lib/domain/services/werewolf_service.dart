import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/game_repository.dart';
import '../../data/repositories/private_message_repository.dart';
import '../models/custom_resident.dart';
import '../models/game.dart';
import '../models/werewolf.dart';
import 'action_registry.dart';
import 'game_service.dart';
import 'model_gateway.dart';
import 'resident_context_service.dart';
import 'resident_tool_session.dart';
import 'tool_call_text.dart';

/// 简化版狼人杀（v50）。
///
/// 9 人局：3 狼、预言家、女巫、猎人、3 村民。用户 + 选中的固定住民，
/// 剩下的位置由内置 AI 玩家补足。固定住民按各自人设和身份通过模型
/// 发言、投票、夜里行动；AI 玩家用本地启发式，不再额外烧一轮模型。
///
/// 没有警长竞选，也没有复杂的遗言；保留“夜 → 公布 → 发言 → 投票 → 猎人”
/// 这条主线。所有状态存在 `game_states`，APP 被杀掉再回来还能接着玩。
class WerewolfService {
  WerewolfService({
    required this.repository,
    required this.residents,
    required this.messages,
    required this.gateway,
    required this.context,
    required this.session,
    required this.games,
    this.now = DateTime.now,
  });

  final GameRepository repository;
  final CustomResidentRepository residents;
  final PrivateMessageRepository messages;
  final ModelGateway gateway;
  final ResidentContextService context;
  final ResidentToolSession session;
  final GameService games;
  final DateTime Function() now;

  static const int playerCount = 9;
  static const List<String> _aiNames = [
    '阿岚',
    '老周',
    '小满',
    '陈默',
    '林野',
    '许知',
    '南星',
    '白露',
  ];

  /// 同一局同时只推进一次；模型可能要跑十几秒。
  final Set<String> _running = {};
  final Map<String, Future<void>> _locks = {};
  final Random _rand = Random();
  static final Random _staticRand = Random();

  Future<void> _serial(String matchId, Future<void> Function() action) async {
    if (_running.contains(matchId)) return;
    _running.add(matchId);
    final previous = _locks[matchId] ?? Future<void>.value();
    final gate = Completer<void>();
    _locks[matchId] = gate.future;
    try {
      await previous.catchError((Object _) {});
      await action();
    } finally {
      _running.remove(matchId);
      gate.complete();
      if (identical(_locks[matchId], gate.future)) {
        _locks.remove(matchId);
      }
    }
  }

  Future<ActionOutcome> _lockedOutcome(
    String matchId,
    Future<ActionOutcome> Function() action, {
    bool advanceAfter = true,
  }) async {
    if (_running.contains(matchId)) {
      return const ActionOutcome(ok: false, message: '正在结算，稍等一下');
    }
    ActionOutcome? result;
    await _serial(matchId, () async {
      result = await action();
    });
    // 提交完用户操作后锁已经释放，再推进下一阶段。
    if (advanceAfter && (result?.ok ?? false)) {
      unawaited(advance(matchId));
    }
    return result ?? const ActionOutcome(ok: false, message: '没有执行');
  }

  // ---------------------------------------------------------------------------
  // 开局
  // ---------------------------------------------------------------------------

  Future<GameMatch> startGame(List<String> residentIds) async {
    final picked = <CustomResident>[];
    for (final id in residentIds.take(8)) {
      final resident = await residents.findById(id);
      if (resident != null) picked.add(resident);
    }
    final roles = <WerewolfRole>[
      WerewolfRole.werewolf,
      WerewolfRole.werewolf,
      WerewolfRole.werewolf,
      WerewolfRole.seer,
      WerewolfRole.witch,
      WerewolfRole.hunter,
      WerewolfRole.villager,
      WerewolfRole.villager,
      WerewolfRole.villager,
    ]..shuffle(_rand);

    final aiNames = List<String>.of(_aiNames)..shuffle(_rand);
    final players = <_SeatPlayer>[
      _SeatPlayer(seat: 1, name: '你', isUser: true, role: roles[0]),
    ];
    var seat = 2;
    for (final resident in picked) {
      players.add(
        _SeatPlayer(
          seat: seat,
          name: resident.name,
          resident: resident,
          role: roles[seat - 1],
        ),
      );
      seat++;
    }
    for (var i = 0; seat <= playerCount; i++, seat++) {
      players.add(
        _SeatPlayer(
          seat: seat,
          name: aiNames[i % aiNames.length],
          role: roles[seat - 1],
        ),
      );
    }

    final match = await repository.createMatch(
      residentId: picked.isEmpty ? 'werewolf_ai' : picked.first.id,
      gameId: 'werewolf',
      board: '',
      turn: GameSide.user,
    );
    try {
      for (final player in players) {
        await repository.addPlayer(
          matchId: match.id,
          residentId: player.resident?.id ?? '',
          name: player.name,
          seat: player.seat,
          isUser: player.isUser,
          role: player.role.name,
          avatarAsset: player.resident?.avatarAsset ?? '',
        );
      }
      final state = WerewolfState(night: 1)..log = ['9 位玩家已经就位。天黑请闭眼。'];
      for (final player in players) {
        if (player.role == WerewolfRole.werewolf) {
          final allies = players
              .where((item) => item.role == WerewolfRole.werewolf)
              .map((item) => '${item.seat}号 ${item.name}')
              .join('、');
          state.privateLog[player.seat] = ['你是狼人。狼队友：$allies。'];
        }
      }
      await repository.saveState(match.id, state.toJson());
      await repository.updateMatch(
        id: match.id,
        board: state.encode(),
        turn: GameSide.user,
        moveCount: 0,
      );

      // 给被拉进来的固定住民留一张已接受的邀请卡，并在它们的上下文里
      // 写一句“你被拉进了一局狼人杀”，进对局时不用重新解释规则。
      final partyId = 'wolf_${match.id}';
      for (final resident in picked) {
        final invite = await repository.createInvite(
          residentId: resident.id,
          gameId: 'werewolf',
          initiator: 'user',
          partyId: partyId,
          note: '来一局狼人杀？',
        );
        await repository.resolveInvite(invite.id, GameInviteStatus.accepted);
        await repository.attachMatch(invite.id, match.id);
        final messageId = await messages.send(
          personaId: resident.id,
          content: invite.id,
          mediaType: 'game_invite',
          caption: '狼人杀 · 来一局？',
        );
        await repository.attachMessage(invite.id, messageId);
        final seatPlayer = players.firstWhere(
          (item) => item.resident?.id == resident.id,
        );
        context.appendMessage(resident.id, {
          'role': 'user',
          'content':
              '<system-reminder>[狼人杀] 对方拉你进了一局 9 人狼人杀，'
              '你是 ${seatPlayer.seat} 号，身份是「${seatPlayer.role.label}」。'
              '${seatPlayer.role.ability}'
              '夜里和白天都按你的身份行动；轮到你说话时，像平常一样说话。'
              '</system-reminder>',
        });
      }

      unawaited(advance(match.id));
      return match;
    } catch (error) {
      // 开局中途失败（比如旧版本留下的状态结构问题）不要留一局空房间。
      await repository.abandonMatch(match.id);
      rethrow;
    }
  }

  Stream<Map<String, dynamic>?> watchState(String matchId) => repository
      .watchState(matchId)
      .map(
        (json) => json == null ? null : WerewolfState.fromJson(json).toJson(),
      );

  Stream<List<GameMatchPlayer>> watchPlayers(String matchId) =>
      repository.watchPlayersFor(matchId);

  // ---------------------------------------------------------------------------
  // 推进
  // ---------------------------------------------------------------------------

  /// 根据当前阶段自动往下走；用户需要操作时会停下并写 `awaiting`。
  Future<void> advance(String matchId) => _serial(matchId, () async {
    final match = await repository.findMatch(matchId);
    if (match == null || match.gameId != 'werewolf' || !match.isActive) {
      return;
    }
    final state = await _loadState(matchId);
    if (state == null || state.isOver || state.awaitingUser) return;
    switch (state.phase) {
      case WerewolfPhase.night:
        await _advanceNight(matchId, state);
      case WerewolfPhase.sheriffElection:
        await _continueSheriffElection(matchId, state);
      case WerewolfPhase.speaking:
        await _continueSpeaking(matchId, state);
      case WerewolfPhase.voting:
        await _tallyVotes(matchId, state);
      case WerewolfPhase.dayAnnounce:
        await _dayAnnounce(matchId, state);
      case WerewolfPhase.hunter:
        await _hunterAct(matchId, state);
      case WerewolfPhase.over:
        break;
    }
  });

  Future<WerewolfState?> _loadState(String matchId) async {
    final json = await repository.loadState(matchId);
    return json == null ? null : WerewolfState.fromJson(json);
  }

  Future<void> _save(String matchId, WerewolfState state) async {
    await repository.saveState(matchId, state.toJson());
    // 棋盘字段只放一份进度快照，列表页不用解 game_states 也能显示“第几天”。
    await repository.updateMatch(
      id: matchId,
      board: state.encode(),
      turn: GameSide.user,
      moveCount: state.day + state.night,
    );
  }

  Future<void> _advanceNight(String matchId, WerewolfState state) async {
    final players = await repository.playersFor(matchId);
    final user = _user(players);
    final alive = players.where((item) => item.alive).toList();

    while (true) {
      switch (state.nightStage) {
        case 'wolves':
          final wolves = alive
              .where((item) => role(item) == WerewolfRole.werewolf)
              .toList();
          if (wolves.isEmpty) {
            state.nightStage = 'seer';
            continue;
          }
          // GameWeb 的狼人夜里先讨论一轮，再各自投票决定刀口。
          if (state.wolfDiscussion.isEmpty) {
            for (final wolf in wolves) {
              if (wolf.isUser) continue;
              final line = await _wolfTalk(wolf, players, state);
              if (line.isNotEmpty) {
                state.wolfDiscussion.add('${wolf.seat}号 ${wolf.name}：$line');
              }
            }
            if (state.wolfDiscussion.isNotEmpty) {
              for (final wolf in wolves) {
                _private(
                  state,
                  wolf.seat,
                  '狼队讨论：\n${state.wolfDiscussion.join('\n')}',
                );
              }
            }
          }
          if (user != null &&
              user.alive &&
              role(user) == WerewolfRole.werewolf) {
            state.awaiting = 'user_night';
            await _save(matchId, state);
            return;
          }
          final targets = <int>[];
          for (final wolf in wolves) {
            if (wolf.isUser) continue;
            final choice = await _askChoice(
              matchId,
              wolf,
              players,
              state,
              kind: 'wolf',
            );
            if (choice.target != null) targets.add(choice.target!);
          }
          state.nightKill = _majority(
            targets,
            fallback: _randomSeat(
              alive.where((item) => role(item) != WerewolfRole.werewolf),
            ),
          );
          for (final wolf in wolves) {
            _private(state, wolf.seat, '今晚你们刀了 ${state.nightKill} 号。');
          }
          state.nightStage = 'seer';
          await _save(matchId, state);
        case 'seer':
          final seer = _firstWhere(
            alive,
            (item) => role(item) == WerewolfRole.seer,
          );
          if (seer == null) {
            state.nightStage = 'witch';
            continue;
          }
          if (seer.isUser) {
            state.awaiting = 'user_night';
            await _save(matchId, state);
            return;
          }
          final choice = await _askChoice(
            matchId,
            seer,
            players,
            state,
            kind: 'seer',
          );
          final target =
              choice.target ??
              _randomSeat(alive.where((item) => item.seat != seer.seat));
          if (target != null) {
            final isWolf =
                role(_bySeat(players, target)) == WerewolfRole.werewolf;
            state.seerTarget = target;
            state.seerResult = isWolf;
            _private(
              state,
              seer.seat,
              '你查验了 $target 号：${isWolf ? '狼人' : '好人'}。',
            );
          }
          state.nightStage = 'witch';
          await _save(matchId, state);
        case 'witch':
          final witch = _firstWhere(
            alive,
            (item) => role(item) == WerewolfRole.witch,
          );
          if (witch == null) {
            state.nightStage = 'resolve';
            continue;
          }
          if (witch.isUser) {
            state.awaiting = 'user_night';
            await _save(matchId, state);
            return;
          }
          final choice = await _askChoice(
            matchId,
            witch,
            players,
            state,
            kind: 'witch',
          );
          if (choice.save == true && state.witchSaveAvailable) {
            state.saved = true;
            state.witchSaveAvailable = false;
            _private(state, witch.seat, '你用解药救了 ${state.nightKill} 号。');
          }
          if (choice.poison != null && state.witchPoisonAvailable) {
            state.poison = choice.poison;
            state.witchPoisonAvailable = false;
            _private(state, witch.seat, '你毒了 ${choice.poison} 号。');
          }
          state.nightStage = 'resolve';
          await _save(matchId, state);
        case 'resolve':
          await _resolveNight(matchId, state, players);
          return;
        default:
          state.nightStage = 'resolve';
      }
    }
  }

  Future<void> _resolveNight(
    String matchId,
    WerewolfState state,
    List<GameMatchPlayer> players,
  ) async {
    final deaths = <int>[];
    if (state.nightKill != null && !state.saved) {
      deaths.add(state.nightKill!);
    }
    if (state.poison != null && !deaths.contains(state.poison)) {
      deaths.add(state.poison!);
    }
    for (final seat in deaths) {
      await _kill(matchId, seat);
    }
    state.lastDeaths = deaths;
    state.endedByPoison = state.poison != null && deaths.contains(state.poison);
    if (deaths.isEmpty) {
      state.log.add('第 ${state.night} 夜是平安夜。');
    } else {
      for (final seat in deaths) {
        final player = _bySeat(players, seat);
        state.log.add('第 ${state.night} 夜，$seat 号 ${player?.name ?? '某人'} 死了。');
      }
    }
    // 猎人被毒杀不能开枪；被刀可以。
    final hunter = _firstWhere(
      players,
      (item) =>
          item.alive &&
          role(item) == WerewolfRole.hunter &&
          deaths.contains(item.seat),
    );
    final poisonedHunter =
        deaths.contains(hunter?.seat) &&
        state.poison != null &&
        state.poison == hunter?.seat;
    if (hunter != null && !poisonedHunter) {
      state.pendingHunter = hunter.seat;
      state.hunterAtNight = true;
      state.phase = WerewolfPhase.hunter;
      if (hunter.isUser) {
        state.awaiting = 'user_hunter';
      }
      await _save(matchId, state);
      if (hunter.isUser) return;
      await _hunterAct(matchId, state);
      return;
    }
    // 上面刚把死者标成出局，胜负判断必须用重新读出来的名单，
    // 不能拿“死之前”的快照。
    final refreshed = await repository.playersFor(matchId);
    await _afterDeaths(matchId, state, refreshed);
  }

  Future<void> _afterDeaths(
    String matchId,
    WerewolfState state,
    List<GameMatchPlayer> players,
  ) async {
    await _handleSheriffDeath(state, players);
    final winner = _checkWinner(players);
    if (winner != null) {
      await _finish(matchId, state, winner);
      return;
    }
    state.phase = WerewolfPhase.dayAnnounce;
    await _save(matchId, state);
    await _dayAnnounce(matchId, state);
  }

  Future<void> _dayAnnounce(String matchId, WerewolfState state) async {
    state.day += 1;
    state.nightStage = 'wolves';
    state.awaiting = '';
    state.votes = {};
    state.aiVotes = {};
    state.speeches = {};
    state.speechOrder = [];
    state.speechIndex = 0;
    state.wolfDiscussion = [];
    state.log.add('第 ${state.day} 天，天亮了。');
    final players = await repository.playersFor(matchId);
    final winner = _checkWinner(players);
    if (winner != null) {
      await _finish(matchId, state, winner);
      return;
    }
    // GameWeb 的规则：第一个白天先选警长，再按警长最后发言的顺序发言。
    if (state.day == 1 && !state.sheriffElectionDone) {
      state.phase = WerewolfPhase.sheriffElection;
      state.sheriffStage = 'candidacy';
      state.candidates = [];
      state.campaignSpeeches = {};
      state.sheriffVotes = {};
      state.runDecisions = {};
      state.campaignIndex = 0;
      state.log.add('第一天白天，先进行警长竞选。');
      await _save(matchId, state);
      await _continueSheriffElection(matchId, state);
      return;
    }
    await _save(matchId, state);
    await _startSpeaking(matchId, state, players);
  }

  @visibleForTesting
  static List<int> speechOrderFor(
    int day,
    List<GameMatchPlayer> players,
    int? sheriffId,
  ) => _buildSpeechOrder(day, players, sheriffId);

  static List<int> _buildSpeechOrder(
    int day,
    List<GameMatchPlayer> players,
    int? sheriffId,
  ) {
    final alive =
        players.where((item) => item.alive).map((item) => item.seat).toList()
          ..sort();
    final order = <int>[
      for (final seat in alive)
        if (seat != sheriffId) seat,
    ];
    // 蛇形顺序：偶数天倒着来；警长永远最后发言。
    if (day % 2 == 0) {
      final reversed = order.reversed.toList();
      order
        ..clear()
        ..addAll(reversed);
    }
    if (sheriffId != null && alive.contains(sheriffId)) {
      order.add(sheriffId);
    }
    return order;
  }

  Future<void> _startSpeaking(
    String matchId,
    WerewolfState state,
    List<GameMatchPlayer> players,
  ) async {
    state.phase = WerewolfPhase.speaking;
    state.awaiting = '';
    state.speechOrder = _buildSpeechOrder(state.day, players, state.sheriffId);
    state.speechIndex = 0;
    if (state.sheriffId != null) {
      state.log.add('警长：${state.sheriffId} 号，今天最后发言。');
    }
    await _save(matchId, state);
    await _continueSpeaking(matchId, state);
  }

  Future<void> _continueSpeaking(String matchId, WerewolfState state) async {
    final players = await repository.playersFor(matchId);
    while (state.speechIndex < state.speechOrder.length) {
      final seat = state.speechOrder[state.speechIndex];
      final player = _bySeat(players, seat);
      if (player == null || !player.alive) {
        state.speechIndex++;
        continue;
      }
      if (player.isUser) {
        state.awaiting = 'user_speech';
        await _save(matchId, state);
        return;
      }
      final text = (await _speechFor(matchId, player, players, state)).trim();
      if (text.isNotEmpty) {
        state.speeches[player.seat] = text;
        state.log.add('${player.seat}号 ${player.name}：$text');
      }
      state.speechIndex++;
      await _save(matchId, state);
    }
    state.awaiting = '';
    await _save(matchId, state);
    await _runVoting(matchId, state);
  }

  // ---------------------------------------------------------------------------
  // 警长竞选（GameWeb 规则）
  // ---------------------------------------------------------------------------

  Future<void> _continueSheriffElection(
    String matchId,
    WerewolfState state,
  ) async {
    if (state.sheriffElectionDone) {
      await _startSpeaking(
        matchId,
        state,
        await repository.playersFor(matchId),
      );
      return;
    }
    final players = await repository.playersFor(matchId);
    final alive = players.where((item) => item.alive).toList();
    final user = _user(players);

    if (state.sheriffStage == 'candidacy') {
      if (user != null &&
          user.alive &&
          !state.runDecisions.containsKey(user.seat)) {
        state.awaiting = 'user_sheriff_run';
        await _save(matchId, state);
        return;
      }
      for (final player in alive) {
        if (player.isUser) continue;
        if (state.runDecisions.containsKey(player.seat)) continue;
        state.runDecisions[player.seat] = await _sheriffRunDecision(
          player,
          players,
          state,
        );
      }
      state.candidates = [
        for (final entry in state.runDecisions.entries)
          if (entry.value && _bySeat(players, entry.key)?.alive == true)
            entry.key,
      ];
      if (state.candidates.isEmpty) {
        final fallback = _randomSeat(alive);
        state.sheriffId = fallback;
        state.sheriffElectionDone = true;
        state.sheriffStage = 'done';
        state.sheriffLog.add('无人上警，系统随机指定 $fallback 号警长');
        state.log.add('没有人上警，随机指定 $fallback 号担任警长。');
        await _save(matchId, state);
        await _startSpeaking(matchId, state, players);
        return;
      }
      state.sheriffStage = 'campaign';
      state.campaignIndex = 0;
      state.log.add('上警：${state.candidates.map((seat) => '$seat号').join('、')}');
      await _save(matchId, state);
      await _continueSheriffElection(matchId, state);
      return;
    }

    if (state.sheriffStage == 'campaign') {
      while (state.campaignIndex < state.candidates.length) {
        final seat = state.candidates[state.campaignIndex];
        final player = _bySeat(players, seat);
        if (player == null || !player.alive) {
          state.campaignIndex++;
          continue;
        }
        if (player.isUser) {
          state.awaiting = 'user_sheriff_speech';
          await _save(matchId, state);
          return;
        }
        final speech = (await _campaignSpeech(player, players, state)).trim();
        state.campaignSpeeches[seat] = speech;
        state.log.add('$seat号 ${player.name}（竞选警长）：$speech');
        state.campaignIndex++;
        await _save(matchId, state);
      }
      if (state.candidates.length == 1) {
        final elected = state.candidates.single;
        state.sheriffId = elected;
        state.sheriffElectionDone = true;
        state.sheriffStage = 'done';
        state.sheriffLog.add('$elected 号唯一候选，自动当选警长');
        state.log.add('$elected 号是唯一候选人，自动当选警长。');
        await _save(matchId, state);
        await _startSpeaking(matchId, state, players);
        return;
      }
      state.sheriffStage = 'vote';
      state.sheriffVotes = {};
      await _save(matchId, state);
      await _continueSheriffElection(matchId, state);
      return;
    }

    if (state.sheriffStage == 'vote') {
      final voters = alive
          .where((item) => !state.candidates.contains(item.seat))
          .toList();
      if (voters.isEmpty) {
        final elected =
            state.candidates[_rand.nextInt(state.candidates.length)];
        state.sheriffId = elected;
        state.sheriffElectionDone = true;
        state.sheriffStage = 'done';
        state.sheriffLog.add('没有非候选人可投票，随机指定 $elected 号警长');
        state.log.add('没有非候选人可投票，随机指定 $elected 号担任警长。');
        await _save(matchId, state);
        await _startSpeaking(matchId, state, players);
        return;
      }
      if (user != null &&
          user.alive &&
          voters.any((item) => item.seat == user.seat) &&
          !state.sheriffVotes.containsKey(user.seat)) {
        state.awaiting = 'user_sheriff_vote';
        await _save(matchId, state);
        return;
      }
      for (final voter in voters) {
        if (voter.isUser) continue;
        if (state.sheriffVotes.containsKey(voter.seat)) continue;
        state.sheriffVotes[voter.seat] = await _sheriffVoteFor(
          voter,
          players,
          state,
        );
      }
      final counts = <int, int>{};
      for (final target in state.sheriffVotes.values) {
        if (target <= 0 || !state.candidates.contains(target)) continue;
        counts[target] = (counts[target] ?? 0) + 1;
      }
      int? elected;
      var best = 0;
      var tied = <int>[];
      for (final entry in counts.entries) {
        if (entry.value > best) {
          best = entry.value;
          elected = entry.key;
          tied = [entry.key];
        } else if (entry.value == best) {
          tied.add(entry.key);
        }
      }
      if (elected == null) {
        elected = state.candidates[_rand.nextInt(state.candidates.length)];
      } else if (tied.length > 1) {
        elected = tied[_rand.nextInt(tied.length)];
      }
      state.sheriffId = elected;
      state.sheriffElectionDone = true;
      state.sheriffStage = 'done';
      state.sheriffLog.add('$elected 号当选警长');
      state.sheriffSummary = [
        '警长竞选：${state.candidates.map((seat) => '$seat号').join('、')}上警。',
        if (state.campaignSpeeches.isNotEmpty)
          '竞选发言：${state.campaignSpeeches.entries.map((e) => '${e.key}号：${e.value}').join('；')}',
        '投票结果：$elected 号当选警长。',
      ].join('\n');
      state.log.add('$elected 号当选警长（1.5 票，最后发言）。');
      await _save(matchId, state);
      await _startSpeaking(matchId, state, players);
      return;
    }

    // 意外状态：直接开始发言，别把游戏卡死。
    state.sheriffElectionDone = true;
    await _startSpeaking(matchId, state, players);
  }

  Future<bool> _sheriffRunDecision(
    GameMatchPlayer player,
    List<GameMatchPlayer> players,
    WerewolfState state,
  ) async {
    if (player.residentId.isEmpty) {
      final roleOfPlayer = role(player);
      return roleOfPlayer != WerewolfRole.villager
          ? _rand.nextDouble() < 0.75
          : _rand.nextDouble() < 0.2;
    }
    final resident = await residents.findById(player.residentId);
    if (resident == null) return false;
    final config =
        await gateway.configFor(configId: resident.modelConfigId) ??
        await gateway.activeConfig();
    if (config == null) return role(player) != WerewolfRole.villager;
    final prompt = [
      '你在玩 9 人狼人杀。你是 ${player.seat} 号「${resident.name}」，'
          '身份「${role(player).label}」。',
      '现在是第一天警长竞选报名。你要不要上警？上警会失去警长投票权，'
          '但可以在竞选发言里争取 1.5 票和最后发言。',
      '只回复 run 或 pass。',
    ].join('\n');
    try {
      final text = await _askText(resident, prompt, maxTokens: 20);
      final lower = text.toLowerCase();
      return lower.contains('run') && !lower.contains('pass');
    } catch (_) {
      return role(player) != WerewolfRole.villager;
    }
  }

  Future<String> _campaignSpeech(
    GameMatchPlayer player,
    List<GameMatchPlayer> players,
    WerewolfState state,
  ) async {
    if (player.residentId.isEmpty) {
      return '我上警是想把话说清楚，后面请大家把警徽票投给我。';
    }
    final resident = await residents.findById(player.residentId);
    if (resident == null) return '我上警，先听大家说。';
    final prompt = [
      '你在玩狼人杀，正在竞选警长。你是 ${player.seat} 号「${resident.name}」，'
          '身份「${role(player).label}」。',
      '说 1—2 句竞选发言：为什么投你、你会怎么带队。不要暴露身份，'
          '不要用 JSON，不要提 AI。',
    ].join('\n');
    try {
      return (await _askText(resident, prompt, maxTokens: 140)).trim();
    } catch (_) {
      return '我上警是想把节奏带起来，警徽票给我不会亏。';
    }
  }

  Future<int> _sheriffVoteFor(
    GameMatchPlayer voter,
    List<GameMatchPlayer> players,
    WerewolfState state,
  ) async {
    if (voter.residentId.isEmpty) {
      final candidates = state.candidates
          .where((seat) => seat != voter.seat)
          .toList();
      return candidates.isEmpty
          ? 0
          : candidates[_rand.nextInt(candidates.length)];
    }
    final resident = await residents.findById(voter.residentId);
    if (resident == null) return 0;
    final prompt = [
      '你在玩狼人杀，正在投警长票。你是 ${voter.seat} 号「${resident.name}」，'
          '身份「${role(voter).label}」。',
      '候选人：${state.candidates.map((seat) => '$seat号').join('、')}。',
      if (state.campaignSpeeches.isNotEmpty)
        '竞选发言：${state.campaignSpeeches.entries.map((e) => '${e.key}号：${e.value}').join('；')}',
      '只回复 {"target": 座位号}；弃权回复 {"target": 0}。',
    ].join('\n');
    try {
      final text = await _askText(resident, prompt, maxTokens: 60);
      return _parseChoice(text).target ?? 0;
    } catch (_) {
      return state.candidates.isEmpty
          ? 0
          : state.candidates[_rand.nextInt(state.candidates.length)];
    }
  }

  Future<String> _askText(
    CustomResident resident,
    String prompt, {
    int maxTokens = 120,
  }) async {
    final config =
        await gateway.configFor(configId: resident.modelConfigId) ??
        await gateway.activeConfig();
    if (config == null) throw StateError('no model');
    return sanitizeModelText(
      await gateway.completeRich(
        config: config,
        messages: [
          {'role': 'system', 'content': '只输出要求的内容，不要解释。'},
          {'role': 'user', 'content': prompt},
        ],
        temperature: 0.6,
        maxTokens: maxTokens,
        timeout: const Duration(seconds: 16),
      ),
    );
  }

  Future<void> _runVoting(String matchId, WerewolfState state) async {
    state.phase = WerewolfPhase.voting;
    state.awaiting = '';
    final players = await repository.playersFor(matchId);
    final alive = players.where((item) => item.alive).toList();
    final votes = await Future.wait([
      for (final player in alive) _voteFor(matchId, player, players, state),
    ]);
    final aiVotes = <int, int>{};
    for (var i = 0; i < alive.length; i++) {
      final player = alive[i];
      if (player.isUser) continue;
      aiVotes[player.seat] = votes[i];
    }
    state.aiVotes = aiVotes;
    final user = _user(players);
    if (user != null && user.alive) {
      state.awaiting = 'user_vote';
      await _save(matchId, state);
      return;
    }
    await _save(matchId, state);
    await _tallyVotes(matchId, state);
  }

  Future<void> _tallyVotes(String matchId, WerewolfState state) async {
    final combined = <int, int>{...state.aiVotes, ...state.votes};
    // 警长 1.5 票；用 double 统计，平票按数值相等判断。
    final counts = <int, double>{};
    for (final entry in combined.entries) {
      final target = entry.value;
      if (target <= 0) continue;
      final weight = entry.key == state.sheriffId ? 1.5 : 1.0;
      counts[target] = (counts[target] ?? 0) + weight;
    }
    int? exiled;
    var best = 0.0;
    var tied = false;
    for (final entry in counts.entries) {
      if (entry.value > best) {
        best = entry.value;
        exiled = entry.key;
        tied = false;
      } else if ((entry.value - best).abs() < 0.001) {
        tied = true;
      }
    }
    if (counts.isNotEmpty) {
      final detail = counts.entries
          .map((entry) => '${entry.key}号 ${entry.value}票')
          .join('，');
      state.log.add('票型：$detail');
    }
    if (tied || exiled == null) {
      state.log.add('投票平票，这一轮没有人被放逐。');
    } else {
      final player = await repository.playersFor(matchId);
      final target = _bySeat(player, exiled);
      state.log.add('投票结果：$exiled 号 ${target?.name ?? '某人'} 被放逐。');
      await _kill(matchId, exiled);
      await _handleSheriffDeath(state, await repository.playersFor(matchId));
      final roleOfTarget = role(target);
      if (roleOfTarget == WerewolfRole.hunter) {
        state.pendingHunter = exiled;
        state.hunterAtNight = false;
        state.phase = WerewolfPhase.hunter;
        state.awaiting = target?.isUser == true ? 'user_hunter' : '';
        await _save(matchId, state);
        if (target?.isUser == true) return;
        await _hunterAct(matchId, state);
        return;
      }
    }
    final players = await repository.playersFor(matchId);
    final winner = _checkWinner(players);
    if (winner != null) {
      await _finish(matchId, state, winner);
      return;
    }
    await _nextNight(matchId, state);
  }

  /// 警长死亡后自动移交警徽（GameWeb 里还有“撕警徽”的选择，
  /// 这里先做自动移交，保证 1.5 票不会因为死亡直接失效）。
  Future<void> _handleSheriffDeath(
    WerewolfState state,
    List<GameMatchPlayer> players,
  ) async {
    final sheriffId = state.sheriffId;
    if (sheriffId == null) return;
    final sheriff = _bySeat(players, sheriffId);
    if (sheriff != null && sheriff.alive) return;
    final alive = players.where((item) => item.alive).toList();
    if (alive.isEmpty) {
      state.sheriffId = null;
      return;
    }
    final successor = alive[_rand.nextInt(alive.length)].seat;
    state.sheriffId = successor;
    state.sheriffLog.add('警长 $sheriffId 号死亡，警徽移交给 $successor 号');
    state.log.add('警长 $sheriffId 号死亡，警徽移交给 $successor 号。');
  }

  Future<void> _hunterAct(String matchId, WerewolfState state) async {
    final seat = state.pendingHunter;
    if (seat == null) {
      await _nextNight(matchId, state);
      return;
    }
    final players = await repository.playersFor(matchId);
    final hunter = _bySeat(players, seat);
    if (hunter == null) {
      await _afterHunterShot(matchId, state, players);
      return;
    }
    if (hunter.isUser) {
      state.awaiting = 'user_hunter';
      await _save(matchId, state);
      return;
    }
    final choice = await _askChoice(
      matchId,
      hunter,
      players,
      state,
      kind: 'hunter',
    );
    final target =
        choice.target ??
        _randomSeat(players.where((item) => item.alive && item.seat != seat));
    if (target != null) {
      final targetPlayer = _bySeat(players, target);
      state.log.add('$seat 号 猎人开枪带走了 $target 号 ${targetPlayer?.name ?? ''}。');
      await _kill(matchId, target);
    }
    final after = await repository.playersFor(matchId);
    await _afterHunterShot(matchId, state, after);
  }

  /// 猎人开完枪后：夜里死的进白天，白天放逐的直接进下一夜。
  Future<void> _afterHunterShot(
    String matchId,
    WerewolfState state,
    List<GameMatchPlayer> players,
  ) async {
    await _handleSheriffDeath(state, players);
    final winner = _checkWinner(players);
    if (winner != null) {
      await _finish(matchId, state, winner);
      return;
    }
    if (state.hunterAtNight) {
      state.hunterAtNight = false;
      await _afterDeaths(matchId, state, players);
    } else {
      await _nextNight(matchId, state);
    }
  }

  Future<void> _nextNight(String matchId, WerewolfState state) async {
    state.phase = WerewolfPhase.night;
    state.night += 1;
    state.nightStage = 'wolves';
    state.awaiting = '';
    state.nightKill = null;
    state.saved = false;
    state.poison = null;
    state.seerTarget = null;
    state.seerResult = null;
    state.pendingHunter = null;
    state.hunterAtNight = false;
    state.votes = {};
    state.aiVotes = {};
    state.speeches = {};
    state.lastDeaths = [];
    state.speechOrder = [];
    state.speechIndex = 0;
    state.wolfDiscussion = [];
    state.log.add('第 ${state.night} 夜，天黑请闭眼。');
    await _save(matchId, state);
    await _advanceNight(matchId, state);
  }

  Future<void> _finish(
    String matchId,
    WerewolfState state,
    String winner,
  ) async {
    state.phase = WerewolfPhase.over;
    state.awaiting = '';
    state.winner = winner;
    state.log.add(winner == 'good' ? '好人阵营获胜。' : '狼人阵营获胜。');
    await _save(matchId, state);
    try {
      final players = await repository.playersFor(matchId);
      for (final player in players) {
        if (player.residentId.isEmpty) continue;
        context.appendMessage(player.residentId, {
          'role': 'user',
          'content':
              '<system-reminder>[狼人杀] 这一局结束了，'
              '${winner == 'good' ? '好人阵营获胜' : '狼人阵营获胜'}。'
              '你是 ${player.seat} 号 ${player.name}，身份「${WerewolfRole.fromKey(player.role).label}」。'
              '想留什么就自己写进记忆；不用在这里复述整局。'
              '</system-reminder>',
        });
      }
    } catch (error) {
      debugPrint('[狼人杀] 结束语没写进上下文：$error');
    }
    await repository.updateMatch(
      id: matchId,
      board: state.encode(),
      turn: GameSide.user,
      moveCount: state.day + state.night,
      status: GameMatchStatus.finished,
      result: winner,
    );
  }

  // ---------------------------------------------------------------------------
  // 用户操作
  // ---------------------------------------------------------------------------

  Future<ActionOutcome> submitNight({
    required String matchId,
    int? target,
    bool? save,
    int? poison,
  }) => _lockedOutcome(matchId, () async {
    final state = await _loadState(matchId);
    if (state == null || state.phase != WerewolfPhase.night) {
      return const ActionOutcome(ok: false, message: '现在不是夜晚');
    }
    final players = await repository.playersFor(matchId);
    final user = _user(players);
    if (user == null || !user.alive) {
      return const ActionOutcome(ok: false, message: '你已经出局了');
    }
    final roleOfUser = role(user);
    if (state.awaiting != 'user_night') {
      return const ActionOutcome(ok: false, message: '现在不用你行动');
    }
    if (roleOfUser == WerewolfRole.werewolf) {
      if (target == null) {
        return const ActionOutcome(ok: false, message: '选一个目标');
      }
      state.nightKill = target;
      state.nightStage = 'seer';
    } else if (roleOfUser == WerewolfRole.seer) {
      if (target == null) {
        return const ActionOutcome(ok: false, message: '选一个查验目标');
      }
      final isWolf = role(_bySeat(players, target)) == WerewolfRole.werewolf;
      state.seerTarget = target;
      state.seerResult = isWolf;
      state.nightStage = 'witch';
      _private(state, user.seat, '你查验了 $target 号：${isWolf ? '狼人' : '好人'}。');
    } else if (roleOfUser == WerewolfRole.witch) {
      if (save == true && state.witchSaveAvailable) {
        state.saved = true;
        state.witchSaveAvailable = false;
      }
      if (poison != null && state.witchPoisonAvailable) {
        state.poison = poison;
        state.witchPoisonAvailable = false;
      }
      state.nightStage = 'resolve';
    } else {
      state.nightStage = 'resolve';
    }
    state.awaiting = '';
    await _save(matchId, state);
    return const ActionOutcome(ok: true, message: '行动已提交');
  });

  Future<ActionOutcome> submitSpeech({
    required String matchId,
    required String text,
  }) => _lockedOutcome(matchId, () async {
    final state = await _loadState(matchId);
    if (state == null || state.phase != WerewolfPhase.speaking) {
      return const ActionOutcome(ok: false, message: '现在不是发言阶段');
    }
    final clean = text.trim();
    if (clean.isNotEmpty) {
      final players = await repository.playersFor(matchId);
      final user = _user(players);
      if (user != null) {
        state.speeches[user.seat] = clean;
        state.log.add('${user.seat}号 你：$clean');
      }
    }
    state.speechIndex++;
    state.awaiting = '';
    await _save(matchId, state);
    return const ActionOutcome(ok: true, message: '发言结束');
  });

  /// 第一天警长竞选：上警 / 不上警。
  Future<ActionOutcome> submitSheriffRun({
    required String matchId,
    required bool run,
  }) => _lockedOutcome(matchId, () async {
    final state = await _loadState(matchId);
    if (state == null ||
        state.phase != WerewolfPhase.sheriffElection ||
        state.sheriffStage != 'candidacy') {
      return const ActionOutcome(ok: false, message: '现在不是报名阶段');
    }
    final players = await repository.playersFor(matchId);
    final user = _user(players);
    if (user == null) return const ActionOutcome(ok: false, message: '找不到你');
    state.runDecisions[user.seat] = run;
    state.awaiting = '';
    state.log.add(run ? '${user.seat}号 你：参加警长竞选' : '${user.seat}号 你：不参加警长竞选');
    await _save(matchId, state);
    return ActionOutcome(ok: true, message: run ? '上警了' : '不上警');
  });

  /// 竞选发言（用户自己是候选人时）。
  Future<ActionOutcome> submitSheriffSpeech({
    required String matchId,
    required String text,
  }) => _lockedOutcome(matchId, () async {
    final state = await _loadState(matchId);
    if (state == null ||
        state.phase != WerewolfPhase.sheriffElection ||
        state.sheriffStage != 'campaign') {
      return const ActionOutcome(ok: false, message: '现在不是竞选发言阶段');
    }
    final players = await repository.playersFor(matchId);
    final user = _user(players);
    if (user == null) return const ActionOutcome(ok: false, message: '找不到你');
    final clean = text.trim();
    state.campaignSpeeches[user.seat] = clean;
    state.log.add('${user.seat}号 你（竞选警长）：${clean.isEmpty ? '（没说话）' : clean}');
    state.campaignIndex++;
    state.awaiting = '';
    await _save(matchId, state);
    return const ActionOutcome(ok: true, message: '竞选发言结束');
  });

  /// 非候选人投警长票。
  Future<ActionOutcome> submitSheriffVote({
    required String matchId,
    required int target,
  }) => _lockedOutcome(matchId, () async {
    final state = await _loadState(matchId);
    if (state == null ||
        state.phase != WerewolfPhase.sheriffElection ||
        state.sheriffStage != 'vote') {
      return const ActionOutcome(ok: false, message: '现在不是警长投票阶段');
    }
    final players = await repository.playersFor(matchId);
    final user = _user(players);
    if (user == null) return const ActionOutcome(ok: false, message: '找不到你');
    state.sheriffVotes[user.seat] = target;
    state.awaiting = '';
    await _save(matchId, state);
    return const ActionOutcome(ok: true, message: '警长票已提交');
  });

  Future<ActionOutcome> submitVote({
    required String matchId,
    required int target,
  }) => _lockedOutcome(matchId, () async {
    final state = await _loadState(matchId);
    if (state == null || state.phase != WerewolfPhase.voting) {
      return const ActionOutcome(ok: false, message: '现在不是投票阶段');
    }
    final players = await repository.playersFor(matchId);
    final user = _user(players);
    if (user == null) return const ActionOutcome(ok: false, message: '找不到你');
    state.votes[user.seat] = target;
    state.awaiting = '';
    await _save(matchId, state);
    return const ActionOutcome(ok: true, message: '投票已提交');
  });

  Future<ActionOutcome> submitHunter({
    required String matchId,
    required int target,
  }) => _lockedOutcome(matchId, () async {
    final state = await _loadState(matchId);
    if (state == null || state.phase != WerewolfPhase.hunter) {
      return const ActionOutcome(ok: false, message: '现在不能开枪');
    }
    final players = await repository.playersFor(matchId);
    final user = _user(players);
    if (user == null) return const ActionOutcome(ok: false, message: '找不到你');
    state.pendingHunter = null;
    state.awaiting = '';
    final targetPlayer = _bySeat(players, target);
    state.log.add('你（猎人）开枪带走了 $target 号 ${targetPlayer?.name ?? ''}。');
    await _kill(matchId, target);
    final after = await repository.playersFor(matchId);
    await _afterHunterShot(matchId, state, after);
    return const ActionOutcome(ok: true, message: '开枪了');
  }, advanceAfter: false);

  // ---------------------------------------------------------------------------
  // 模型 / 启发式
  // ---------------------------------------------------------------------------

  Future<WerewolfChoice> _askChoice(
    String matchId,
    GameMatchPlayer player,
    List<GameMatchPlayer> players,
    WerewolfState state, {
    required String kind,
  }) async {
    final resident = player.residentId.isEmpty
        ? null
        : await residents.findById(player.residentId);
    if (resident == null) return _heuristicChoice(player, players, state, kind);
    final config =
        await gateway.configFor(configId: resident.modelConfigId) ??
        await gateway.activeConfig();
    if (config == null) return _heuristicChoice(player, players, state, kind);
    final roleOfPlayer = role(player);
    final alive = players.where((item) => item.alive).toList();
    final private = state.privateLog[player.seat] ?? const <String>[];
    final recent = state.log.length > 20
        ? state.log.sublist(state.log.length - 20)
        : state.log;
    final prompt = [
      '你正在玩一局 9 人狼人杀。你是 ${player.seat} 号「${resident.name}」，'
          '身份是「${roleOfPlayer.label}」：${roleOfPlayer.ability}',
      '现在：第 ${state.night} 夜，${kind == 'wolf'
          ? '狼人选择击杀目标'
          : kind == 'seer'
          ? '预言家查验'
          : kind == 'witch'
          ? '女巫用药'
          : '猎人开枪'}。',
      '还活着的人：${alive.map((item) => '${item.seat}号 ${item.name}').join('、')}',
      if (private.isNotEmpty) '你的私密信息：\n${private.join('\n')}',
      '最近发生的事：\n${recent.join('\n')}',
      _choiceInstruction(kind),
    ].join('\n\n');
    try {
      final text = sanitizeModelText(
        await gateway.completeRich(
          config: config,
          messages: [
            {
              'role': 'system',
              'content': '你在玩狼人杀，只输出一个 JSON，不要解释，不要 markdown。',
            },
            {'role': 'user', 'content': prompt},
          ],
          temperature: 0.6,
          maxTokens: 180,
          timeout: const Duration(seconds: 16),
        ),
      );
      return _parseChoice(text);
    } catch (error) {
      debugPrint('[狼人杀] ${resident.name} 决策失败：$error');
      return _heuristicChoice(player, players, state, kind);
    }
  }

  static String _choiceInstruction(String kind) => switch (kind) {
    'wolf' => '选一个还活着的、不是狼人的目标。只回复 {"target": 座位号}。',
    'seer' => '选一个还活着的其他玩家查验。只回复 {"target": 座位号}。不要假设自己已经知道身份。',
    'witch' =>
      '如果你有解药，可以考虑救今晚被刀的人；如果有毒药，可以考虑毒一个你怀疑的人。'
          '只回复 {"save": true/false, "poison": 座位号或0}。',
    'hunter' => '选一个还活着的玩家开枪带走。只回复 {"target": 座位号}。',
    _ => '只回复一个 JSON。',
  };

  static WerewolfChoice _parseChoice(String text) {
    final target = RegExp(r'"target"\s*:\s*(\d+)').firstMatch(text);
    final save = RegExp(r'"save"\s*:\s*(true|false)').firstMatch(text);
    final poison = RegExp(r'"poison"\s*:\s*(\d+)').firstMatch(text);
    return WerewolfChoice(
      target: target == null ? null : int.tryParse(target.group(1)!),
      save: save == null ? null : save.group(1) == 'true',
      poison: poison == null ? null : int.tryParse(poison.group(1)!),
    );
  }

  WerewolfChoice _heuristicChoice(
    GameMatchPlayer player,
    List<GameMatchPlayer> players,
    WerewolfState state,
    String kind,
  ) {
    final alive = players.where((item) => item.alive).toList();
    final ownRole = role(player);
    if (kind == 'wolf') {
      final candidates = alive.where(
        (item) => role(item) != WerewolfRole.werewolf,
      );
      return WerewolfChoice(target: _randomSeat(candidates));
    }
    if (kind == 'seer') {
      return WerewolfChoice(
        target: _randomSeat(alive.where((item) => item.seat != player.seat)),
      );
    }
    if (kind == 'witch') {
      final save = state.nightKill != null && _rand.nextDouble() < 0.25;
      final poison = !save && _rand.nextDouble() < 0.12
          ? _randomSeat(alive.where((item) => item.seat != player.seat))
          : null;
      return WerewolfChoice(save: save, poison: poison);
    }
    if (kind == 'hunter') {
      return WerewolfChoice(
        target: _randomSeat(alive.where((item) => item.seat != player.seat)),
      );
    }
    // 投票：狼人优先投好人，好人随机怀疑一个。
    final candidates = ownRole == WerewolfRole.werewolf
        ? alive.where((item) => role(item) != WerewolfRole.werewolf)
        : alive.where((item) => item.seat != player.seat);
    return WerewolfChoice(target: _randomSeat(candidates));
  }

  /// 狼人夜里的讨论：只给狼队看，决定今晚刀谁。
  Future<String> _wolfTalk(
    GameMatchPlayer player,
    List<GameMatchPlayer> players,
    WerewolfState state,
  ) async {
    final alive = players.where((item) => item.alive).toList();
    final candidates = alive.where(
      (item) => role(item) != WerewolfRole.werewolf,
    );
    final target = _randomSeat(candidates);
    if (player.residentId.isEmpty) {
      return target == null ? '今晚先稳一手。' : '我觉得 $target 号像神，先刀他。';
    }
    final resident = await residents.findById(player.residentId);
    if (resident == null) return '今晚先稳一手。';
    final prompt = [
      '你在玩狼人杀，现在是狼队夜里讨论。你是 ${player.seat} 号「${resident.name}」，'
          '身份狼人。还活着的人：${alive.map((item) => '${item.seat}号 ${item.name}').join('、')}。',
      '说 1 句话：你想刀谁、为什么。不要暴露给好人，不要用 JSON。',
    ].join('\n');
    try {
      final text = (await _askText(resident, prompt, maxTokens: 80)).trim();
      return text.isEmpty
          ? (target == null ? '今晚先稳一手。' : '我觉得 $target 号像神。')
          : text;
    } catch (_) {
      return target == null ? '今晚先稳一手。' : '我觉得 $target 号像神。';
    }
  }

  Future<String> _speechFor(
    String matchId,
    GameMatchPlayer player,
    List<GameMatchPlayer> players,
    WerewolfState state,
  ) async {
    if (player.isUser) return '';
    final resident = player.residentId.isEmpty
        ? null
        : await residents.findById(player.residentId);
    if (resident == null) return _aiSpeech(player, players, state);
    final config =
        await gateway.configFor(configId: resident.modelConfigId) ??
        await gateway.activeConfig();
    if (config == null) return _aiSpeech(player, players, state);
    final roleOfPlayer = role(player);
    final private = state.privateLog[player.seat] ?? const <String>[];
    final memory = await session.memoryLinesFor(resident);
    final recent = state.log.length > 16
        ? state.log.sublist(state.log.length - 16)
        : state.log;
    final prompt = [
      '你正在玩一局 9 人狼人杀。你是 ${player.seat} 号「${resident.name}」，'
          '身份是「${roleOfPlayer.label}」：${roleOfPlayer.ability}',
      if (resident.personality.trim().isNotEmpty)
        '你的性格：${resident.personality}',
      if (resident.tone.trim().isNotEmpty) '你的语气：${resident.tone}',
      if (memory.isNotEmpty) '你记得：$memory',
      if (private.isNotEmpty) '你的私密信息：\n${private.join('\n')}',
      '最近发生的事：\n${recent.join('\n')}',
      '轮到你发言。结合你的身份和别人的发言，说 1—2 句，像真人复盘：'
          '可以点怀疑、帮自己解释、或者给好人留信息。不要报身份，不要用 JSON，'
          '不要提“AI”、不要写括号动作。',
    ].join('\n\n');
    try {
      final text = sanitizeModelText(
        await gateway.completeRich(
          config: config,
          messages: [
            {'role': 'system', 'content': '你在一局狼人杀里发言，只输出你要说的话。'},
            {'role': 'user', 'content': prompt},
          ],
          temperature: 0.85,
          maxTokens: 160,
          timeout: const Duration(seconds: 16),
        ),
      ).trim();
      return text;
    } catch (error) {
      debugPrint('[狼人杀] ${resident.name} 发言失败：$error');
      return _aiSpeech(player, players, state);
    }
  }

  String _aiSpeech(
    GameMatchPlayer player,
    List<GameMatchPlayer> players,
    WerewolfState state,
  ) {
    final alive = players.where((item) => item.alive).toList();
    final suspect = _randomSeat(
      alive.where((item) => item.seat != player.seat),
    );
    final templates = [
      if (suspect != null) '我先听 $suspect 号怎么说，他刚才那句有点急。',
      if (suspect != null) '我暂时怀疑 $suspect 号，先投他一票看看。',
      '我信息不多，先跟一轮，有预言家的话记得留验人。',
      '昨晚的刀口有点怪，我觉得狼在中间位置。',
    ];
    return templates[_rand.nextInt(templates.length)];
  }

  Future<int> _voteFor(
    String matchId,
    GameMatchPlayer player,
    List<GameMatchPlayer> players,
    WerewolfState state,
  ) async {
    if (player.isUser) return 0;
    final resident = player.residentId.isEmpty
        ? null
        : await residents.findById(player.residentId);
    if (resident == null) {
      return _heuristicChoice(player, players, state, 'vote').target ?? 0;
    }
    final config =
        await gateway.configFor(configId: resident.modelConfigId) ??
        await gateway.activeConfig();
    if (config == null) {
      return _heuristicChoice(player, players, state, 'vote').target ?? 0;
    }
    final alive = players.where((item) => item.alive).toList();
    final private = state.privateLog[player.seat] ?? const <String>[];
    final speechLog = state.log.length > 20
        ? state.log.sublist(state.log.length - 20)
        : state.log;
    final prompt = [
      '你正在玩狼人杀。你是 ${player.seat} 号「${resident.name}」，'
          '身份「${role(player).label}」。',
      if (private.isNotEmpty) '私密信息：${private.join('；')}',
      '还活着：${alive.map((item) => '${item.seat}号 ${item.name}').join('、')}',
      '最近发言：\n${speechLog.join('\n')}',
      '请投票放逐一个人。只回复 {"target": 座位号}；弃权回复 {"target": 0}。',
    ].join('\n\n');
    try {
      final text = await gateway.completeRich(
        config: config,
        messages: [
          {'role': 'system', 'content': '只输出一个 JSON。'},
          {'role': 'user', 'content': prompt},
        ],
        temperature: 0.5,
        maxTokens: 80,
        timeout: const Duration(seconds: 14),
      );
      return _parseChoice(text).target ?? 0;
    } catch (error) {
      debugPrint('[狼人杀] ${resident.name} 投票失败：$error');
      return _heuristicChoice(player, players, state, 'vote').target ?? 0;
    }
  }

  // ---------------------------------------------------------------------------
  // 小工具
  // ---------------------------------------------------------------------------

  static WerewolfRole role(GameMatchPlayer? player) =>
      WerewolfRole.fromKey(player?.role ?? '');

  static GameMatchPlayer? _firstWhere(
    Iterable<GameMatchPlayer> players,
    bool Function(GameMatchPlayer) test,
  ) {
    for (final player in players) {
      if (test(player)) return player;
    }
    return null;
  }

  static GameMatchPlayer? _user(List<GameMatchPlayer> players) {
    for (final player in players) {
      if (player.isUser) return player;
    }
    return null;
  }

  static GameMatchPlayer? _bySeat(List<GameMatchPlayer> players, int? seat) {
    if (seat == null) return null;
    for (final player in players) {
      if (player.seat == seat) return player;
    }
    return null;
  }

  @visibleForTesting
  static String? winnerFor(List<GameMatchPlayer> players) =>
      _checkWinner(players);

  static String? _checkWinner(List<GameMatchPlayer> players) {
    final alive = players.where((item) => item.alive).toList();
    final wolves = alive
        .where((item) => role(item) == WerewolfRole.werewolf)
        .length;
    final good = alive.length - wolves;
    if (wolves == 0) return 'good';
    if (wolves >= good) return 'evil';
    // GameWeb 的“屠边”：村民全死，或神职全死，狼人同样获胜。
    final aliveVillagers = alive
        .where((item) => role(item) == WerewolfRole.villager)
        .length;
    final aliveSpecial = alive
        .where(
          (item) =>
              role(item) == WerewolfRole.seer ||
              role(item) == WerewolfRole.witch ||
              role(item) == WerewolfRole.hunter,
        )
        .length;
    if (aliveVillagers == 0 || aliveSpecial == 0) return 'evil';
    return null;
  }

  Future<void> _kill(String matchId, int seat) async {
    final players = await repository.playersFor(matchId);
    final player = _bySeat(players, seat);
    if (player != null) {
      await repository.updatePlayer(playerId: player.id, alive: false);
    }
  }

  static void _private(WerewolfState state, int seat, String text) {
    final list = state.privateLog.putIfAbsent(seat, () => <String>[]);
    list.add(text);
  }

  @visibleForTesting
  static int? majorityFor(List<int> votes, {int? fallback}) =>
      _majority(votes, fallback: fallback);

  static int? _majority(List<int> votes, {int? fallback}) {
    if (votes.isEmpty) return fallback;
    final counts = <int, int>{};
    for (final vote in votes) {
      counts[vote] = (counts[vote] ?? 0) + 1;
    }
    var best = 0;
    final tied = <int>[];
    for (final entry in counts.entries) {
      if (entry.value > best) {
        best = entry.value;
        tied
          ..clear()
          ..add(entry.key);
      } else if (entry.value == best) {
        tied.add(entry.key);
      }
    }
    if (tied.isEmpty) return fallback;
    return tied[_staticRand.nextInt(tied.length)];
  }

  int? _randomSeat(Iterable<GameMatchPlayer> players) {
    final list = players.toList(growable: false);
    if (list.isEmpty) return null;
    return list[_rand.nextInt(list.length)].seat;
  }
}

class _SeatPlayer {
  const _SeatPlayer({
    required this.seat,
    required this.name,
    required this.role,
    this.resident,
    this.isUser = false,
  });

  final int seat;
  final String name;
  final WerewolfRole role;
  final CustomResident? resident;
  final bool isUser;
}

final werewolfServiceProvider = Provider<WerewolfService>(
  (ref) => WerewolfService(
    repository: ref.watch(gameRepositoryProvider),
    residents: ref.watch(customResidentRepositoryProvider),
    messages: ref.watch(privateMessageRepositoryProvider),
    gateway: ref.watch(modelGatewayProvider),
    context: ref.watch(residentContextServiceProvider),
    session: ref.watch(residentToolSessionProvider),
    games: ref.watch(gameServiceProvider),
  ),
);
