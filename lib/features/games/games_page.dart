import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../domain/games/game_registry.dart';
import '../../domain/models/custom_resident.dart';
import '../../domain/models/game.dart';
import '../../domain/services/game_service.dart';
import '../../domain/services/resident_wake_service.dart';
import '../shared_widgets/user_avatar.dart';
import 'game_invite_card.dart';
import 'game_providers.dart';

/// 回响模式的「小游戏」页。
///
/// 取代原来的发布 tab：发布挪到首页右上角。这里只负责约局和进入棋局，
/// 具体规则、走棋和上下文由 `GameService` 处理。
class GamesPage extends ConsumerWidget {
  const GamesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final residents = ref.watch(customResidentsProvider).value ?? const [];
    final active = ref.watch(activeGameMatchesProvider).value ?? const [];
    final recent = ref.watch(recentGameMatchesProvider).value ?? const [];
    final invites = ref.watch(allGameInvitesProvider).value ?? const [];
    final byId = {for (final resident in residents) resident.id: resident};
    final now = DateTime.now();

    final waiting = invites
        .where(
          (invite) =>
              invite.status == GameInviteStatus.pending &&
              !invite.fromResident &&
              invite.expiresAt.isAfter(now),
        )
        .toList(growable: false);
    final incoming = invites
        .where(
          (invite) =>
              invite.status == GameInviteStatus.pending &&
              invite.fromResident &&
              invite.expiresAt.isAfter(now),
        )
        .toList(growable: false);
    final finished = recent
        .where((match) => match.status != GameMatchStatus.active)
        .take(8)
        .toList(growable: false);

    return Container(
      color: EchoColors.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          _Header(residents: residents.length),
          const SizedBox(height: 16),
          const _SectionTitle('开始一局'),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final engine in GameRegistry.all)
                    SizedBox(
                      width: width,
                      child: _GameCard(
                        name: engine.definition.name,
                        description: engine.definition.description,
                        icon: engine.definition.id == 'xiangqi'
                            ? Icons.grid_on
                            : Icons.blur_on,
                        onTap: () => _pickResident(
                          context,
                          ref,
                          engine.definition.id,
                          residents,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (waiting.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _SectionTitle('等 TA 回应'),
            const SizedBox(height: 8),
            for (final invite in waiting)
              _WaitingTile(
                invite: invite,
                resident: byId[invite.residentId],
              ),
          ],
          if (incoming.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _SectionTitle('TA 的邀请'),
            const SizedBox(height: 8),
            for (final invite in incoming)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GameInviteCard(
                  inviteId: invite.id,
                  fromMe: false,
                ),
              ),
          ],
          if (active.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _SectionTitle('进行中'),
            const SizedBox(height: 8),
            for (final match in active)
              _MatchTile(
                match: match,
                resident: byId[match.residentId],
                onTap: () => context.push(RoutePaths.gameMatch(match.id)),
              ),
          ],
          if (finished.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _SectionTitle('最近对局'),
            const SizedBox(height: 8),
            for (final match in finished)
              _MatchTile(
                match: match,
                resident: byId[match.residentId],
                onTap: () => context.push(RoutePaths.gameMatch(match.id)),
              ),
          ],
          if (residents.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 22),
              child: Text(
                '还没有固定住民。先去「我的 → 自定义住民」请一个人住进来吧。',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickResident(
    BuildContext context,
    WidgetRef ref,
    String gameId,
    List<CustomResident> residents,
  ) async {
    if (residents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有住民，先去创建一个')),
      );
      return;
    }
    final picked = await showModalBottomSheet<CustomResident>(
      context: context,
      backgroundColor: EchoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text(
                '邀请谁来陪你下棋？',
                style: TextStyle(
                  color: EchoColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final resident in residents)
              ListTile(
                leading: UserAvatar(
                  name: resident.name,
                  avatarRef: resident.avatarAsset,
                  size: 38,
                ),
                title: Text(resident.name),
                subtitle: Text(
                  resident.personality.trim().isEmpty
                      ? '固定住民'
                      : resident.personality.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(sheet).pop(resident),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;

    try {
      await ref
          .read(gameServiceProvider)
          .inviteFromUser(
            residentId: picked.id,
            gameId: gameId,
            note: '来一局？',
          );
      // 用户发起的邀请要马上让住民看到，不等 90 分钟空闲唤醒。
      unawaited(
        ref
            .read(residentWakeServiceProvider)
            .wake(picked.id, trigger: WakeTrigger.userAction),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已邀请 ${picked.name}，等 TA 回应')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('邀请没发出去：$error')),
      );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.residents});

  final int residents;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            EchoColors.primary.withValues(alpha: 0.22),
            EchoColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EchoColors.divider, width: 0.8),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: EchoColors.primary.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.casino_outlined,
              color: EchoColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '小游戏',
                  style: TextStyle(
                    color: EchoColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  residents == 0
                      ? '有住民之后，就能在这里约一局。'
                      : '和 $residents 位住民下一局。棋盘、胜负、记忆都留在本地。',
                  style: TextStyle(
                    color: EchoColors.textMuted,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.name,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final String name;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 13, 13, 14),
        decoration: BoxDecoration(
          color: EchoColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: EchoColors.divider, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 24, color: EchoColors.primary),
            const SizedBox(height: 10),
            Text(
              name,
              style: TextStyle(
                color: EchoColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: EchoColors.textMuted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: EchoColors.text,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _WaitingTile extends StatelessWidget {
  const _WaitingTile({required this.invite, required this.resident});

  final GameInvite invite;
  final CustomResident? resident;

  @override
  Widget build(BuildContext context) {
    final engine = GameRegistry.byId(invite.gameId);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: EchoColors.divider, width: 0.8),
      ),
      child: Row(
        children: [
          UserAvatar(
            name: resident?.name ?? '住民',
            avatarRef: resident?.avatarAsset,
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '已邀请 ${resident?.name ?? 'TA'} 下${engine?.definition.name ?? '棋'}，等回应',
              style: TextStyle(color: EchoColors.textMuted, fontSize: 12),
            ),
          ),
          Icon(Icons.schedule, size: 16, color: EchoColors.textFaint),
        ],
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({
    required this.match,
    required this.resident,
    required this.onTap,
  });

  final GameMatch match;
  final CustomResident? resident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final engine = GameRegistry.byId(match.gameId);
    final isActive = match.status == GameMatchStatus.active;
    final turnText = isActive
        ? (match.isUserTurn ? '轮到你' : 'TA 正在想')
        : switch (match.result) {
            'user_win' => '你赢了',
            'resident_win' => 'TA 赢了',
            'draw' => '和棋',
            _ => '已结束',
          };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: EchoColors.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isActive
                ? EchoColors.primary.withValues(alpha: 0.35)
                : EchoColors.divider,
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            UserAvatar(
              name: resident?.name ?? '住民',
              avatarRef: resident?.avatarAsset,
              size: 34,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${resident?.name ?? 'TA'} · ${engine?.definition.name ?? match.gameId}',
                    style: TextStyle(
                      color: EchoColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${match.moveCount} 手 · $turnText',
                    style: TextStyle(
                      color: match.isUserTurn && isActive
                          ? EchoColors.primary
                          : EchoColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: EchoColors.textFaint, size: 19),
          ],
        ),
      ),
    );
  }
}
