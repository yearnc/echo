import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/services/mode_controller.dart';

/// 演示模式控制台（规划书 §3.12）。
///
/// 存在的唯一理由：**微视频拍摄必须稳定、零成本、可重复**。
/// 所以这里的内容全部读预置 JSON，不依赖网络、不调用任何 API。
/// 阶段 A 先把三幕脚本读出来、把播放器的骨架搭好；
/// 逐帧播放（点赞爬升、评论逐条出现）在 M3 落地。
class DemoPage extends ConsumerWidget {
  const DemoPage({super.key});

  static const List<String> _assets = [
    'assets/demo/act1.json',
    'assets/demo/act2.json',
    'assets/demo/act3.json',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acts = ref.watch(_demoActsProvider);

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
              '所有内容均为本地预置，不联网、不调用模型，可反复重放。',
              style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5, height: 1.6),
            ),
            const SizedBox(height: 16),
            for (final act in list) ...[
              _ActCard(act: act),
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

class _ActCard extends ConsumerWidget {
  const _ActCard({required this.act});

  final DemoAct act;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: EchoColors.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(act.id.replaceAll('act', ''),
                    style: const TextStyle(
                        color: EchoColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(act.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: EchoColors.text,
                          fontWeight: FontWeight.w700,
                        )),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(act.subtitle,
              style: const TextStyle(
                  color: EchoColors.textMuted, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 10),
          Row(
            children: [
              _Meta(icon: Icons.timeline, text: '${act.stepCount} 个动作'),
              const SizedBox(width: 14),
              _Meta(
                  icon: Icons.timer_outlined,
                  text: '${(act.durationMs / 1000).round()} 秒'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    // 第三幕的剧情就是"切到清醒模式"，所以这里先把模式切过去
                    final controller = ref.read(modeControllerProvider.notifier);
                    if (act.id == 'act3') {
                      controller.toClear();
                    } else {
                      controller.toEcho();
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${act.title}：逐帧播放在 M3 实现')),
                    );
                  },
                  child: const Text('播放'),
                ),
              ),
            ],
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

class DemoAct {
  const DemoAct({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.stepCount,
    required this.durationMs,
  });

  final String id;
  final String title;
  final String subtitle;
  final int stepCount;
  final int durationMs;
}

final _demoActsProvider = FutureProvider<List<DemoAct>>((ref) async {
  final acts = <DemoAct>[];
  for (final path in DemoPage._assets) {
    final raw = await rootBundle.loadString(path);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final steps = (json['steps'] as List<dynamic>? ?? const []).length;
    final preSteps = (json['preSteps'] as List<dynamic>? ?? const []).length;
    acts.add(DemoAct(
      id: json['id'] as String? ?? 'act',
      title: json['title'] as String? ?? '未命名',
      subtitle: json['subtitle'] as String? ?? '',
      stepCount: steps + preSteps,
      durationMs: (json['durationHintMs'] as num?)?.toInt() ?? 0,
    ));
  }
  return acts;
});
