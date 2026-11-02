import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/game_plugin_repository.dart';
import '../../domain/models/game_plugin.dart';
import '../../domain/services/game_service.dart';
import '../../domain/services/resident_sleep_service.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';
import 'game_providers.dart';

/// 声明式插件游戏的对局页（v50）。
///
/// 插件只声明“状态字段 + 工具”，所以这里用一套通用的界面：
/// 上面显示状态，下面把当前可用的工具做成按钮；点开按钮按参数弹一个小表单。
/// 不需要为每个插件写单独的 Flutter 页面。
class PluginGamePage extends ConsumerWidget {
  const PluginGamePage({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(gameMatchProvider(matchId)).value;
    final stateMap = ref.watch(gameStateProvider(matchId)).value;
    final plugins =
        ref.watch(gamePluginsProvider).value ?? const <GamePlugin>[];
    if (match == null || stateMap == null) {
      return Scaffold(
        backgroundColor: EchoColors.bg,
        appBar: AppBar(title: const Text('游戏')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final pluginId = match.gameId.startsWith('plugin:')
        ? match.gameId.substring('plugin:'.length)
        : '';
    GamePlugin? plugin;
    for (final item in plugins) {
      if (item.id == pluginId) {
        plugin = item;
        break;
      }
    }
    if (plugin == null) {
      return Scaffold(
        backgroundColor: EchoColors.bg,
        appBar: AppBar(title: const Text('游戏')),
        body: const Center(child: Text('这个插件已经被删掉了')),
      );
    }
    final interpreter = PluginInterpreter(plugin);
    final finished = !match.isActive;
    final fields = interpreter.describe(stateMap);
    final tools = plugin.tools
        .where((tool) => interpreter.available(tool, stateMap))
        .toList(growable: false);

    return Scaffold(
      backgroundColor: EchoColors.bg,
      bottomNavigationBar: const SafeArea(child: AiDisclaimerBar()),
      appBar: AppBar(
        backgroundColor: EchoColors.bg,
        elevation: 0,
        title: Text('${plugin.name}${finished ? ' · 已结束' : ''}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
            decoration: BoxDecoration(
              color: EchoColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: EchoColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plugin.description.isEmpty ? plugin.name : plugin.description,
                  style: TextStyle(
                    color: EchoColors.textMuted,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
                if (fields.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final line in fields)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        line,
                        style: TextStyle(
                          color: EchoColors.text,
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
                    ),
                ],
                if (finished) ...[
                  const SizedBox(height: 10),
                  Text(
                    match.result.isEmpty ? '这一局结束了。' : match.result,
                    style: TextStyle(
                      color: EchoColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!finished) ...[
            const SizedBox(height: 14),
            Text(
              tools.isEmpty ? '现在没有能做的操作，等住民行动。' : '轮到你行动',
              style: TextStyle(
                color: EchoColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final tool in tools)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: EchoColors.text,
                    side: BorderSide(color: EchoColors.divider),
                    padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
                  ),
                  onPressed: () => _openTool(
                    context,
                    ref,
                    plugin!,
                    interpreter,
                    tool,
                    matchId,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tool.description.isEmpty ? tool.name : tool.description,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (tool.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            tool.name,
                            style: TextStyle(
                              color: EchoColors.textFaint,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _openTool(
    BuildContext context,
    WidgetRef ref,
    GamePlugin plugin,
    PluginInterpreter interpreter,
    PluginTool tool,
    String matchId,
  ) async {
    final properties = tool.parameters['properties'] is Map
        ? Map<String, dynamic>.from(tool.parameters['properties'] as Map)
        : <String, dynamic>{};
    final required = tool.parameters['required'] is List
        ? (tool.parameters['required'] as List).map((item) => '$item').toSet()
        : <String>{};
    final controllers = <String, TextEditingController>{};
    final booleans = <String, bool>{};
    final fields = <String>[];
    for (final entry in properties.entries) {
      if (entry.key == 'match_id') continue;
      final schema = entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map)
          : const <String, dynamic>{};
      final type = '${schema['type'] ?? 'string'}';
      fields.add(entry.key);
      if (type == 'boolean') {
        booleans[entry.key] = false;
      } else {
        controllers[entry.key] = TextEditingController();
      }
    }

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setDialogState) => AlertDialog(
          title: Text(tool.description.isEmpty ? tool.name : tool.description),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (fields.isEmpty)
                  Text(
                    '这个操作不需要额外参数。',
                    style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
                  ),
                for (final key in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: booleans.containsKey(key)
                        ? SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              key,
                              style: TextStyle(
                                color: EchoColors.text,
                                fontSize: 13,
                              ),
                            ),
                            value: booleans[key] ?? false,
                            onChanged: (value) => setDialogState(
                              () => booleans[key] = value,
                            ),
                          )
                        : TextField(
                            controller: controllers[key],
                            decoration: InputDecoration(
                              labelText: key,
                              suffixText: required.contains(key) ? '必填' : '',
                            ),
                          ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                for (final key in required) {
                  if (key == 'match_id') continue;
                  if (controllers[key]?.text.trim().isEmpty ?? false) {
                    return;
                  }
                }
                Navigator.of(dialog).pop(true);
              },
              child: const Text('执行'),
            ),
          ],
        ),
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (submitted != true || !context.mounted) return;

    final players = ref.read(gamePlayersProvider(matchId)).value ?? const [];
    await ref.read(residentSleepServiceProvider).interactAll(
      [
        for (final player in players)
          if (player.residentId.isNotEmpty) player.residentId,
      ],
    );
    if (!context.mounted) return;

    final args = <String, dynamic>{};
    for (final entry in controllers.entries) {
      final raw = entry.value.text.trim();
      final schema = properties[entry.key];
      final type = schema is Map ? '${schema['type']}' : 'string';
      if (type == 'number' || type == 'integer') {
        args[entry.key] = int.tryParse(raw) ?? double.tryParse(raw) ?? raw;
      } else {
        args[entry.key] = raw;
      }
    }
    for (final entry in booleans.entries) {
      args[entry.key] = entry.value;
    }
    final outcome = await ref
        .read(gameServiceProvider)
        .applyPluginUserTool(
          matchId: matchId,
          toolName: tool.name,
          args: args,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(outcome.message)),
    );
  }
}
