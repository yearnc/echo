import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media/image_payload.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/game_plugin_repository.dart';
import '../../data/repositories/game_repository.dart';
import '../../data/repositories/private_message_repository.dart';
import '../games/game_engine.dart';
import '../games/game_registry.dart';
import '../games/game_tools.dart';
import '../models/game.dart';
import '../models/game_plugin.dart';
import 'action_registry.dart';
import 'model_gateway.dart';
import 'resident_context_service.dart';
import 'tool_call_text.dart';

/// 棋盘截图生成器。由 UI 层注入，避免 domain 依赖 Flutter 的绘制上下文。
typedef BoardImageBuilder = Future<String?> Function(GameMatch match);

/// 小游戏的对局服务。
///
/// 所有对局共用同一段常驻上下文窗口：开局/走棋只往窗口末尾追加一行，
/// 当前棋盘作为本轮载荷，不另建 system，也不另建窗口。
class GameService {
  GameService({
    required this.repository,
    required this.residents,
    required this.messages,
    required this.context,
    required this.gateway,
    required this.actions,
    required this.plugins,
    this.boardImages,
  });

  final GameRepository repository;
  final CustomResidentRepository residents;
  final PrivateMessageRepository messages;
  final ResidentContextService context;
  final ModelGateway gateway;
  final ActionRegistry actions;
  final GamePluginRepository plugins;

  /// 由棋局页面在打开时绑定：domain 不认识 Flutter 的绘制上下文。
  BoardImageBuilder? boardImages;

  void bindBoardImages(BoardImageBuilder builder) {
    boardImages = builder;
  }

  /// 同一位住民同一时间只让模型想一步，避免用户连点触发多次。
  final Set<String> _thinking = {};

  /// 同一局棋的所有写操作串行：模型工具、用户落子、认输可能同时到达。
  final Map<String, Future<void>> _matchLocks = {};

  /// 已经收尾并写过记忆的局，避免同一次结束被重复总结。
  final Set<String> _summarizedMatches = {};

  /// 一局同时只回一条棋盘边聊天，避免用户连点触发多次模型。
  final Set<String> _chatting = {};

  static const int _maxModelTries = 3;

  Future<T> _withMatchLock<T>(String matchId, Future<T> Function() action) {
    final previous = _matchLocks[matchId] ?? Future<void>.value();
    final gate = Completer<void>();
    _matchLocks[matchId] = gate.future;
    return previous
        .catchError((Object _) {})
        .then((_) => action())
        .whenComplete(() {
          gate.complete();
          if (identical(_matchLocks[matchId], gate.future)) {
            _matchLocks.remove(matchId);
          }
        });
  }

  List<GameDefinition> get definitions => GameRegistry.definitions;

  Future<List<GameInvite>> pendingInvitesFor(String residentId) =>
      repository.pendingInvites(residentId);

  Future<List<GameMatch>> activeMatchesFor(String residentId) =>
      repository.activeMatchesForPlayer(residentId);

  // ---------------------------------------------------------------------------
  // 邀请
  // ---------------------------------------------------------------------------

  /// 住民主动邀请用户。会给用户发一张邀请卡片。
  Future<ActionOutcome> inviteFromResident({
    required String residentId,
    required String gameId,
    String note = '',
  }) async {
    final engine = GameRegistry.byId(gameId);
    if (engine == null) {
      return const ActionOutcome(ok: false, message: '没有这个游戏');
    }
    final resident = await residents.findById(residentId);
    if (resident == null) {
      return const ActionOutcome(ok: false, message: '这个人已经不在社区里了');
    }
    final pending = await repository.pendingInvites(residentId);
    if (pending.any((invite) => invite.gameId == gameId)) {
      return const ActionOutcome(ok: false, message: '你已经有一条这个游戏的邀请还没处理');
    }

    final invite = await repository.createInvite(
      residentId: residentId,
      gameId: gameId,
      initiator: 'resident',
      note: note,
    );
    final messageId = await messages.scheduleIncoming(
      personaId: residentId,
      content: invite.id,
      at: DateTime.now(),
      mediaType: 'game_invite',
      caption: _inviteCaption(engine, note),
    );
    await repository.attachMessage(invite.id, messageId);
    return ActionOutcome(
      ok: true,
      message: '邀请已经发过去了，等对方接受',
      data: {'invite_id': invite.id, 'game': engine.definition.id},
    );
  }

  /// 用户在小游戏页邀请住民。邀请进入待处理，住民醒来自己决定。
  Future<GameInvite> inviteFromUser({
    required String residentId,
    required String gameId,
    String note = '',
  }) async {
    final engine = GameRegistry.byId(gameId);
    if (engine == null) throw StateError('没有这个游戏');
    final pending = await repository.pendingInvites(residentId);
    if (pending.any((invite) => invite.gameId == gameId)) {
      throw StateError('这个游戏已经有一条邀请还没处理');
    }
    final invite = await repository.createInvite(
      residentId: residentId,
      gameId: gameId,
      initiator: 'user',
      note: note,
    );
    final messageId = await messages.send(
      personaId: residentId,
      content: invite.id,
      mediaType: 'game_invite',
      caption: _inviteCaption(engine, note),
    );
    await repository.attachMessage(invite.id, messageId);
    return invite;
  }

