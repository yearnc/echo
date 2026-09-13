import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/model_config_repository.dart';
import '../../domain/models/model_config.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';

/// 模型配置中心（规划书 §6.9 / M5）。
class ModelsPage extends ConsumerWidget {
  const ModelsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(modelConfigsProvider);

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          '模型配置中心',
          style: TextStyle(color: EchoColors.text, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: '新增配置',
            icon: const Icon(Icons.add),
            onPressed: () => _create(context, ref),
          ),
        ],
      ),
      bottomNavigationBar: const SafeArea(child: AiDisclaimerBar()),
      body: configs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            '读取失败：$error',
            style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5),
          ),
        ),
        data: (list) => list.isEmpty
            ? _Empty(onCreate: () => _create(context, ref))
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final config in list)
                    _ConfigTile(config: config, onUse: () => _use(ref, config)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                    child: Text(
                      '密钥存在系统钥匙串里（Windows 用 DPAPI、安卓用 Keystore），'
                      '不会写进数据库，也不会传到别处——只有这个 APP 调模型时才用得到。',
                      style: TextStyle(
                        color: EchoColors.textFaint,
                        fontSize: 11.5,
                        height: 1.7,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// 点「+」只是打开一张空表单——**不落库**。
  /// 保存过的东西才配出现在这个列表里。
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    await context.push(RoutePaths.modelNew);
  }

  Future<void> _use(WidgetRef ref, ModelConfig config) async {
    if (config.enabled) return;
    await ref.read(modelConfigRepositoryProvider).setEnabled(config.id);
  }
}

class _ConfigTile extends ConsumerWidget {
  const _ConfigTile({required this.config, required this.onUse});

  final ModelConfig config;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasKey = ref.watch(modelHasKeyProvider(config.id)).value ?? false;

    return ListTile(
      onTap: () => context.push(RoutePaths.modelEdit(config.id)),
      title: Row(
        children: [
          Expanded(
            child: Text(
              config.label,
              style: TextStyle(
                color: config.enabled ? EchoColors.primary : EchoColors.text,
                fontSize: 14,
                fontWeight: config.enabled ? FontWeight.w600 : FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (config.enabled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: EchoColors.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '使用中',
                style: TextStyle(color: EchoColors.primary, fontSize: 10),
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          '${config.model}${hasKey ? '' : ' · 还没填密钥'}',
          style: TextStyle(
            color: hasKey ? EchoColors.textFaint : EchoColors.like,
            fontSize: 11.5,
          ),
        ),
      ),
      trailing: config.enabled
          ? Icon(Icons.check_circle, size: 18, color: EchoColors.primary)
          : TextButton(
              onPressed: onUse,
              style: TextButton.styleFrom(
                foregroundColor: EchoColors.textMuted,
              ),
              child: const Text('启用', style: TextStyle(fontSize: 12.5)),
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '还没有配置任何模型\n配好之后，客观分析可以走你自己的模型。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: EchoColors.textMuted,
              fontSize: 13,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onCreate, child: const Text('新增配置')),
        ],
      ),
    );
  }
}
