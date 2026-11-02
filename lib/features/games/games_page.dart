import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/game_plugin_repository.dart';
import '../../domain/games/game_registry.dart';
import '../../domain/models/custom_resident.dart';
import '../../domain/models/game.dart';
import '../../domain/models/game_plugin.dart';
import '../../domain/services/game_service.dart';
import '../../domain/services/resident_sleep_service.dart';
import '../../domain/services/werewolf_service.dart';
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
    final plugins =
        ref.watch(gamePluginsProvider).value ?? const <GamePlugin>[];
    final definitions = <GameDefinition>[
      ...GameRegistry.definitions,
      for (final plugin in plugins)
        if (plugin.enabled) plugin.definition,
    ];
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
          Row(
            children: [
              const Expanded(child: _SectionTitle('开始一局')),
              TextButton.icon(
                onPressed: () => _openUpload(context, ref),
                icon: const Icon(Icons.upload_file, size: 17),
                label: const Text('上传游戏'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final definition in definitions)
                    SizedBox(
                      width: width,
                      child: _GameCard(
                        name: definition.name,
                        description: definition.description,
                        icon: _iconFor(definition),
                        badge: definition.plugin
                            ? '插件'
                            : (definition.multiplayer ? '多人' : ''),
                        onTap: () =>
                            _pickResident(context, ref, definition, residents),
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
              _WaitingTile(invite: invite, resident: byId[invite.residentId]),
          ],
          if (incoming.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _SectionTitle('TA 的邀请'),
            const SizedBox(height: 8),
            for (final invite in incoming)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GameInviteCard(inviteId: invite.id, fromMe: false),
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
    GameDefinition definition,
    List<CustomResident> residents,
  ) async {
    final soloPlugin = definition.plugin && definition.maxPlayers <= 1;
    if (residents.isEmpty && definition.id != 'werewolf' && !soloPlugin) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('还没有住民，先去创建一个')));
      return;
    }
    if (definition.multiplayer || definition.id == 'werewolf') {
      await _pickManyAndStart(context, ref, definition, residents);
      return;
    }
    if (definition.plugin) {
      if (definition.maxPlayers <= 1) {
        await _startPlugin(context, ref, definition, const []);
        return;
      }
      final picked = await _pickOne(
        context,
        residents,
        '和谁玩「${definition.name}」？',
      );
      if (picked == null || !context.mounted) return;
      await _startPlugin(context, ref, definition, [picked]);
      return;
    }
    final picked = await _pickOne(context, residents, '邀请谁来陪你下棋？');
    if (picked == null || !context.mounted) return;

    try {
      await ref
          .read(gameServiceProvider)
          .inviteFromUser(
            residentId: picked.id,
            gameId: definition.id,
            note: '来一局？',
          );
      // 用户发起的邀请要马上让住民看到，不等 90 分钟空闲唤醒。
      unawaited(_wakePlayers(ref, [picked.id]));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已邀请 ${picked.name}，等 TA 回应')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('邀请没发出去：$error')));
    }
  }

  Future<CustomResident?> _pickOne(
    BuildContext context,
    List<CustomResident> residents,
    String title,
  ) {
    return showModalBottomSheet<CustomResident>(
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
                title,
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
                  avatarRef: resident.avatarAsset.isEmpty
                      ? null
                      : resident.avatarAsset,
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
  }

  /// 多人房间：一次勾选多位住民。
  Future<void> _pickManyAndStart(
    BuildContext context,
    WidgetRef ref,
    GameDefinition definition,
    List<CustomResident> residents,
  ) async {
    final maxResidents = definition.maxPlayers - 1;
    final minResidents = definition.id == 'werewolf'
        ? 0
        : (definition.minPlayers - 1).clamp(0, maxResidents);
    final selected = <String>{};
    final picked = await showModalBottomSheet<List<CustomResident>>(
      context: context,
      backgroundColor: EchoColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheetState) {
          final enough = selected.length >= minResidents;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(
                        color: EchoColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '「${definition.name}」要几个人？',
                    style: TextStyle(
                      color: EchoColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    definition.id == 'werewolf'
                        ? '固定 9 人局。选中的住民和你一起坐进去，'
                              '剩下的位置由内置 AI 玩家补足；不选也可以全 AI 开局。'
                        : '最多可选 $maxResidents 位住民。插件里的操作和发言由你们共同推进。',
                    style: TextStyle(
                      color: EchoColors.textMuted,
                      fontSize: 12,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final resident in residents)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: selected.contains(resident.id),
                            onChanged: (checked) {
                              if (checked == true &&
                                  selected.length >= maxResidents) {
                                return;
                              }
                              setSheetState(() {
                                if (checked == true) {
                                  selected.add(resident.id);
                                } else {
                                  selected.remove(resident.id);
                                }
                              });
                            },
                            secondary: UserAvatar(
                              name: resident.name,
                              avatarRef: resident.avatarAsset.isEmpty
                                  ? null
                                  : resident.avatarAsset,
                              size: 34,
                            ),
                            title: Text(resident.name),
                            subtitle: Text(
                              resident.personality.trim().isEmpty
                                  ? '固定住民'
                                  : resident.personality.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '已选 ${selected.length} 位'
                          '${definition.id == 'werewolf' ? ' · AI 补 ${8 - selected.length} 位' : ''}',
                          style: TextStyle(
                            color: EchoColors.textFaint,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: enough
                            ? () => Navigator.of(sheet).pop([
                                for (final resident in residents)
                                  if (selected.contains(resident.id)) resident,
                              ])
                            : null,
                        child: const Text('开局'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (picked == null || !context.mounted) return;
    final ids = [for (final resident in picked) resident.id];
    await _wakePlayers(ref, ids);
    if (!context.mounted) return;
    try {
      if (definition.id == 'werewolf') {
        final match = await ref.read(werewolfServiceProvider).startGame(ids);
        if (!context.mounted) return;
        context.push(RoutePaths.gameMatch(match.id));
        return;
      }
      await _startPlugin(context, ref, definition, picked);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('开局失败：$error')));
    }
  }

  Future<void> _startPlugin(
    BuildContext context,
    WidgetRef ref,
    GameDefinition definition,
    List<CustomResident> picked,
  ) async {
    final pluginId = definition.id.startsWith('plugin:')
        ? definition.id.substring('plugin:'.length)
        : '';
    if (pluginId.isEmpty) return;
    await _wakePlayers(ref, [for (final resident in picked) resident.id]);
    final result = await ref
        .read(gameServiceProvider)
        .startPluginMatch(
          pluginId: pluginId,
          residentIds: [for (final resident in picked) resident.id],
        );
    if (!context.mounted) return;
    if (!result.ok || result.match == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }
    context.push(RoutePaths.gameMatch(result.match!.id));
  }

  /// 约局/开局都是直接找 TA：在睡着的住民会在这里被叫醒。
  Future<void> _wakePlayers(WidgetRef ref, List<String> ids) =>
      ref.read(residentSleepServiceProvider).interactAll(ids);

  static IconData _iconFor(GameDefinition definition) {
    if (definition.plugin) return Icons.extension_outlined;
    return switch (definition.id) {
      'xiangqi' => Icons.grid_on,
      'werewolf' => Icons.nightlight_round,
      _ => Icons.blur_on,
    };
  }

  Future<void> _openUpload(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EchoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheet) => Consumer(
        builder: (sheet, sheetRef, _) => StatefulBuilder(
          builder: (sheet, setSheetState) {
            final installed =
                sheetRef.watch(gamePluginsProvider).value ??
                const <GamePlugin>[];
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  16 + MediaQuery.of(sheet).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '上传游戏',
                      style: TextStyle(
                        color: EchoColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '粘贴 GitHub 仓库链接。仓库根目录需要有 echo-game.json，'
                      '里面用 JSON 声明游戏状态、工具和规则；APP 只下载这一份清单，'
                      '不执行远程代码。国内网络会自动尝试 gh-proxy 镜像。',
                      style: TextStyle(
                        color: EchoColors.textMuted,
                        fontSize: 12,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        hintText: 'https://github.com/owner/repo',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          final url = controller.text.trim();
                          if (url.isEmpty) return;
                          try {
                            final plugin = await sheetRef
                                .read(gamePluginRepositoryProvider)
                                .installFromUrl(url);
                            if (!sheet.mounted) return;
                            setSheetState(() {});
                            controller.clear();
                            ScaffoldMessenger.of(sheet).showSnackBar(
                              SnackBar(content: Text('已安装「${plugin.name}」')),
                            );
                          } catch (error) {
                            if (!sheet.mounted) return;
                            ScaffoldMessenger.of(sheet).showSnackBar(
                              SnackBar(content: Text('安装失败：$error')),
                            );
                          }
                        },
                        child: const Text('下载并安装'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (installed.isNotEmpty) ...[
                      Text(
                        '已安装',
                        style: TextStyle(
                          color: EchoColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final plugin in installed)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.extension_outlined,
                            size: 20,
                          ),
                          title: Text(plugin.name),
                          subtitle: Text(
                            plugin.enabled
                                ? '${plugin.minPlayers}—${plugin.maxPlayers} 人 · ${plugin.sourceUrl}'
                                : '清单损坏或已停用',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: '删除',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () async {
                              await sheetRef
                                  .read(gamePluginRepositoryProvider)
                                  .remove(plugin.id);
                              if (!sheet.mounted) return;
                              setSheetState(() {});
                            },
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    controller.dispose();
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
    this.badge = '',
  });

  final String name;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  final String badge;

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
            Row(
              children: [
                Icon(icon, size: 24, color: EchoColors.primary),
                const Spacer(),
                if (badge.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: EchoColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(color: EchoColors.primary, fontSize: 10),
                    ),
                  ),
              ],
            ),
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
    final werewolf = match.gameId == 'werewolf';
    final plugin = match.gameId.startsWith('plugin:');
    final title = werewolf
        ? '狼人杀 · 9 人局'
        : plugin
        ? '插件游戏'
        : '${resident?.name ?? 'TA'} · ${engine?.definition.name ?? match.gameId}';
    final isActive = match.status == GameMatchStatus.active;
    final turnText = isActive
        ? match.isUserTurn
              ? '轮到你'
              : 'TA 正在想'
        : switch (match.result) {
            'user_win' => '你赢了',
            'resident_win' => 'TA 赢了',
            'draw' => '和棋',
            'good' => '好人阵营获胜',
            'evil' => '狼人阵营获胜',
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
                    title,
                    style: TextStyle(
                      color: EchoColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    werewolf
                        ? '$turnText · 共 ${match.moveCount} 轮'
                        : '${match.moveCount} 手 · $turnText',
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