  /// 住民接受/拒绝用户发来的邀请。
  Future<ActionOutcome> respondInvite({
    required String residentId,
    required String inviteId,
    required bool accept,
    String note = '',
  }) async {
    await repository.expireStale();
    final invite = await repository.findInvite(inviteId);
    if (invite == null || invite.residentId != residentId) {
      return const ActionOutcome(ok: false, message: '找不到这条邀请');
    }
    if (invite.fromResident) {
      return const ActionOutcome(ok: false, message: '这条邀请是你发出去的，等对方回应');
    }
    if (invite.status != GameInviteStatus.pending) {
      return ActionOutcome(
        ok: false,
        message: switch (invite.status) {
          GameInviteStatus.accepted => '这条邀请已经接受了',
          GameInviteStatus.declined => '这条邀请已经拒绝了',
          GameInviteStatus.expired => '这条邀请已经过期了',
          GameInviteStatus.cancelled => '这条邀请已经取消了',
          GameInviteStatus.pending => '这条邀请还没处理',
        },
      );
    }
    if (!accept) {
      await repository.resolveInvite(invite.id, GameInviteStatus.declined);
      await messages.send(
        personaId: residentId,
        content: note.trim().isEmpty ? '这次先不下啦，改天吧。' : note.trim(),
      );
      await _noteInviteStatus(
        residentId,
        '你拒绝了对方发来的${_gameName(invite.gameId)}邀请。',
      );
      return const ActionOutcome(ok: true, message: '已拒绝邀请');
    }

    final match = await _openMatch(invite: invite, residentId: residentId);
    if (match == null) {
      return const ActionOutcome(ok: false, message: '这个游戏的规则还没准备好');
    }
    await _noteInviteStatus(
      residentId,
      '你接受了对方发来的${_gameName(invite.gameId)}邀请，对局开始了。',
    );
    // 接受邀请不再自动发私信：进入对局后所有交流都走棋盘边的桌宠气泡。
    return ActionOutcome(
      ok: true,
      message: '接受了邀请，开局了',
      data: {'match_id': match.id},
    );
  }

  /// 用户在聊天卡片上接受住民发来的邀请。
  Future<GameActionResult> acceptInviteByUser(String inviteId) async {
    await repository.expireStale();
    final invite = await repository.findInvite(inviteId);
    if (invite == null) {
      return const GameActionResult(ok: false, message: '邀请不存在');
    }
    if (!invite.fromResident) {
      return const GameActionResult(ok: false, message: '这是你发出的邀请，等 TA 回应');
    }
    if (invite.status != GameInviteStatus.pending) {
      return const GameActionResult(ok: false, message: '这条邀请已经处理过了');
    }
    final match = await _openMatch(
      invite: invite,
      residentId: invite.residentId,
    );
    if (match == null) {
      return const GameActionResult(ok: false, message: '这个游戏的规则还没准备好');
    }
    await _noteInviteStatus(
      invite.residentId,
      '对方接受了你发出的${_gameName(invite.gameId)}邀请，对局开始了。',
    );
    // 不在私信里补“好啊”：对局内会直接进入棋盘边的交流。
    return GameActionResult(ok: true, message: '开局了', match: match);
  }

  Future<GameActionResult> declineInviteByUser(String inviteId) async {
    await repository.expireStale();
    final invite = await repository.findInvite(inviteId);
    if (invite == null) {
      return const GameActionResult(ok: false, message: '邀请不存在');
    }
    if (!invite.fromResident) {
      return const GameActionResult(ok: false, message: '这是你发出的邀请，等 TA 回应');
    }
    final changed = await repository.resolveInvite(
      invite.id,
      GameInviteStatus.declined,
    );
    if (!changed) {
      return const GameActionResult(ok: false, message: '这条邀请已经处理过了');
    }
    await messages.send(personaId: invite.residentId, content: '这次先不下了，改天吧。');
    await _noteInviteStatus(
      invite.residentId,
      '对方拒绝了你发出的${_gameName(invite.gameId)}邀请。',
    );
    return const GameActionResult(ok: true, message: '已拒绝');
  }

  /// 接受邀请并开一局。两边方向不同，但棋盘/先后手一致：用户先走。
  /// 邀请状态也进同一个窗口：住民下次醒来知道对方接受/拒绝了，
  /// 而不是只看到一条永远停在“邀请”的旧私信。
  Future<void> _noteInviteStatus(String residentId, String text) async {
    try {
      final resident = await residents.findById(residentId);
      if (resident == null) return;
      final config =
          await gateway.configFor(configId: resident.modelConfigId) ??
          await gateway.activeConfig();
      await context.open(
        resident,
        allowVoice: true,
        allowImages: config?.supportsVision ?? false,
      );
      context.appendMessage(residentId, {
        'role': 'user',
        'content': '<system-reminder>[游戏邀请] $text</system-reminder>',
      });
    } catch (error) {
      debugPrint('[游戏] 邀请状态没写进上下文：$error');
    }
  }

  String _gameName(String gameId) =>
      GameRegistry.byId(gameId)?.definition.name ?? gameId;

  Future<GameMatch?> _openMatch({
    required GameInvite invite,
    required String residentId,
  }) async {
    final engine = GameRegistry.byId(invite.gameId);
    if (engine == null) return null;
    final changed = await repository.resolveInvite(
      invite.id,
      GameInviteStatus.accepted,
    );
    if (!changed) return null;
    final match = await repository.createMatch(
      residentId: residentId,
      gameId: engine.definition.id,
      board: engine.initialBoard(),
      turn: GameSide.user,
    );
    await repository.attachMatch(invite.id, match.id);
    return match;
  }

  // ---------------------------------------------------------------------------
  // 对局
  // ---------------------------------------------------------------------------

