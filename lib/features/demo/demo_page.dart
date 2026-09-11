import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/demo/demo_script_repository.dart';
import '../../domain/models/demo_script.dart';

/// 演示模式控制台（规划书 §3.12）。
///
/// 存在的唯一理由：**微视频拍摄必须稳定、零成本、可重复**。
/// 三幕脚本全部来自本地 assets，不联网、不调用任何模型。
class DemoPage extends ConsumerWidget {
  const DemoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acts = ref.watch(demoScriptsProvider);

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        title: const Text('演示模式'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: acts.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: EchoColors.primary),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('演示脚本读取失败：$error',
                style: const TextStyle(color: EchoColors.like)),
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Text(
              '所有内容均为本地预置，不联网、不调用模型，可反复重放。\n'
              '播放时可暂停、单步、重置——镜头不满意就再来一遍。',
              style: TextStyle(
                  color: EchoColors.textMuted, fontSize: 12.5, height: 1.7),
            ),
            const SizedBox(height: 16),
            for (final act in list) ...[
              _ActCard(script: act),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: EchoColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EchoColors.divider),
              ),
              child: const Text(
                '演示态下，页面底部的「内容由AI生成，仅供参考」与清醒模式的永久提示照常显示——合规不参与表演。',
                style: TextStyle(
                    color: EchoColors.textFaint, fontSize: 11.5, height: 1.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActCard extends StatelessWidget {
  const _ActCard({required this.script});

  final DemoScript script;

  @override
  Widget build(BuildContext context) {
    final commentCount =
        script.steps.where((step) => step.isComment).length;
    final seconds = (script.effectiveDurationMs / 1000).round();

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: EchoColors.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  script.id.replaceAll('act', ''),
                  style: const TextStyle(
                      color: EchoColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(script.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: EchoColors.text,
                          fontWeight: FontWeight.w700,
                        )),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(script.subtitle,
              style: const TextStyle(
                  color: EchoColors.textMuted, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 10),
          Row(
            children: [
              _Meta(icon: Icons.timeline, text: '${script.steps.length} 个动作'),
              const SizedBox(width: 12),
              _Meta(icon: Icons.timer_outlined, text: '$seconds 秒'),
              const SizedBox(width: 12),
              _Meta(icon: Icons.mode_comment_outlined, text: '$commentCount 条评论'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push(RoutePaths.demoAct(script.id)),
              icon: const Icon(Icons.play_arrow_rounded, size: 19),
              label: const Text('播放这一幕'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: EchoColors.textFaint),
        const SizedBox(width: 5),
        Text(text,
            style: const TextStyle(color: EchoColors.textFaint, fontSize: 11.5)),
      ],
    );
  }
}
