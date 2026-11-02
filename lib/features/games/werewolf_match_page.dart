import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/game.dart';
import '../../domain/models/werewolf.dart';
import '../../domain/services/action_registry.dart';
import '../../domain/services/resident_sleep_service.dart';
import '../../domain/services/werewolf_service.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';
import '../shared_widgets/user_avatar.dart';
import 'game_providers.dart';

/// 狼人杀对局页（v50）。
///
/// 视觉参考 `D:\Project\GameWeb\werewolf\web` 的“月下狼影”：
/// 夜色、月亮、森林剪影，顶部一排玩家头像，中间是群聊式的发言与系统消息，
/// 底部才是夜里选人/白天投票的“决策台”。所有规则都在 [WerewolfService]。
class WerewolfMatchPage extends ConsumerStatefulWidget {
  const WerewolfMatchPage({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<WerewolfMatchPage> createState() => _WerewolfMatchPageState();
}

class _WerewolfMatchPageState extends ConsumerState<WerewolfMatchPage> {
  final TextEditingController _speech = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _busy = false;
  bool _advanced = false;
  bool _roleRevealed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(werewolfServiceProvider).advance(widget.matchId));
    });
  }

  @override
  void dispose() {
    _speech.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(werewolfStateProvider(widget.matchId));
    final playersAsync = ref.watch(gamePlayersProvider(widget.matchId));
    final stateJson = stateAsync.value;
    final players = playersAsync.value ?? const <GameMatchPlayer>[];
    if (stateJson == null) {
      return const _WerewolfScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (players.isEmpty) {
      return const _WerewolfScaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              '这一局没有玩家，可能是上次开局中途失败了。回游戏页重新开一局吧。',
              textAlign: TextAlign.center,
              style: TextStyle(color: _W.textMuted, fontSize: 13, height: 1.6),
            ),
          ),
        ),
      );
    }
    final state = WerewolfState.fromJson(stateJson);
    final me = _user(players);
    final entries = _parseLog(state);

    // 有新消息就滚到底；群聊不滚到底会像卡住。
    ref.listen(werewolfStateProvider(widget.matchId), (_, next) {
      if (next.value != null) _scrollToBottom();
    });
    if (!_advanced && !state.awaitingUser && !state.isOver) {
      _advanced = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(ref.read(werewolfServiceProvider).advance(widget.matchId));
      });
    }
    if (!_roleRevealed && me != null) {
      _roleRevealed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRoleReveal(me, state, players);
      });
    }

    final sheriff = state.sheriffId == null
        ? null
        : _bySeat(players, state.sheriffId!);

    return _WerewolfScaffold(
      phase: state.phase,
      body: Column(
        children: [
          _Header(
            state: state,
            sheriff: sheriff,
            me: me,
            players: players,
            onContinue: () => unawaited(
              ref.read(werewolfServiceProvider).advance(widget.matchId),
            ),
          ),
          _PlayerStrip(players: players, me: me, sheriffId: state.sheriffId),
          const Divider(height: 1, color: _W.line),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              itemCount: entries.length,
              itemBuilder: (context, index) =>
                  _ChatRow(entry: entries[index], me: me, players: players),
            ),
          ),
          if (state.awaitingUser)
            _DecisionAltar(
              matchId: widget.matchId,
              state: state,
              players: players,
              me: me!,
              speech: _speech,
              busy: _busy,
              onSubmit: (action) => _submit(action, [
                for (final player in players)
                  if (player.residentId.isNotEmpty) player.residentId,
              ]),
            )
          else if (!state.isOver)
            _WaitingBar(
              text: _waitingText(state),
              busy: _busy,
              onContinue: () => unawaited(
                ref.read(werewolfServiceProvider).advance(widget.matchId),
              ),
            ),
          const _BottomBar(),
        ],
      ),
    );
  }

  Future<void> _submit(
    Future<ActionOutcome> Function() action,
    List<String> residentIds,
  ) async {
    if (_busy) return;
    unawaited(ref.read(residentSleepServiceProvider).interactAll(residentIds));
    setState(() => _busy = true);
    try {
      final outcome = await action();
      if (!mounted) return;
      if (!outcome.ok) {
        _toast(outcome.message);
      } else {
        _speech.clear();
      }
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      _toast('没提交成功：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showRoleReveal(
    GameMatchPlayer me,
    WerewolfState state,
    List<GameMatchPlayer> players,
  ) async {
    final role = WerewolfRole.fromKey(me.role);
    final teammates = role == WerewolfRole.werewolf
        ? [
            for (final player in players)
              if (!player.isUser && player.role == WerewolfRole.werewolf.name)
                '${player.seat}号 ${player.name}',
          ]
        : const <String>[];
    await showDialog<void>(
      context: context,
      builder: (dialog) => Dialog(
        backgroundColor: const Color(0xFF0C1224),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: _W.gold.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '你是 ${me.seat} 号',
                style: const TextStyle(
                  color: _W.textMuted,
                  fontSize: 11.5,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                role.label,
                style: TextStyle(
                  color: role.evil ? _W.bloodBright : _W.gold,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                role.ability,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _W.parchment,
                  fontSize: 12.5,
                  height: 1.65,
                ),
              ),
              if (teammates.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '狼队友：${teammates.join('、')}',
                  style: const TextStyle(color: _W.bloodBright, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _W.gold,
                    foregroundColor: _W.night,
                  ),
                  onPressed: () => Navigator.of(dialog).pop(),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static GameMatchPlayer? _user(List<GameMatchPlayer> players) {
    for (final player in players) {
      if (player.isUser) return player;
    }
    return null;
  }

  static GameMatchPlayer? _bySeat(List<GameMatchPlayer> players, int seat) {
    for (final player in players) {
      if (player.seat == seat) return player;
    }
    return null;
  }

  static String _waitingText(WerewolfState state) {
    if (state.phase == WerewolfPhase.night) return '夜色里，有人正在行动…';
    if (state.phase == WerewolfPhase.sheriffElection) {
      return '警长竞选进行中，听一听别人怎么说…';
    }
    if (state.phase == WerewolfPhase.voting) return '正在等其他人投票…';
    return '正在等其他玩家行动…';
  }

  /// 把服务层的公开日志拆成“群聊消息”和“系统消息”。
  static List<_LogEntry> _parseLog(WerewolfState state) {
    final entries = <_LogEntry>[];
    final speechPattern = RegExp(r'^(\d+)号\s+(.+?)（竞选警长）：(.*)$');
    final normalPattern = RegExp(r'^(\d+)号\s+(.+?)：(.*)$');
    for (final line in state.log) {
      final campaign = speechPattern.firstMatch(line);
      if (campaign != null) {
        entries.add(
          _LogEntry.speech(
            seat: int.tryParse(campaign.group(1)!) ?? 0,
            name: campaign.group(2)!.trim(),
            text: campaign.group(3)!.trim(),
            campaign: true,
          ),
        );
        continue;
      }
      final speech = normalPattern.firstMatch(line);
      if (speech != null) {
        entries.add(
          _LogEntry.speech(
            seat: int.tryParse(speech.group(1)!) ?? 0,
            name: speech.group(2)!.trim(),
            text: speech.group(3)!.trim(),
          ),
        );
        continue;
      }
      entries.add(_LogEntry.system(line, tone: _toneOf(line)));
    }
    return entries;
  }

  static _Tone _toneOf(String line) {
    if (line.contains('死了') ||
        line.contains('被放逐') ||
        line.contains('开枪') ||
        line.contains('出局')) {
      return _Tone.death;
    }
    if (line.contains('平安夜')) return _Tone.peace;
    if (line.contains('投票') || line.contains('票型') || line.contains('弃权')) {
      return _Tone.vote;
    }
    if (line.contains('警长') ||
        line.contains('上警') ||
        line.contains('警徽') ||
        line.contains('竞选')) {
      return _Tone.election;
    }
    if (line.contains('第 ') ||
        line.contains('天黑') ||
        line.contains('天亮') ||
        line.contains('夜')) {
      return _Tone.phase;
    }
    return _Tone.normal;
  }
}

// ---------------------------------------------------------------------------
// 夜色背景
// ---------------------------------------------------------------------------

class _WerewolfScaffold extends StatelessWidget {
  const _WerewolfScaffold({required this.body, this.phase});

  final Widget body;
  final WerewolfPhase? phase;

  @override
  Widget build(BuildContext context) {
    final day =
        phase == WerewolfPhase.dayAnnounce ||
        phase == WerewolfPhase.speaking ||
        phase == WerewolfPhase.voting ||
        phase == WerewolfPhase.sheriffElection;
    return Scaffold(
      backgroundColor: _W.night,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 900),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: day
                      ? const [Color(0xFF111A20), Color(0xFF0B1224)]
                      : const [Color(0xFF04060C), Color(0xFF0B1224)],
                ),
              ),
            ),
          ),
          const Positioned.fill(child: CustomPaint(painter: _StarPainter())),
          Positioned(
            top: -56,
            right: -44,
            child: IgnorePointer(
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [
                      Color(0xFFFAF8F0),
                      Color(0xFFD8D0A8),
                      Color(0xFF807040),
                    ],
                    stops: [0.0, 0.55, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFDCD2B4).withValues(alpha: 0.28),
                      blurRadius: 90,
                      spreadRadius: 18,
                    ),
                    BoxShadow(
                      color: const Color(0xFFDCD2B4).withValues(alpha: 0.10),
                      blurRadius: 180,
                      spreadRadius: 30,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 150,
            child: IgnorePointer(child: CustomPaint(painter: _ForestPainter())),
          ),
          SafeArea(child: body),
        ],
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  const _StarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.55);
    for (var i = 0; i < 42; i++) {
      final x = (math.sin(i * 12.9898) * 43758.5453).abs() % 1;
      final y = (math.sin(i * 78.233) * 12543.123).abs() % 1;
      final radius = i % 7 == 0 ? 1.4 : 0.8;
      canvas.drawCircle(
        Offset(x * size.width, y * size.height * 0.72),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ForestPainter extends CustomPainter {
  const _ForestPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF040A06);
    final path = Path()..moveTo(0, size.height);
    const peaks = 18;
    for (var i = 0; i <= peaks; i++) {
      final x = size.width * i / peaks;
      final height = size.height * (0.35 + (i % 4) * 0.12);
      path.lineTo(x, size.height - height);
      path.lineTo(x + size.width / peaks / 2, size.height - height * 0.45);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 顶部、玩家头像条、底部
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.sheriff,
    required this.me,
    required this.players,
    required this.onContinue,
  });

  final WerewolfState state;
  final GameMatchPlayer? sheriff;
  final GameMatchPlayer? me;
  final List<GameMatchPlayer> players;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final phase = _phaseLabel(state);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _W.line)),
        color: Color(0xAA04060C),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: _W.parchment),
            tooltip: '退出',
          ),
          Icon(
            state.phase == WerewolfPhase.night
                ? Icons.nightlight_round
                : Icons.wb_sunny_outlined,
            size: 18,
            color: _W.gold,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phase,
                  style: const TextStyle(
                    color: _W.gold,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '第 ${state.night} 夜 / 第 ${state.day} 天'
                  '${sheriff == null ? '' : ' · 警长 ${sheriff!.seat}号 ${sheriff!.name}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _W.textMuted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          if (sheriff != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _W.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _W.gold.withValues(alpha: 0.3)),
              ),
              child: const Text(
                '★ 警长',
                style: TextStyle(color: _W.gold, fontSize: 10),
              ),
            ),
          IconButton(
            tooltip: '身份与私密信息',
            onPressed: () => _showSecret(context),
            icon: const Icon(Icons.lock_outline, color: _W.textMuted, size: 18),
          ),
          TextButton(
            onPressed: onContinue,
            child: const Text(
              '继续',
              style: TextStyle(color: _W.textMuted, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSecret(BuildContext context) async {
    final seat = me?.seat;
    final role = me == null ? null : WerewolfRole.fromKey(me!.role);
    final logs = seat == null
        ? const <String>[]
        : (state.privateLog[seat] ?? const <String>[]);
    final teammates = role == WerewolfRole.werewolf
        ? [
            for (final player in players)
              if (!player.isUser && player.role == WerewolfRole.werewolf.name)
                '${player.seat}号 ${player.name}',
          ]
        : const <String>[];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0C1224),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          children: [
            Text(
              me == null ? '你的身份' : '你是 ${me!.seat} 号 · ${me!.name}',
              style: const TextStyle(
                color: _W.gold,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (role != null) ...[
              const SizedBox(height: 6),
              Text(
                '身份：${role.label}',
                style: const TextStyle(
                  color: _W.parchment,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                role.ability,
                style: const TextStyle(
                  color: _W.textMuted,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ],
            if (teammates.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '你的狼队友：${teammates.join('、')}',
                style: const TextStyle(color: _W.bloodBright, fontSize: 12),
              ),
            ],
            if (state.sheriffId != null) ...[
              const SizedBox(height: 8),
              Text(
                '当前警长：${state.sheriffId} 号（1.5 票，最后发言）',
                style: const TextStyle(color: _W.gold, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              '只有你知道的事',
              style: TextStyle(
                color: _W.parchment,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            if (logs.isEmpty)
              const Text(
                '暂时没有私密信息。',
                style: TextStyle(color: _W.textFaint, fontSize: 12),
              )
            else
              for (final line in logs.reversed.take(12))
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    line,
                    style: const TextStyle(
                      color: _W.textMuted,
                      fontSize: 12,
                      height: 1.55,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  static String _phaseLabel(WerewolfState state) {
    if (state.isOver) {
      return state.winner == 'good' ? '好人阵营获胜' : '狼人阵营获胜';
    }
    return switch (state.phase) {
      WerewolfPhase.night => '月下狼影 · 第 ${state.night} 夜',
      WerewolfPhase.dayAnnounce => '天亮了 · 公布',
      WerewolfPhase.sheriffElection => '警长竞选',
      WerewolfPhase.speaking => '第 ${state.day} 天 · 发言',
      WerewolfPhase.voting => '第 ${state.day} 天 · 投票',
      WerewolfPhase.hunter => '猎人开枪',
      WerewolfPhase.over => '对局结束',
    };
  }
}

class _PlayerStrip extends StatelessWidget {
  const _PlayerStrip({
    required this.players,
    required this.me,
    required this.sheriffId,
  });

  final List<GameMatchPlayer> players;
  final GameMatchPlayer? me;
  final int? sheriffId;

  @override
  Widget build(BuildContext context) {
    final myRole = me == null ? null : WerewolfRole.fromKey(me!.role);
    return Container(
      height: 100,
      color: const Color(0x6604060C),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        itemCount: players.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final player = players[index];
          final role = WerewolfRole.fromKey(player.role);
          final isMe = player.isUser;
          final ally =
              myRole == WerewolfRole.werewolf &&
              role == WerewolfRole.werewolf &&
              !isMe;
          final dead = !player.alive;
          final sheriff = player.seat == sheriffId;
          final border = dead
              ? const Color(0xFF5A2020)
              : isMe
              ? _W.green
              : sheriff
              ? _W.gold
              : ally
              ? _W.blood
              : _W.lineBright;
          return Opacity(
            opacity: dead ? 0.42 : 1,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: border, width: 1.6),
                        boxShadow: _aliveGlow(dead, isMe, sheriff),
                      ),
                      child: UserAvatar(
                        name: player.name,
                        avatarRef: player.avatarAsset.isEmpty
                            ? null
                            : player.avatarAsset,
                        size: 34,
                      ),
                    ),
                    if (sheriff)
                      const Positioned(
                        right: -3,
                        bottom: -3,
                        child: Text(
                          '★',
                          style: TextStyle(color: _W.gold, fontSize: 13),
                        ),
                      ),
                    if (dead)
                      const Positioned(
                        right: -2,
                        top: -2,
                        child: Icon(Icons.close, size: 12, color: _W.blood),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${player.seat}号',
                  style: const TextStyle(
                    color: _W.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  player.name.length > 4
                      ? player.name.substring(0, 4)
                      : player.name,
                  style: TextStyle(
                    color: isMe ? _W.green : _W.parchment,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static List<BoxShadow> _aliveGlow(bool dead, bool isMe, bool sheriff) {
    if (dead) return const [];
    if (sheriff) {
      return [
        BoxShadow(
          color: _W.gold.withValues(alpha: 0.25),
          blurRadius: 12,
          spreadRadius: 1,
        ),
      ];
    }
    if (isMe) {
      return [
        BoxShadow(color: _W.green.withValues(alpha: 0.22), blurRadius: 10),
      ];
    }
    return const [];
  }
}

class _WaitingBar extends StatelessWidget {
  const _WaitingBar({
    required this.text,
    required this.busy,
    required this.onContinue,
  });

  final String text;
  final bool busy;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Color(0xE6080C18),
        border: Border(top: BorderSide(color: _W.line)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.8, color: _W.gold),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: _W.textMuted, fontSize: 11.5),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onContinue,
            child: const Text('继续', style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 2),
      color: const Color(0xF004060C),
      child: const AiDisclaimerBar(dark: true),
    );
  }
}

// ---------------------------------------------------------------------------
// 群聊消息
// ---------------------------------------------------------------------------

enum _Tone { normal, phase, death, peace, vote, election }

class _LogEntry {
  const _LogEntry.system(this.text, {required this.tone})
    : seat = 0,
      name = '',
      speech = false,
      campaign = false;

  const _LogEntry.speech({
    required this.seat,
    required this.name,
    required this.text,
    this.campaign = false,
  }) : tone = _Tone.normal,
       speech = true;

  final String text;
  final _Tone tone;
  final int seat;
  final String name;
  final bool speech;
  final bool campaign;
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.entry,
    required this.me,
    required this.players,
  });

  final _LogEntry entry;
  final GameMatchPlayer? me;
  final List<GameMatchPlayer> players;

  @override
  Widget build(BuildContext context) {
    if (!entry.speech) {
      return _SystemMessage(entry: entry);
    }
    final mine = me != null && entry.seat == me!.seat;
    final player = _find(entry.seat);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            _ChatAvatar(
              player: player,
              seat: entry.seat,
              dead: !(player?.alive ?? true),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Text(
                    '${entry.seat}号 ${entry.name}${mine ? '（你）' : ''}',
                    style: TextStyle(
                      color: mine
                          ? _W.green.withValues(alpha: 0.8)
                          : _W.textMuted,
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                  decoration: BoxDecoration(
                    color: mine
                        ? const Color(0xE63C4630)
                        : entry.campaign
                        ? const Color(0xE64A4020)
                        : const Color(0xE642382C),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(mine ? 14 : 3),
                      topRight: Radius.circular(mine ? 3 : 14),
                      bottomLeft: const Radius.circular(14),
                      bottomRight: const Radius.circular(14),
                    ),
                    border: Border(
                      left: mine || entry.campaign
                          ? BorderSide.none
                          : BorderSide(
                              color: _W.lineBright.withValues(alpha: 0.5),
                              width: 2,
                            ),
                      right: mine
                          ? BorderSide(
                              color: _W.green.withValues(alpha: 0.25),
                              width: 2,
                            )
                          : BorderSide.none,
                    ),
                  ),
                  child: Text(
                    entry.text,
                    style: TextStyle(
                      color: mine
                          ? const Color(0xFFE6F0D8)
                          : entry.campaign
                          ? const Color(0xFFE6D8A8)
                          : _W.parchment,
                      fontSize: 13,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (mine) ...[
            const SizedBox(width: 8),
            _ChatAvatar(player: player, seat: entry.seat, dead: false),
          ],
        ],
      ),
    );
  }

  GameMatchPlayer? _find(int seat) {
    for (final player in players) {
      if (player.seat == seat) return player;
    }
    return null;
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({
    required this.player,
    required this.seat,
    required this.dead,
  });

  final GameMatchPlayer? player;
  final int seat;
  final bool dead;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dead ? 0.45 : 1,
      child: UserAvatar(
        name: player?.name ?? '$seat号',
        avatarRef: (player?.avatarAsset.isEmpty ?? true)
            ? null
            : player!.avatarAsset,
        size: 28,
      ),
    );
  }
}

class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.entry});

  final _LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.tone) {
      _Tone.phase => _W.gold,
      _Tone.death => _W.bloodBright,
      _Tone.peace => _W.green,
      _Tone.vote => _W.purple,
      _Tone.election => _W.gold,
      _Tone.normal => _W.textMuted,
    };
    final phase = entry.tone == _Tone.phase;
    return Padding(
      padding: EdgeInsets.only(top: phase ? 14 : 3, bottom: phase ? 12 : 6),
      child: Center(
        child: Container(
          padding: phase
              ? const EdgeInsets.symmetric(vertical: 5)
              : const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: phase
              ? null
              : BoxDecoration(
                  color: color.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.22)),
                ),
          child: Text(
            entry.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: phase ? 11.5 : 11,
              fontWeight: phase ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: phase ? 2.2 : 0.2,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 决策台
// ---------------------------------------------------------------------------

class _DecisionAltar extends ConsumerWidget {
  const _DecisionAltar({
    required this.matchId,
    required this.state,
    required this.players,
    required this.me,
    required this.speech,
    required this.busy,
    required this.onSubmit,
  });

  final String matchId;
  final WerewolfState state;
  final List<GameMatchPlayer> players;
  final GameMatchPlayer me;
  final TextEditingController speech;
  final bool busy;
  final Future<void> Function(Future<ActionOutcome> Function()) onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(werewolfServiceProvider);
    return Container(
      constraints: const BoxConstraints(maxHeight: 330),
      decoration: BoxDecoration(
        color: const Color(0xF20C1224),
        border: Border(
          top: BorderSide(color: _W.green.withValues(alpha: 0.22), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 18,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: switch (state.awaiting) {
          'user_night' => _nightPanel(context, service),
          'user_sheriff_run' => _sheriffRunPanel(context, service),
          'user_sheriff_speech' => _sheriffSpeechPanel(context, service),
          'user_sheriff_vote' => _sheriffVotePanel(context, service),
          'user_speech' => _speechPanel(context, service),
          'user_vote' => _votePanel(context, service, hunter: false),
          'user_hunter' => _votePanel(context, service, hunter: true),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  Widget _nightPanel(BuildContext context, WerewolfService service) {
    final role = WerewolfRole.fromKey(me.role);
    final alive = players.where((item) => item.alive).toList();
    if (role == WerewolfRole.werewolf) {
      final candidates = alive
          .where((item) => item.role != WerewolfRole.werewolf.name)
          .toList();
      return _panel(
        context,
        title: '选择今晚要刀的人',
        subtitle: '狼队已经讨论过了；你选完后就进入下一步。',
        child: _seatButtons(
          candidates,
          onTap: (seat) => onSubmit(
            () => service.submitNight(matchId: matchId, target: seat),
          ),
        ),
      );
    }
    if (role == WerewolfRole.seer) {
      return _panel(
        context,
        title: '选择要查验的人',
        subtitle: state.seerResult == null
            ? '查验结果只有你自己能看到。'
            : '上次查验：${state.seerTarget}号 · '
                  '${state.seerResult == true ? '狼人' : '好人'}',
        child: _seatButtons(
          alive.where((item) => item.seat != me.seat).toList(),
          onTap: (seat) => onSubmit(
            () => service.submitNight(matchId: matchId, target: seat),
          ),
        ),
      );
    }
    if (role == WerewolfRole.witch) {
      return _panel(
        context,
        title: '女巫用药',
        subtitle: state.nightKill == null
            ? '今晚没有人被刀。'
            : '今晚 ${state.nightKill} 号被刀了。'
                  '${state.witchSaveAvailable ? '' : '解药已经用过了。'}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.witchSaveAvailable && state.nightKill != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => onSubmit(
                          () =>
                              service.submitNight(matchId: matchId, save: true),
                        ),
                  child: const Text('用解药救 TA'),
                ),
              ),
            const SizedBox(height: 8),
            if (state.witchPoisonAvailable) ...[
              Text(
                '要不要用毒药？',
                style: TextStyle(color: _W.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              _seatButtons(
                alive.where((item) => item.seat != me.seat).toList(),
                onTap: (seat) => onSubmit(
                  () => service.submitNight(
                    matchId: matchId,
                    save: false,
                    poison: seat,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: busy
                    ? null
                    : () => onSubmit(
                        () =>
                            service.submitNight(matchId: matchId, save: false),
                      ),
                child: const Text('不用药，直接过'),
              ),
            ),
          ],
        ),
      );
    }
    return _panel(
      context,
      title: '夜晚',
      subtitle: '你的身份今晚没有行动。',
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy
              ? null
              : () => onSubmit(() => service.submitNight(matchId: matchId)),
          child: const Text('继续'),
        ),
      ),
    );
  }

  Widget _sheriffRunPanel(BuildContext context, WerewolfService service) {
    return _panel(
      context,
      title: '要不要上警？',
      subtitle: '上警能争取警长（1.5 票、最后发言），但会失去警长投票权。',
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: busy
                  ? null
                  : () => onSubmit(
                      () =>
                          service.submitSheriffRun(matchId: matchId, run: true),
                    ),
              child: const Text('上警'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: busy
                  ? null
                  : () => onSubmit(
                      () => service.submitSheriffRun(
                        matchId: matchId,
                        run: false,
                      ),
                    ),
              child: const Text('不上警'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheriffSpeechPanel(BuildContext context, WerewolfService service) {
    return _panel(
      context,
      title: '竞选警长发言',
      subtitle: '说 1—2 句，争取非候选人的警徽票。不想说也可以跳过。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _textField(controller: speech, hint: '比如：我上警是想把节奏带起来，警徽票给我。'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () => onSubmit(
                          () => service.submitSheriffSpeech(
                            matchId: matchId,
                            text: speech.text,
                          ),
                        ),
                  child: const Text('发表竞选发言'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => onSubmit(
                          () => service.submitSheriffSpeech(
                            matchId: matchId,
                            text: '',
                          ),
                        ),
                  child: const Text('跳过'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sheriffVotePanel(BuildContext context, WerewolfService service) {
    final candidates = players
        .where((item) => state.candidates.contains(item.seat))
        .toList();
    return _panel(
      context,
      title: '投警长票',
      subtitle: '只有非候选人能投；警长拥有 1.5 票并在每天最后发言。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _seatButtons(
            candidates,
            onTap: (seat) => onSubmit(
              () => service.submitSheriffVote(matchId: matchId, target: seat),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: busy
                  ? null
                  : () => onSubmit(
                      () => service.submitSheriffVote(
                        matchId: matchId,
                        target: 0,
                      ),
                    ),
              child: const Text('弃权'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _speechPanel(BuildContext context, WerewolfService service) {
    return _panel(
      context,
      title: '轮到你发言',
      subtitle: '说 1—2 句；不想说也可以直接跳过。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _textField(controller: speech, hint: '比如：我怀疑 3 号，刚才那句话太急了。'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () => onSubmit(
                          () => service.submitSpeech(
                            matchId: matchId,
                            text: speech.text,
                          ),
                        ),
                  child: const Text('发言'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => onSubmit(
                          () =>
                              service.submitSpeech(matchId: matchId, text: ''),
                        ),
                  child: const Text('跳过'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _votePanel(
    BuildContext context,
    WerewolfService service, {
    required bool hunter,
  }) {
    final alive = players.where((item) => item.alive).toList();
    final candidates = alive.where((item) => item.seat != me.seat).toList();
    return _panel(
      context,
      title: hunter ? '你是猎人，开枪带走一个人' : '投票放逐一个人',
      subtitle: hunter ? '被毒杀时不能开枪；这次可以。' : '平票时没有人被放逐。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _seatButtons(
            candidates,
            onTap: (seat) => onSubmit(
              () => hunter
                  ? service.submitHunter(matchId: matchId, target: seat)
                  : service.submitVote(matchId: matchId, target: seat),
            ),
          ),
          if (!hunter) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: busy
                    ? null
                    : () => onSubmit(
                        () => service.submitVote(matchId: matchId, target: 0),
                      ),
                child: const Text('弃权'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _panel(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: _W.green,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: _W.parchment,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (busy)
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: _W.gold,
                ),
              ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            color: _W.textMuted,
            fontSize: 11,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 9),
        child,
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      maxLines: 3,
      minLines: 2,
      enabled: !busy,
      style: const TextStyle(color: _W.parchment, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _W.textFaint, fontSize: 11.5),
        filled: true,
        fillColor: const Color(0xCC060A14),
        contentPadding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: _W.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: _W.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: _W.green.withValues(alpha: 0.6)),
        ),
      ),
    );
  }

  Widget _seatButtons(
    List<GameMatchPlayer> players, {
    required void Function(int seat) onTap,
  }) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final player in players)
          OutlinedButton(
            onPressed: busy ? null : () => onTap(player.seat),
            style: OutlinedButton.styleFrom(
              foregroundColor: _W.parchment,
              side: const BorderSide(color: _W.lineBright),
              backgroundColor: const Color(0x66080C18),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              '${player.seat}号 ${player.name}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 配色
// ---------------------------------------------------------------------------

class _W {
  static const night = Color(0xFF04060C);
  static const parchment = Color(0xFFE8E0C8);
  static const textMuted = Color(0xFFA8A090);
  static const textFaint = Color(0xFF706A60);
  static const gold = Color(0xFFD4A843);
  static const blood = Color(0xFF9B2020);
  static const bloodBright = Color(0xFFE84040);
  static const green = Color(0xFF4ADE80);
  static const purple = Color(0xFF8B5CF6);
  static const line = Color(0x22FFFFFF);
  static const lineBright = Color(0x33FFFFFF);
}