  Future<GameActionResult> applyUserMove({
    required String matchId,
    required String move,
  }) => _withMatchLock(matchId, () async {
    final match = await repository.findMatch(matchId);
    if (match == null || !match.isActive) {
      return const GameActionResult(ok: false, message: '这局已经结束了');
    }
    if (match.turn != GameSide.user) {
      return const GameActionResult(ok: false, message: '现在轮到 TA 走');
    }
    final result = await _applyMoveInternal(
      match: match,
      move: move,
      by: GameSide.user,
    );
    if (!result.ok) {
      return GameActionResult(ok: false, message: result.message);
    }
    final next = await repository.findMatch(matchId);
    if (next != null && next.isActive) {
      // 不阻塞界面：住民想一步可能要几秒，数据库流会把新棋盘推回来。
      unawaited(requestResidentMove(matchId));
    }
    return GameActionResult(
      ok: true,
      message: result.message,
      match: next,
      winner: result.winner,
    );
  });

  /// 住民走一步（工具调用/兜底都会走这里）。
  Future<ActionOutcome> applyResidentMove({
    required String residentId,
    required String matchId,
    required String move,
  }) => _withMatchLock(matchId, () async {
    final match = await repository.findMatch(matchId);
    if (match == null || match.residentId != residentId) {
      return const ActionOutcome(ok: false, message: '找不到这局棋');
    }
    if (!match.isActive) {
      return const ActionOutcome(ok: false, message: '这局已经结束了');
    }
    if (match.turn != GameSide.resident) {
      return const ActionOutcome(ok: false, message: '现在轮到对方走');
    }
    final result = await _applyMoveInternal(
      match: match,
      move: move,
      by: GameSide.resident,
    );
    if (!result.ok) {
      return ActionOutcome(ok: false, message: result.message);
    }
    return ActionOutcome(
      ok: true,
      message: result.message,
      data: {
        'match_id': matchId,
        'board': result.board,
        if (result.winner != null) 'winner': result.winner!.name,
      },
    );
  });

  Future<GameActionResult> resign({
    required String matchId,
    required GameSide by,
  }) => _withMatchLock(matchId, () async {
    final match = await repository.findMatch(matchId);
    if (match == null || !match.isActive) {
      return const GameActionResult(ok: false, message: '这局已经结束了');
    }
    final winner = by == GameSide.user ? GameSide.resident : GameSide.user;
    await _finishMatch(match, winner: winner, draw: false, reason: '认输');
    final next = await repository.findMatch(matchId);
    return GameActionResult(
      ok: true,
      message: '已认输',
      match: next,
      winner: winner,
    );
  });

  Future<GameMoveResult> _applyMoveInternal({
    required GameMatch match,
    required String move,
    required GameSide by,
  }) async {
    final engine = GameRegistry.byId(match.gameId);
    if (engine == null) return GameMoveResult.rejected('没有这个游戏');
    final history = await repository.movesFor(match.id);
    final boards = [
      engine.initialBoard(),
      for (final item in history)
        if (item.board.isNotEmpty) item.board,
    ];
    final result = engine.apply(
      board: match.board,
      move: move,
      by: by,
      history: boards,
    );
    if (!result.ok) return result;

    final nextTurn = by == GameSide.user ? GameSide.resident : GameSide.user;
    final over = result.isOver;
    final winnerText = result.winner == null
        ? (result.draw ? 'draw' : '')
        : result.winner == GameSide.user
        ? 'user_win'
        : 'resident_win';
    final updated = await repository.updateMatch(
      id: match.id,
      board: result.board,
      turn: nextTurn,
      moveCount: match.moveCount + 1,
      status: over ? GameMatchStatus.finished : GameMatchStatus.active,
      result: winnerText,
      expectActive: true,
      expectedTurn: match.turn,
      expectedMoveCount: match.moveCount,
    );
    if (!updated) {
      return GameMoveResult.rejected('棋局状态刚刚变了，重新看一眼棋盘再走');
    }
    await repository.appendMove(
      matchId: match.id,
      seq: match.moveCount + 1,
      by: by,
      move: engine.normalizeMove(move),
      board: result.board,
      now: DateTime.now(),
    );

    context.appendMessage(match.residentId, {
      'role': by == GameSide.user ? 'user' : 'assistant',
      'content':
          '<system-reminder>[${engine.definition.name}] '
          '${by == GameSide.user ? '对方' : '你'}走了 '
          '${engine.displayMove(engine.normalizeMove(move))}</system-reminder>',
    });

    if (over) {
      await _finishMatch(
        await repository.findMatch(match.id) ?? match,
        winner: result.winner,
        draw: result.draw,
        reason: result.message,
      );
    }
    return result;
  }

