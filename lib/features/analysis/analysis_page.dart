import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/clear_insight_repository.dart';
import '../../domain/models/clear_insight.dart';
import '../../domain/services/clear_insight_service.dart';
import '../../domain/services/mode_controller.dart';
import '../../domain/services/notification_service.dart';
import '../../domain/services/tts_service.dart';
import '../../domain/services/voice_playback.dart';

/// 客观分析页（v31 重做）。
///
/// 以前整页是预置文案：不管用户发了什么、做过什么，看到的都是同一段
/// “天空照”的分析。现在这里只读**本机记录算出来的快照**——
/// 发帖频率、互动构成、AI 占比、情绪走向、时间分布，每一项都能说清来源。
///
/// 分析不调用模型：清醒模式要的是“看清自己的记录”，
/// 让另一个人（模型）来评价你，只会把评价权又交出去一次。
class AnalysisPage extends ConsumerStatefulWidget {
  const AnalysisPage({super.key});

  @override
  ConsumerState<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends ConsumerState<AnalysisPage> {
  bool _generating = false;
  bool _speaking = false;

  Future<void> _generate() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final insight = await ref
          .read(clearInsightServiceProvider)
          .generate();
      if (!mounted) return;
      if (insight == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('这 7 天还没有可分析的记录。先写下一条，或做一件真实的小事。')),
        );
        return;
      }

      // 生成完成后发一条系统通知；点开直达这一页。
      // 复用现有通知通道，不新开一套。
      unawaited(
        ref
            .read(systemNotificationProvider)
            .show(
              key: 'clear_insight',
              title: '清醒分析已生成',
              body: insight.summary,
            ),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _speak(ClearInsight insight) async {
    final playback = ref.read(voicePlaybackProvider.notifier);
    if (ref.read(voicePlaybackProvider).playing) {
      await playback.stop();
      return;
    }
    if (_speaking) return;
    setState(() => _speaking = true);
    try {
      final clip = await ref
          .read(ttsServiceProvider)
          .speak(text: insight.toSpeechText(), personaId: 'clear_analysis');
      if (!mounted) return;
      if (clip == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('这台设备暂时合成不了语音，文字版就在上面。')),
        );
        return;
      }
      await ref.read(voicePlaybackProvider.notifier).toggle(clip.ref);
    } catch (error) {
      // 精简版没下载语音模型时，异常里带着“去我的 → 下载资源”，原样告诉用户。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(modeControllerProvider);
    final async = ref.watch(latestClearInsightProvider);
    final playing = ref.watch(voicePlaybackProvider).playing;

    return Container(
      color: ClearColors.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            '客观分析',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: ClearColors.text, fontSize: 24),
          ),
          const SizedBox(height: 4),
          Text(
            '只根据你本机的记录算，不评价你。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: ClearColors.textMuted),
          ),
          const SizedBox(height: 16),
          if (mode.isEcho)
            const _NeedClearMode()
          else ...[
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _ErrorCard(message: '$error'),
              data: (insight) => insight == null
                  ? _EmptyInsight(onGenerate: _generate, busy: _generating)
                  : _InsightView(
                      insight: insight,
                      generating: _generating,
                      speaking: _speaking,
                      playing: playing,
                      onGenerate: _generate,
                      onSpeak: () => _speak(insight),
                    ),
            ),
            const SizedBox(height: 14),
            _EntryCard(
              icon: Icons.compare_arrows,
              title: '数字关系',
              subtitle: '线上投入与线下做过的事，并排看',
              onTap: () => context.push(RoutePaths.reflection),
            ),
            const SizedBox(height: 10),
            _EntryCard(
              icon: Icons.photo_library_outlined,
              title: '真实生活相册',
              subtitle: '只收你自己选的、真实拍下的照片',
              onTap: () => context.push(RoutePaths.album),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: ClearColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '本页数据来自本机真实记录，不含 AI 模拟反馈。\n'
                '分析不调用模型，也不会上传任何内容。',
                style: TextStyle(
                  color: ClearColors.textMuted,
                  fontSize: 11.5,
                  height: 1.7,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                AppTexts.permanentNotice,
                textAlign: TextAlign.center,
                style: TextStyle(color: ClearColors.textFaint, fontSize: 10.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightView extends StatelessWidget {
  const _InsightView({
    required this.insight,
    required this.generating,
    required this.speaking,
    required this.playing,
    required this.onGenerate,
    required this.onSpeak,
  });

  final ClearInsight insight;
  final bool generating;
  final bool speaking;
  final bool playing;
  final Future<void> Function() onGenerate;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: ClearColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ClearColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.summarize_outlined, size: 16, color: ClearColors.primary),
                  const SizedBox(width: 7),
                  Text(
                    '这 ${ClearInsightService.days} 天',
                    style: TextStyle(
                      color: ClearColors.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    RelativeTime.format(insight.generatedAt),
                    style: TextStyle(color: ClearColors.textFaint, fontSize: 10.5),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                insight.summary,
                style: TextStyle(
                  color: ClearColors.text,
                  fontSize: 14,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: generating ? null : onGenerate,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(generating ? '生成中…' : '重新生成'),
                  ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    onPressed: onSpeak,
                    icon: Icon(
                      playing ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                      size: 17,
                    ),
                    label: Text(
                      speaking
                          ? '合成中…'
                          : (playing ? '停止朗读' : '朗读结论'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final metric in insight.metrics) _MetricCard(metric: metric),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final ClearInsightMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ClearColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ClearColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.label,
            style: TextStyle(
              color: ClearColors.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            metric.value,
            style: TextStyle(
              color: ClearColors.text,
              fontSize: 14.5,
              height: 1.6,
            ),
          ),
          if (metric.detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              metric.detail,
              style: TextStyle(
                color: ClearColors.textFaint,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyInsight extends StatelessWidget {
  const _EmptyInsight({required this.onGenerate, required this.busy});

  final Future<void> Function() onGenerate;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ClearColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ClearColors.divider),
      ),
      child: Column(
        children: [
          Icon(
            Icons.insights_outlined,
            size: 26,
            color: ClearColors.textFaint,
          ),
          const SizedBox(height: 10),
          Text(
            '还没有生成过分析。',
            style: TextStyle(color: ClearColors.text, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            '先写下一条记录，或者做一件真实的小事，再回来生成。\n'
            '这里不会用预置样例凑出一份“看起来像分析”的东西。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ClearColors.textMuted,
              fontSize: 12,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: busy ? null : onGenerate,
            child: Text(busy ? '生成中…' : '生成本机分析'),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ClearColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ClearColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: ClearColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: ClearColors.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: ClearColors.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: ClearColors.textFaint, size: 20),
          ],
        ),
      ),
    );
  }
}

class _NeedClearMode extends StatelessWidget {
  const _NeedClearMode();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Text(
        '客观分析属于清醒模式。\n切到清醒模式后，AI 互动会停止，这里只留下对你本机记录的统计。',
        style: TextStyle(
          color: EchoColors.textMuted,
          height: 1.7,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ClearColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ClearColors.divider),
      ),
      child: Text(
        '这次没读出来：$message',
        style: TextStyle(color: ClearColors.textMuted, fontSize: 12.5),
      ),
    );
  }
}
