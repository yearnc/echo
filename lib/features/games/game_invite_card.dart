import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/games/game_registry.dart';
import '../../domain/models/game.dart';
import '../../domain/services/game_service.dart';
import 'game_providers.dart';

/// 私信里的游戏邀请卡片。
///
/// 不把邀请状态抄进私信正文：卡片只拿 inviteId，状态从邀请表实时读，
/// 所以接受/拒绝/过期后不用改历史消息。
class GameInviteCard extends ConsumerWidget {
  const GameInviteCard({
    super.key,
    required this.inviteId,
    required this.fromMe,
  });

  final String inviteId;
  final bool fromMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(gameInviteProvider(inviteId));
    final invite = async.value;
    if (invite == null) {
      return _shell(
        context,
        title: '游戏邀请',
        child: Text(
          '这条邀请已经不在了',
          style: TextStyle(color: EchoColors.textFaint, fontSize: 12.5),
        ),
      );
    }
    final engine = GameRegistry.byId(invite.gameId);
    final name = engine?.definition.name ?? invite.gameId;
    final expired =
        invite.status == GameInviteStatus.pending &&
        invite.expiresAt.isBefore(DateTime.now());
    final status = expired ? GameInviteStatus.expired : invite.status;
    final pending = status == GameInviteStatus.pending;
    final canAnswer = pending && invite.fromResident && !fromMe;

    return _shell(
      context,
      title: '来一局$name？',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (invite.note.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                invite.note.trim(),
                style: TextStyle(
                  color: EchoColors.textMuted,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ),
          Text(
            switch (status) {
              GameInviteStatus.pending => invite.fromResident
                  ? 'TA 在等你回应'
                  : '已经邀请 TA，等 TA 回应',
              GameInviteStatus.accepted => '已接受',
              GameInviteStatus.declined => '已拒绝',
              GameInviteStatus.expired => '已过期',
              GameInviteStatus.cancelled => '已取消',
            },
            style: TextStyle(
              color: status == GameInviteStatus.pending
                  ? EchoColors.primary
                  : EchoColors.textFaint,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 10),
          if (canAnswer)
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: EchoColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _accept(context, ref),
                    child: const Text('接受'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: EchoColors.textMuted,
                      side: BorderSide(color: EchoColors.divider),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _decline(context, ref),
                    child: const Text('这次不玩'),
                  ),
                ),
              ],
            )
          else if (status == GameInviteStatus.accepted &&
              invite.matchId != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () =>
                    context.push(RoutePaths.gameMatch(invite.matchId!)),
                child: const Text('进入对局'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(gameServiceProvider).acceptInviteByUser(inviteId);
    if (!context.mounted) return;
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      return;
    }
    final match = result.match;
    if (match != null) context.push(RoutePaths.gameMatch(match.id));
  }

  Future<void> _decline(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(gameServiceProvider)
        .declineInviteByUser(inviteId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.ok ? '已经回绝了邀请' : result.message)),
    );
  }

  Widget _shell(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Container(
      width: 262,
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.casino_outlined, size: 17, color: EchoColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: EchoColors.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }
}