  Future<void> _finishMatch(
    GameMatch match, {
    required GameSide? winner,
    required bool draw,
    String reason = '',
  }) async {
    final engine = GameRegistry.byId(match.gameId);
    final gameName = engine?.definition.name ?? match.gameId;
    final resultText = draw
        ? '和棋'
        : winner == GameSide.user
        ? '你输了'
        : '你赢了';
    final now = DateTime.now();
    await repository.updateMatch(
      id: match.id,
      board: match.board,
      turn: match.turn,
      moveCount: match.moveCount,
      status: GameMatchStatus.finished,
      result: draw
          ? 'draw'
          : winner == GameSide.user
          ? 'user_win'
          : 'resident_win',
      now: now,
    );
    if (!_summarizedMatches.add(match.id)) return;
    context.appendMessage(match.residentId, {
      'role': 'user',
      'content':
          '<system-reminder>[$gameName] 这一局结束了，'
          '${draw
              ? '和棋'
              : winner == GameSide.resident
              ? '你赢了'
              : '你输了'}。'
          '${reason.trim().isEmpty ? '' : '（$reason）'}</system-reminder>',
    });
    // 先把一句通用记忆落库：就算总结模型还没跑完 APP 就被关掉，
    // 这局也不会完全没留下东西。总结成功后再把这条改详细。
    String? fallbackMemoryId;
    // 带上日期时间：两局同样的棋不该被当成“同一件事”而去重掉。
    final at = DateTime.now();
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    final fallbackText =
        '和对方在 ${at.month}月${at.day}日 $hh:$mm 下了一局$gameName，$resultText。';
    try {
      final written = await actions.writeMemory(
        residentId: match.residentId,
        summary: fallbackText,
        content: fallbackText,
        source: 'game',
        idempotencyKey: 'game:${match.id}:fallback',
      );
      if (written.ok) {
        final id = written.data['memory_id'];
        if (id is String && id.isNotEmpty) fallbackMemoryId = id;
      }
    } catch (error) {
      debugPrint('[游戏] 这局的兜底记忆没写成：$error');
    }
    // 详细总结要调模型，不能让“最后一手”的界面卡在这里等半分钟。
    unawaited(
      _summarizeAndRemember(
        match,
        gameName: gameName,
        winner: winner,
        draw: draw,
        reason: reason,
        fallbackMemoryId: fallbackMemoryId,
        fallbackText: fallbackText,
      ),
    );
  }

  Future<void> _summarizeAndRemember(
    GameMatch match, {
    required String gameName,
    required GameSide? winner,
    required bool draw,
    required String reason,
    required String? fallbackMemoryId,
    required String fallbackText,
  }) async {
    var summary = '';
    try {
      summary = await _summarizeGame(
        match,
        gameName: gameName,
        winner: winner,
        draw: draw,
        reason: reason,
      );
    } catch (error) {
      debugPrint('[游戏] 这局总结没写成：$error');
    }
    if (summary.isEmpty) {
      // 兜底已经写过了就到此为止；刚才兜底失败才再试一次。
      if (fallbackMemoryId == null) {
        try {
          await actions.writeMemory(
            residentId: match.residentId,
            summary: fallbackText,
            content: fallbackText,
            source: 'game',
            idempotencyKey: 'game:${match.id}:fallback',
          );
        } catch (error) {
          debugPrint('[游戏] 这局没记成记忆：$error');
        }
      }
      return;
    }
    try {
      if (fallbackMemoryId != null) {
        await actions.updateMemory(
          residentId: match.residentId,
          memoryId: fallbackMemoryId,
          summary: summary,
          content: summary,
          idempotencyKey: 'game:${match.id}:finish',
        );
      } else {
        await actions.writeMemory(
          residentId: match.residentId,
          summary: summary,
          content: summary,
          source: 'game',
          idempotencyKey: 'game:${match.id}:finish',
        );
      }
    } catch (error) {
      debugPrint('[游戏] 这局详细记忆没写回去：$error');
    }
  }

  /// 让住民自己总结这局：棋怎么走的、棋盘边聊了什么、哪些值得记住。
  /// 模型不可用时返回空，由调用方退回一句通用记忆。
  Future<String> _summarizeGame(
    GameMatch match, {
    required String gameName,
    required GameSide? winner,
    required bool draw,
    required String reason,
  }) async {
    final resident = await residents.findById(match.residentId);
    if (resident == null || !resident.memoryEnabled) return '';
    final config =
        await gateway.configFor(configId: resident.modelConfigId) ??
        await gateway.activeConfig();
    if (config == null) return '';
    final moves = await repository.movesFor(match.id);
    final chats = await repository.messagesFor(match.id);
    if (moves.isEmpty && chats.isEmpty) return '';

    final resultText = draw
        ? '和棋'
        : winner == GameSide.resident
        ? '你赢了'
        : '你输了';
    final record = StringBuffer()
      ..writeln('结果：$resultText${reason.trim().isEmpty ? '' : '（$reason）'}')
      ..writeln('走法（最多列最近 24 手）：');
    for (final move
        in moves.length > 24 ? moves.sublist(moves.length - 24) : moves) {
      record.writeln('${move.by == GameSide.user ? '对方' : '你'} ${move.move}');
    }
    if (chats.isNotEmpty) {
      record.writeln('棋盘边说过：');
      for (final chat
          in chats.length > 20 ? chats.sublist(chats.length - 20) : chats) {
        record.writeln(
          '${chat.by == GameSide.user ? '对方' : '你'}：${chat.content}',
        );
      }
    }

    final text = await gateway.completeRich(
      config: config,
      messages: [
        {
          'role': 'system',
          'content':
              '你刚和对方下完一局$gameName。把这一局里值得记住的事写成一条'
              '简短记忆：对方下棋的习惯、棋盘边说过的话、有没有约定或情绪变化。'
              '两句以内，第一人称，不要写棋谱、不要逐手复盘、不要提“游戏记录”。'
              '如果这局没什么特别的，就只写一句最值得留的。',
        },
        {'role': 'user', 'content': record.toString()},
      ],
      temperature: 0.4,
      maxTokens: 200,
      timeout: const Duration(seconds: 25),
    );
    return sanitizeModelText(text).trim();
  }

  // ---------------------------------------------------------------------------
  // 棋盘边聊天
  // ---------------------------------------------------------------------------

  /// 用户在棋盘边说一句话。住民像坐在对面一样回一句，不用下棋工具。
  ///
  /// 聊天和走棋共用同一个常驻窗口；这里只往后追加，不另开 system。
  Future<GameMessage?> sendGameMessage({
    required String matchId,
    required String text,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty || _chatting.contains(matchId)) return null;
    final match = await repository.findMatch(matchId);
    if (match == null || !match.isActive) return null;
    final resident = await residents.findById(match.residentId);
    if (resident == null) return null;
    final engine = GameRegistry.byId(match.gameId);
    if (engine == null) return null;

    await repository.addMessage(
      matchId: match.id,
      residentId: match.residentId,
      by: GameSide.user,
      content: clean,
    );
    context.appendMessage(match.residentId, {
      'role': 'user',
      'content':
          '<system-reminder>[${engine.definition.name}棋盘边] 对方说：$clean</system-reminder>',
    });

    if (!_chatting.add(matchId)) return null;
    try {
      final config =
          await gateway.configFor(configId: resident.modelConfigId) ??
          await gateway.activeConfig();
      if (config == null) return null;
      final history = await repository.messagesFor(match.id);
      final spoken = history.length > 12
          ? history.sublist(history.length - 12)
          : history;
      final window = await context.open(
        resident,
        allowVoice: true,
        allowImages: config.supportsVision,
      );
      final recent = spoken
          .map(
            (message) =>
                '${message.by == GameSide.user ? '对方' : '你'}：${message.content}',
          )
          .join('\n');
      final prompt = [
        '现在你们在下一局${engine.definition.name}，棋盘就在眼前。',
        engine.describeForModel(match.board, by: GameSide.resident),
        if (recent.isNotEmpty) '你们刚才在棋盘边说过：\n$recent',
        '对方刚说：「$clean」',
        '像坐在棋盘对面聊天一样回一句，1—2 句，短一点；'
            '不要报坐标、不要讨论怎么走棋、不要提 AI。',
      ].join('\n\n');
      final reply = sanitizeModelText(
        await gateway.completeRich(
          config: config,
          messages: [
            ...window.messages,
            {'role': 'user', 'content': prompt},
          ],
          temperature: 0.85,
          maxTokens: 180,
          timeout: const Duration(seconds: 25),
        ),
      ).trim();
      if (reply.isEmpty) return null;
      final saved = await repository.addMessage(
        matchId: match.id,
        residentId: match.residentId,
        by: GameSide.resident,
        content: reply,
      );
      context.appendMessage(match.residentId, {
        'role': 'assistant',
        'content':
            '<system-reminder>[${engine.definition.name}棋盘边] 你说：$reply</system-reminder>',
      });
      return saved;
    } catch (error) {
      debugPrint('[游戏] 棋盘边这句没回成：$error');
      return null;
    } finally {
      _chatting.remove(matchId);
    }
  }

  // ---------------------------------------------------------------------------
  // 模型走棋
  // ---------------------------------------------------------------------------

  /// 轮到住民时叫它想一步。每局同一时间只跑一次。
  Future<void> requestResidentMove(String matchId) async {
    if (!_thinking.add(matchId)) return;
    var settled = false;
    try {
      final match = await repository.findMatch(matchId);
      if (match == null || !match.isActive || match.turn != GameSide.resident) {
        return;
      }
      final engine = GameRegistry.byId(match.gameId);
      if (engine == null) return;
      final resident = await residents.findById(match.residentId);
      if (resident == null) return;
      final config =
          await gateway.configFor(configId: resident.modelConfigId) ??
          await gateway.activeConfig();
      if (config == null) {
        await _fallbackMove(matchId);
        settled = true;
        return;
      }

      final window = await context.open(
        resident,
        allowVoice: true,
        allowImages: config.supportsVision,
      );
      final history = await repository.movesFor(match.id);
      final boardText = engine.describeForModel(
        match.board,
        by: GameSide.resident,
      );
      final lastMoves = history.isEmpty
          ? '这是开局。'
          : '最近几步：${history.reversed.take(4).map((m) => '${m.by == GameSide.user ? '对方' : '你'} ${m.move}').join('，')}';
      final legal = engine.legalMoves(match.board, by: GameSide.resident);
      final legalLine = legal.isEmpty
          ? '当前没有合法走法。'
          : legal.length <= 60
          ? '合法走法（任选一个）：${legal.join(' ')}'
          : '';

      final userText = [
        '现在你们在下一局${engine.definition.name}。',
        boardText,
        lastMoves,
        if (legalLine.isNotEmpty) legalLine,
        '轮到你了。请调用 ${engine.moveToolName} 走一步合法的棋；',
        '不要解释规则，不要聊天，只走这一步。',
      ].join('\n\n');

      final imageParts = <Map<String, dynamic>>[];
      if (config.supportsVision && boardImages != null) {
        final ref = await boardImages!(match);
        if (ref != null) {
          imageParts.addAll(await ImagePayload.partsFromRefs([ref], limit: 1));
        }
      }

      final modelMessages = <Map<String, dynamic>>[
        ...window.messages,
        {
          'role': 'user',
          'content': imageParts.isEmpty
              ? userText
              : [
                  {'type': 'text', 'text': userText},
                  ...imageParts,
                ],
        },
      ];
      final tools = [engine.moveToolSchema, GameTools.resignTool];

      for (var attempt = 0; attempt < _maxModelTries; attempt++) {
        final result = await gateway.completeWithTools(
          config: config,
          messages: modelMessages,
          tools: tools,
          temperature: 0.6,
          maxTokens: 300,
          timeout: const Duration(seconds: 30),
        );

        String? move;
        String? toolId;
        String? error;
        for (final call in result.toolCalls) {
          if (call.name == GameTools.resign) {
            await resign(matchId: match.id, by: GameSide.resident);
            settled = true;
            return;
          }
          if (call.name == engine.moveToolName) {
            toolId = call.id;
            move = _moveFromArgs(engine, call.arguments);
            if (move == null) error = '参数不完整';
            break;
          }
          error = '未知工具：${call.name}';
        }
        if (result.toolCalls.isEmpty) {
          move = _extractMove(engine, result.content);
        }

        if (move != null && move.trim().isNotEmpty) {
          final outcome = await applyResidentMove(
            residentId: match.residentId,
            matchId: match.id,
            move: move,
          );
          if (outcome.ok) {
            settled = true;
            return;
          }
          error = outcome.message;
        } else {
          error ??= '没有给出走法';
        }

        // 把这一轮的失败原因交回去，下一轮只重试走棋，不重开一局。
        if (result.toolCalls.isNotEmpty) {
          modelMessages.add({
            'role': 'assistant',
            'content': result.content,
            'tool_calls': [
              for (final call in result.toolCalls)
                {
                  'id': call.id,
                  'type': 'function',
                  'function': {
                    'name': call.name,
                    'arguments': jsonEncode(call.arguments),
                  },
                },
            ],
          });
          for (final call in result.toolCalls) {
            modelMessages.add({
              'role': 'tool',
              'tool_call_id': call.id,
              'content': jsonEncode({
                'ok': false,
                'message': call.id == toolId
                    ? error
                    : '这一轮只处理一个走棋工具，请重新只调用 ${engine.moveToolName}',
              }),
            });
          }
        } else {
          modelMessages.add({'role': 'assistant', 'content': result.content});
          modelMessages.add({
            'role': 'user',
            'content': '这一步不行：$error。请只回复一个合法走法，或调用 ${engine.moveToolName}。',
          });
        }
      }

      // 模型一直走不出来：引擎兜一个合法落点，别把棋局卡死。
      await _fallbackMove(matchId);
      settled = true;
    } catch (error) {
      debugPrint('[游戏] 住民这一步没走成：$error');
    } finally {
      if (!settled) {
        // 没配模型、超时、服务商报错都要落到同一个兜底：
        // 让 engine 挑一步合法棋，用户不会对着「TA 正在想」干等。
        await _fallbackMove(matchId);
      }
      _thinking.remove(matchId);
    }
  }

  /// 模型不可用时替住民走一步合法棋。返回 false 表示确实无棋可走。
  Future<bool> _fallbackMove(String matchId) async {
    try {
      final match = await repository.findMatch(matchId);
      if (match == null || !match.isActive || match.turn != GameSide.resident) {
        return true;
      }
      final engine = GameRegistry.byId(match.gameId);
      if (engine == null) return true;
      final move = engine.suggestMove(match.board, by: GameSide.resident);
      if (move.isEmpty) return false;
      final outcome = await applyResidentMove(
        residentId: match.residentId,
        matchId: match.id,
        move: move,
      );
      if (outcome.ok) {
        context.appendMessage(match.residentId, {
          'role': 'assistant',
          'content': '<system-reminder>[游戏] 这一步是系统替你选的合法落点。</system-reminder>',
        });
      }
      return outcome.ok;
    } catch (error) {
      debugPrint('[游戏] 兜底走棋也失败了：$error');
      return false;
    }
  }

  static String? _moveFromArgs(GameEngine engine, Map<String, dynamic> args) {
    if (engine.definition.id == 'gomoku') {
      final pos = args['position']?.toString();
      return pos;
    }
    final from = args['from']?.toString();
    final to = args['to']?.toString();
    if (from == null || to == null) return null;
    return engine.normalizeMove('$from$to');
  }

  static String? _extractMove(GameEngine engine, String content) {
    if (engine.definition.id == 'gomoku') {
      final match = RegExp(r'\b([A-Oa-o]\d{1,2})\b').firstMatch(content);
      return match?.group(1);
    }
    final match = RegExp(r'\b([a-i][0-9][a-i][0-9])\b')
        .firstMatch(content.toLowerCase());
    return match?.group(1);
  }

  // ---------------------------------------------------------------------------
  // 工具入口
  // ---------------------------------------------------------------------------

  /// `list_game_tools`：让住民先看见有什么局、轮到谁，再动态拿到走棋工具。
  Future<ActionOutcome> listGameTools(String residentId) async {
    await repository.expireStale();
    final matches = await repository.activeMatchesForPlayer(residentId);
    // 不只给 pending：已经接受/拒绝/过期的邀请也要让住民看得到，
    // 否则窗口里那条“邀请”永远像没处理过。
    final invites = (await repository.invitesFor(residentId)).take(10).toList();
    final games = <Map<String, dynamic>>[];
    final toolSchemas = <Map<String, dynamic>>[];
    for (final match in matches) {
      if (match.gameId == 'werewolf') {
        final bySeat = await repository.playersFor(match.id);
        final me = bySeat.where((item) => item.residentId == residentId);
        games.add({
          'match_id': match.id,
          'game': 'werewolf',
          'name': '狼人杀',
          'turn': 'multiplayer',
          'your_seat': me.isEmpty ? null : me.first.seat,
          'alive': me.isEmpty ? false : me.first.alive,
          'players': [
            for (final player in bySeat)
              {'seat': player.seat, 'name': player.name, 'alive': player.alive},
          ],
        });
        continue;
      }
      if (match.gameId.startsWith('plugin:')) {
        final pluginId = match.gameId.substring('plugin:'.length);
        final plugin = await plugins.findById(pluginId);
        if (plugin == null) continue;
        final interpreter = PluginInterpreter(plugin);
        final state =
            await repository.loadState(match.id) ?? interpreter.initialState;
        games.add({
          'match_id': match.id,
          'game': match.gameId,
          'name': plugin.name,
          'turn': 'multiplayer',
          'state': interpreter.describe(state),
        });
        for (final tool in plugin.tools) {
          if (interpreter.available(tool, state)) {
            toolSchemas.add(_pluginToolSchema(plugin, tool));
          }
        }
        continue;
      }
      final engine = GameRegistry.byId(match.gameId);
      if (engine == null) continue;
      final yourTurn = match.turn == GameSide.resident;
      games.add({
        'match_id': match.id,
        'game': engine.definition.id,
        'name': engine.definition.name,
        'turn': match.turn.name,
        'your_turn': yourTurn,
        'move_count': match.moveCount,
        'board_text': engine.describeForModel(
          match.board,
          by: GameSide.resident,
        ),
      });
      if (yourTurn) toolSchemas.add(engine.moveToolSchema);
    }
    return ActionOutcome(
      ok: true,
      message: matches.isEmpty && invites.isEmpty
          ? '现在没有在玩的对局，也没有等你回应的邀请。'
          : '这是你现在的棋局和邀请。',
      data: {
        'games': games,
        'invites': [
          for (final invite in invites)
            {
              'invite_id': invite.id,
              'game': invite.gameId,
              'from': invite.fromResident ? '你发起的' : '对方发起的',
              'status': invite.status.name,
              'note': invite.note,
              'expires_at': invite.expiresAt.toIso8601String(),
            },
        ],
        'tool_schemas': toolSchemas,
      },
    );
  }

  Future<ActionOutcome> executeMoveTool({
    required String residentId,
    required String toolName,
    required Map<String, dynamic> args,
  }) async {
    final engine = GameRegistry.byToolName(toolName);
    if (engine == null) {
      return const ActionOutcome(ok: false, message: '没有这个走棋工具');
    }
    final matchId = args['match_id']?.toString() ?? '';
    if (matchId.isEmpty) {
      return const ActionOutcome(ok: false, message: '缺少 match_id');
    }
    final move = _moveFromArgs(engine, args);
    if (move == null || move.isEmpty) {
      return const ActionOutcome(ok: false, message: '走法参数不完整');
    }
    return applyResidentMove(
      residentId: residentId,
      matchId: matchId,
      move: move,
    );
  }

  Future<ActionOutcome> resignTool({
    required String residentId,
    required String matchId,
  }) async {
    final match = await repository.findMatch(matchId);
    if (match == null || match.residentId != residentId) {
      return const ActionOutcome(ok: false, message: '找不到这局棋');
    }
    final result = await resign(matchId: matchId, by: GameSide.resident);
    return ActionOutcome(ok: result.ok, message: result.message);
  }

  // ---------------------------------------------------------------------------
  // MCP 风格工具目录与声明式插件（v50）
  // ---------------------------------------------------------------------------

  /// 当前能发给模型的全部游戏工具。
  ///
  /// 内置走棋工具全部常驻，不再等 `list_game_tools` 的下一轮请求；
  /// 插件工具按安装的插件展开，名字统一加前缀，避免重名。
  Future<List<Map<String, dynamic>>> mcpToolSchemas() async {
    final tools = <Map<String, dynamic>>[...GameTools.allBuiltinTools];
    for (final plugin in await plugins.all()) {
      if (!plugin.enabled) continue;
      for (final tool in plugin.tools) {
        tools.add(_pluginToolSchema(plugin, tool));
      }
    }
    return tools;
  }

  static Map<String, dynamic> _pluginToolSchema(
    GamePlugin plugin,
    PluginTool tool,
  ) {
    final parameters = Map<String, dynamic>.from(tool.parameters);
    final properties = parameters['properties'] is Map
        ? Map<String, dynamic>.from(parameters['properties'] as Map)
        : <String, dynamic>{};
    properties['match_id'] = {'type': 'string', 'description': '对局 id'};
    final required = parameters['required'] is List
        ? List<Object?>.from(parameters['required'] as List)
        : <Object?>[];
    if (!required.contains('match_id')) required.add('match_id');
    parameters['type'] = 'object';
    parameters['properties'] = properties;
    parameters['required'] = required;
    return {
      'type': 'function',
      'function': {
        'name': tool.toolName(plugin.id),
        'description':
            '「${plugin.name}」：${tool.description.isEmpty ? tool.name : tool.description}',
        'parameters': parameters,
      },
    };
  }

  /// 住民通过工具调用进入声明式插件。
  Future<ActionOutcome> executeMcpTool({
    required String residentId,
    required String toolName,
    required Map<String, dynamic> args,
  }) async {
    if (toolName.startsWith('echo_')) {
      return _applyPluginTool(
        residentId: residentId,
        toolName: toolName,
        args: args,
      );
    }
    final engine = GameRegistry.byToolName(toolName);
    if (engine != null) {
      return executeMoveTool(
        residentId: residentId,
        toolName: toolName,
        args: args,
      );
    }
    return const ActionOutcome(ok: false, message: '没有这个游戏工具');
  }

  Future<ActionOutcome> _applyPluginTool({
    required String residentId,
    required String toolName,
    required Map<String, dynamic> args,
  }) async {
    final matchId = args['match_id']?.toString() ?? '';
    if (matchId.isEmpty) {
      return const ActionOutcome(ok: false, message: '缺少 match_id');
    }
    final match = await repository.findMatch(matchId);
    if (match == null ||
        !match.isActive ||
        !match.gameId.startsWith('plugin:')) {
      return const ActionOutcome(ok: false, message: '找不到这局游戏');
    }
    final pluginId = match.gameId.substring('plugin:'.length);
    final plugin = await plugins.findById(pluginId);
    if (plugin == null || !plugin.enabled) {
      return const ActionOutcome(ok: false, message: '这个游戏插件已经被删掉了');
    }
    final players = await repository.playersFor(matchId);
    if (!players.any((player) => player.residentId == residentId)) {
      return const ActionOutcome(ok: false, message: '你不在这一局里');
    }
    PluginTool? tool;
    for (final item in plugin.tools) {
      if (item.toolName(plugin.id) == toolName) {
        tool = item;
        break;
      }
    }
    if (tool == null) {
      return const ActionOutcome(ok: false, message: '这个插件没有这个工具');
    }
    final interpreter = PluginInterpreter(plugin);
    final state =
        await repository.loadState(matchId) ?? interpreter.initialState;
    final result = interpreter.apply(tool, args, state);
    if (!result.ok) {
      return ActionOutcome(ok: false, message: result.message);
    }
    await repository.saveState(matchId, result.state);
    if (result.finished) {
      await repository.updateMatch(
        id: matchId,
        board: interpreter.encode(result.state),
        turn: match.turn,
        moveCount: match.moveCount + 1,
        status: GameMatchStatus.finished,
        result: result.result.isEmpty ? 'finished' : result.result,
      );
    } else {
      await repository.updateMatch(
        id: matchId,
        board: interpreter.encode(result.state),
        turn: match.turn,
        moveCount: match.moveCount + 1,
      );
    }
    context.appendMessage(residentId, {
      'role': 'user',
      'content':
          '<system-reminder>[${plugin.name}] 你执行了 ${tool.name}：'
          '${result.message}${result.finished ? '（游戏结束：${result.result}）' : ''}'
          '</system-reminder>',
    });
    return ActionOutcome(
      ok: true,
      message: result.message,
      data: {
        'state': result.state,
        'finished': result.finished,
        if (result.result.isNotEmpty) 'result': result.result,
      },
    );
  }

  /// 用户点击插件按钮。residentId 为空，不要求参与者身份。
  Future<GameActionResult> applyPluginUserTool({
    required String matchId,
    required String toolName,
    required Map<String, dynamic> args,
  }) async {
    final match = await repository.findMatch(matchId);
    if (match == null || !match.isActive) {
      return const GameActionResult(ok: false, message: '这局已经结束了');
    }
    final pluginId = match.gameId.startsWith('plugin:')
        ? match.gameId.substring('plugin:'.length)
        : '';
    final plugin = pluginId.isEmpty ? null : await plugins.findById(pluginId);
    if (plugin == null) {
      return const GameActionResult(ok: false, message: '插件不在了');
    }
    final interpreter = PluginInterpreter(plugin);
    final state =
        await repository.loadState(matchId) ?? interpreter.initialState;
    PluginTool? tool;
    for (final item in plugin.tools) {
      if (item.name == toolName) {
        tool = item;
        break;
      }
    }
    if (tool == null) {
      return const GameActionResult(ok: false, message: '没有这个操作');
    }
    final result = interpreter.apply(tool, args, state);
    if (!result.ok) {
      return GameActionResult(ok: false, message: result.message);
    }
    await repository.saveState(matchId, result.state);
    final over = result.finished;
    await repository.updateMatch(
      id: matchId,
      board: interpreter.encode(result.state),
      turn: GameSide.user,
      moveCount: match.moveCount + 1,
      status: over ? GameMatchStatus.finished : GameMatchStatus.active,
      result: over ? (result.result.isEmpty ? 'finished' : result.result) : '',
    );
    if (over) {
      context.appendMessage(match.residentId, {
        'role': 'user',
        'content':
            '<system-reminder>[${plugin.name}] 这一局结束了：'
            '${result.result.isEmpty ? result.message : result.result}'
            '</system-reminder>',
      });
    }
    final next = await repository.findMatch(matchId);
    return GameActionResult(ok: true, message: result.message, match: next);
  }

  /// 开一局声明式插件。插件所有操作都可以由用户和住民共同触发。
  Future<GameActionResult> startPluginMatch({
    required String pluginId,
    required List<String> residentIds,
  }) async {
    final plugin = await plugins.findById(pluginId);
    if (plugin == null || !plugin.enabled) {
      return const GameActionResult(ok: false, message: '插件不可用');
    }
    if (residentIds.isEmpty) {
      return const GameActionResult(ok: false, message: '先选一位住民');
    }
    final picked = residentIds
        .take(plugin.maxPlayers - 1)
        .toList(growable: false);
    final interpreter = PluginInterpreter(plugin);
    final state = interpreter.initialState;
    final match = await repository.createMatch(
      residentId: picked.isEmpty ? 'plugin_solo' : picked.first,
      gameId: plugin.gameId,
      board: interpreter.encode(state),
      turn: GameSide.user,
    );
    await repository.saveState(match.id, state);
    await repository.addPlayer(
      matchId: match.id,
      name: '你',
      seat: 1,
      isUser: true,
    );
    var seat = 2;
    for (final id in picked) {
      final resident = await residents.findById(id);
      if (resident == null) continue;
      await repository.addPlayer(
        matchId: match.id,
        residentId: resident.id,
        name: resident.name,
        seat: seat++,
        avatarAsset: resident.avatarAsset,
      );
      context.appendMessage(resident.id, {
        'role': 'user',
        'content':
            '<system-reminder>[${plugin.name}] 对方拉你开了一局。'
            '当前状态：${interpreter.describe(state).join('；')}'
            '</system-reminder>',
      });
    }
    return GameActionResult(ok: true, message: '开局了', match: match);
  }

  static String _inviteCaption(GameEngine engine, String note) {
    final clean = note.trim();
    return clean.isEmpty
        ? engine.definition.name
        : '${engine.definition.name} · $clean';
  }
}

final gameServiceProvider = Provider<GameService>(
  (ref) => GameService(
    repository: ref.watch(gameRepositoryProvider),
    residents: ref.watch(customResidentRepositoryProvider),
    messages: ref.watch(privateMessageRepositoryProvider),
    context: ref.watch(residentContextServiceProvider),
    gateway: ref.watch(modelGatewayProvider),
    actions: ref.watch(actionRegistryProvider),
    plugins: ref.watch(gamePluginRepositoryProvider),
  ),
);
