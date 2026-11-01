import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../domain/games/game_engine.dart';
import '../../domain/games/game_registry.dart';
import '../../domain/models/custom_resident.dart';
import '../../domain/models/game.dart';
import '../../domain/services/game_service.dart';
import '../../domain/services/game_session_registry.dart';
import '../../domain/services/pet_controller.dart';
import '../../domain/services/pet_native.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';
import 'game_board.dart';
import 'game_providers.dart';

/// 一局棋的棋盘页。
///
/// 页面只做两件事：把点击变成合法走法，把数据库里的最新棋盘画出来。
/// 住民的回合由 `GameService` 在后台想，不阻塞用户。
class GameMatchPage extends ConsumerStatefulWidget {
  const GameMatchPage({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<GameMatchPage> createState() => _GameMatchPageState();
}

class _GameMatchPageState extends ConsumerState<GameMatchPage> {
  bool _busy = false;
  (int, int)? _selected;
  final Set<(int, int)> _targets = {};
  String? _requestedForTurn;
  final TextEditingController _chat = TextEditingController();
  bool _chatSending = false;
  bool _autoPet = false;
  bool _petAttempted = false;
  bool _sessionStarted = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(gameServiceProvider)
          .bindBoardImages(ref.read(boardImageRendererProvider).render);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    if (_sessionStarted) GameSessionRegistry.end(widget.matchId);
    _chat.dispose();
    if (_autoPet) {
      unawaited(
        ref.read(petControllerProvider.notifier).forceDisableForGame(),
      );
    }
    super.dispose();
  }

  /// 对局里自动把桌宠叫出来；没有悬浮窗权限就安静跳过，
  /// 棋盘边的气泡仍然在页面里显示，不影响下棋。
  Future<void> _openPetForGame() async {
    final controller = ref.read(petControllerProvider.notifier);
    await controller.refresh();
    if (!mounted || ref.read(petControllerProvider).enabled) return;
    final result = await controller.enableForGame();
    if (!result.ok) return;
    _autoPet = true;
    // 开启过程可能比页面寿命长：页面已经走了就立刻把它收掉，
    // 不能因为 mounted 为 false 就把桌宠留在屏幕上。
    if (!mounted || _disposed) {
      unawaited(controller.forceDisableForGame());
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(gameMatchProvider(widget.matchId));
    final match = async.value;
    if (match == null && async.isLoading) {
      return Scaffold(
        backgroundColor: EchoColors.bg,
        appBar: AppBar(title: const Text('对局')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (match == null) {
      return Scaffold(
        backgroundColor: EchoColors.bg,
        appBar: AppBar(title: const Text('对局')),
        body: Center(
          child: Text(
            '这局棋不在了',
            style: TextStyle(color: EchoColors.textMuted),
          ),
        ),
      );
    }
    final engine = GameRegistry.byId(match.gameId);
    if (engine == null) {
      return Scaffold(
        backgroundColor: EchoColors.bg,
        appBar: AppBar(title: const Text('对局')),
        body: const Center(child: Text('这个游戏还没有规则')),
      );
    }
    final resident = ref.watch(customResidentByIdProvider(match.residentId));
    final messages =
        ref.watch(gameMessagesProvider(match.id)).value ?? const <GameMessage>[];
    _maybeAskResident(match);
    if (match.isActive && !_sessionStarted) {
      _sessionStarted = true;
      GameSessionRegistry.begin(match.id, match.residentId);
    }
    if (match.isActive && !_petAttempted) {
      _petAttempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openPetForGame());
      });
    }

    return Scaffold(
      backgroundColor: EchoColors.bg,
      bottomNavigationBar: const SafeArea(child: AiDisclaimerBar()),
      appBar: AppBar(
        backgroundColor: EchoColors.bg,
        elevation: 0,
        title: Text('${resident?.name ?? 'TA'} · ${engine.definition.name}'),
        actions: [
          if (match.isActive)
            TextButton(
              onPressed: _busy ? null : () => _resign(match),
              child: const Text('认输'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _statusCard(match, engine, resident?.name ?? 'TA'),
          const SizedBox(height: 14),
          if (match.gameId == 'xiangqi')
            XiangqiBoard(
              board: match.board,
              enabled: match.isActive && match.isUserTurn && !_busy,
              selected: _selected,
              targets: _targets,
              onTap: (x, y) => _tapXiangqi(match, engine, x, y),
            )
          else
            GomokuBoard(
              board: match.board,
              enabled: match.isActive && match.isUserTurn && !_busy,
              lastMove: null,
              onTap: (x, y) => _tapGomoku(match, x, y),
            ),
          const SizedBox(height: 14),
          _hint(match, engine),
          if (match.isActive && !match.isUserTurn) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  '${resident?.name ?? 'TA'} 正在想这一步…',
                  style: TextStyle(color: EchoColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _chatPanel(match, resident, messages),
        ],
      ),
    );
  }

  Widget _chatPanel(
    GameMatch match,
    CustomResident? resident,
    List<GameMessage> messages,
  ) {
    final name = resident?.name ?? 'TA';
    final recent = messages.length > 8
        ? messages.sublist(messages.length - 8)
        : messages;
    final pet = ref.watch(petControllerProvider);
    final petElsewhere =
        pet.enabled &&
        pet.controllerId != null &&
        pet.controllerId != match.residentId;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: EchoColors.divider, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pets, size: 15, color: EchoColors.primary),
              const SizedBox(width: 5),
              Text(
                '棋盘边',
                style: TextStyle(
                  color: EchoColors.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_chatSending)
                Text(
                  '$name 正在回…',
                  style: TextStyle(color: EchoColors.textFaint, fontSize: 10.5),
                ),
            ],
          ),
          if (petElsewhere)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '桌宠现在由另一位住民控制；$name 的话只会显示在这里，不冒到那只桌宠上。',
                style: TextStyle(color: EchoColors.textFaint, fontSize: 10.5),
              ),
            ),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                match.isActive
                    ? '下棋时说句话吧，TA 会在棋盘边回应你。'
                    : '这局结束了，棋盘边的对话已经收进记忆。',
                style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
              ),
            )
          else
            for (final message in recent)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: _chatLine(message),
              ),
          if (match.isActive) ...[
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chat,
                    enabled: !_chatSending,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendChat(match),
                    style: TextStyle(color: EchoColors.text, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '跟 $name 说句话…',
                      hintStyle: TextStyle(
                        color: EchoColors.textFaint,
                        fontSize: 12,
                      ),
                      filled: true,
                      fillColor: EchoColors.bg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 9,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11),
                        borderSide: BorderSide(color: EchoColors.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11),
                        borderSide: BorderSide(color: EchoColors.divider),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                IconButton(
                  onPressed: _chatSending ? null : () => _sendChat(match),
                  icon: const Icon(Icons.send_rounded, size: 20),
                  color: EchoColors.primary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chatLine(GameMessage message) {
    final mine = message.by == GameSide.user;
    return Row(
      mainAxisAlignment: mine
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!mine) ...[
          Icon(Icons.pets, size: 14, color: EchoColors.primary),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: mine
                  ? EchoColors.primary.withValues(alpha: 0.9)
                  : EchoColors.bg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(mine ? 12 : 4),
                bottomRight: Radius.circular(mine ? 4 : 12),
              ),
            ),
            child: Text(
              message.content,
              style: TextStyle(
                color: mine ? Colors.white : EchoColors.text,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _sendChat(GameMatch match) async {
    final text = _chat.text.trim();
    if (text.isEmpty || _chatSending || !match.isActive) return;
    _chat.clear();
    setState(() => _chatSending = true);
    try {
      final reply = await ref
          .read(gameServiceProvider)
          .sendGameMessage(matchId: match.id, text: text);
      if (reply != null && reply.by == GameSide.resident) {
        // 只有当前桌宠真的属于这位住民时才冒屏上气泡；
        // 桌宠由 B 控制时，A 的话只留在棋盘边，别让 B 的桌宠替 A 说话。
        final pet = ref.read(petControllerProvider);
        if (mounted &&
            pet.enabled &&
            pet.controllerId == match.residentId) {
          unawaited(ref.read(petNativeProvider).say(reply.content));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('TA 这次没接上话')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('没发出去：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _chatSending = false);
    }
  }

  void _maybeAskResident(GameMatch match) {
    if (!match.isActive || match.isUserTurn) return;
    final key = '${match.id}:${match.moveCount}';
    if (_requestedForTurn == key) return;
    _requestedForTurn = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(gameServiceProvider).requestResidentMove(match.id));
    });
  }

  Widget _statusCard(GameMatch match, GameEngine engine, String name) {
    final text = !match.isActive
        ? switch (match.result) {
            'user_win' => '你赢了',
            'resident_win' => '$name 赢了',
            'draw' => '和棋',
            _ => '对局结束',
          }
        : match.isUserTurn
        ? '轮到你了'
        : '$name 正在想';
    final accent = !match.isActive
        ? EchoColors.textMuted
        : match.isUserTurn
        ? EchoColors.primary
        : EchoColors.textMuted;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: EchoColors.divider, width: 0.8),
      ),
      child: Row(
        children: [
          Icon(
            match.isActive ? Icons.sports_esports : Icons.emoji_events_outlined,
            color: accent,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: accent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            match.isActive ? '第 ${match.moveCount + 1} 手' : '共 ${match.moveCount} 手',
            style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _hint(GameMatch match, GameEngine engine) {
    if (!match.isActive) {
      return Center(
        child: Text(
          '这一局已经结束，结果会写进你们的记忆。',
          style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
        ),
      );
    }
    final text = match.gameId == 'xiangqi'
        ? '点自己的棋子，再点落点。你执红。'
        : '点棋盘交叉点落子。你执黑，先走。';
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
    );
  }

  Future<void> _tapGomoku(GameMatch match, int x, int y) async {
    if (_busy || !match.isUserTurn) return;
    final move = '${String.fromCharCode(65 + x)}${y + 1}';
    await _play(match, move);
  }

  Future<void> _tapXiangqi(
    GameMatch match,
    GameEngine engine,
    int x,
    int y,
  ) async {
    if (_busy || !match.isUserTurn) return;
    final code = '${String.fromCharCode(97 + x)}$y';
    final targets = engine.legalMoves(match.board, by: GameSide.user);
    final moves = targets.where((move) => move.startsWith(_selectedCode()));
    final isTarget = _selected != null &&
        moves.any((move) => move.substring(2) == code);
    if (isTarget) {
      final from = _selectedCode();
      setState(() {
        _selected = null;
        _targets.clear();
      });
      await _play(match, '$from$code');
      return;
    }

    // 点到自己的另一颗子：换选中；点空处则取消。
    if (targets.any((move) => move.startsWith(code))) {
      final nextTargets = <(int, int)>{};
      for (final move in targets.where((move) => move.startsWith(code))) {
        final to = move.substring(2);
        nextTargets.add((to.codeUnitAt(0) - 97, int.parse(to.substring(1))));
      }
      setState(() {
        _selected = (x, y);
        _targets
          ..clear()
          ..addAll(nextTargets);
      });
    } else {
      setState(() {
        _selected = null;
        _targets.clear();
      });
    }
  }

  String _selectedCode() {
    final pos = _selected;
    if (pos == null) return '';
    return '${String.fromCharCode(97 + pos.$1)}${pos.$2}';
  }

  Future<void> _play(GameMatch match, String move) async {
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(gameServiceProvider)
          .applyUserMove(matchId: match.id, move: move);
      if (!mounted) return;
      if (!result.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resign(GameMatch match) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('认输？'),
        content: const Text('这一局会立刻结束，结果记成 TA 赢。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('认输'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(gameServiceProvider)
          .resign(matchId: match.id, by: GameSide.user);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
