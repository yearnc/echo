import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_texts.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/services/mode_controller.dart';

/// 客观分析结果页（规划书 §6.8）。
///
/// 清醒模式的全部产出都在这里：**只有描述、情绪、逻辑、事实、建议五件事**，
/// 没有分数、没有排名、没有"你被多少人看过"。
/// 阶段 A 用预置结果（对应演示模式第三幕），阶段 B 接真实模型。
class AnalysisPage extends ConsumerWidget {
  const AnalysisPage({super.key});

  static const _PresetAnalysis _preset = _PresetAnalysis(
    imageDescription:
        '画面为中景天空，云层呈絮状分布，左侧偏暖色、右侧偏冷色；光来自画面右下方，属于逆光，主体无遮挡。画面内没有人物或建筑。',
    emotionAnalysis: '文案为平淡陈述，含不确定语气（"好像有点"），情绪强度低，偏中性；没有明显的求助或负面表达。',
    logicAnalysis: '陈述句 + 主观评价结构完整，未发现逻辑跳跃。',
    factCheck: '"下课""操场边"为个人经历描述，无法也无需外部核查。',
    suggestions: '如果想要更准确的记录，可以补上拍摄时间与地点；若希望练习表达，可尝试用三个具体名词替代表容词。',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeControllerProvider);

    return Container(
      color: ClearColors.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '客观分析',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: ClearColors.text, fontSize: 24),
          ),
          const SizedBox(height: 4),
          Text(
            '系统只描述它看到的东西，不评价你。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: ClearColors.textMuted),
          ),
          const SizedBox(height: 16),
          if (mode.isEcho) const _NeedClearMode(),
          if (mode.isClear) ...[
            const _AnalyzedPostPreview(),
            const SizedBox(height: 16),
            _AnalysisSection(
              index: 1,
              title: '图片客观描述',
              icon: Icons.image_outlined,
              content: _preset.imageDescription,
            ),
            _AnalysisSection(
              index: 2,
              title: '文本情绪分析',
              icon: Icons.mood_outlined,
              content: _preset.emotionAnalysis,
            ),
            _AnalysisSection(
              index: 3,
              title: '逻辑结构分析',
              icon: Icons.account_tree_outlined,
              content: _preset.logicAnalysis,
            ),
            _AnalysisSection(
              index: 4,
              title: '事实核查提示',
              icon: Icons.fact_check_outlined,
              content: _preset.factCheck,
            ),
            _AnalysisSection(
              index: 5,
              title: '改进建议',
              icon: Icons.lightbulb_outline,
              content: _preset.suggestions,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: ClearColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ClearColors.divider),
              ),
              child: Text(
                '阶段 A 展示的是预置分析结果；接入你自己的模型后，这里会由真实 API 生成。',
                style: TextStyle(
                  color: ClearColors.textMuted,
                  fontSize: 11.5,
                  height: 1.6,
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
        '客观分析属于清醒模式。\n切到清醒模式后，AI 互动会停止，这里只留下对内容的描述与分析。',
        style: TextStyle(
          color: EchoColors.textMuted,
          height: 1.7,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _AnalyzedPostPreview extends StatelessWidget {
  const _AnalyzedPostPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
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
            '被分析的内容',
            style: TextStyle(
              color: ClearColors.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '今天下课后在操场边随手拍的天空，好像有点好看。',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: ClearColors.text),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.visibility_off_outlined,
                size: 13,
                color: ClearColors.textFaint,
              ),
              SizedBox(width: 5),
              Text(
                '点赞数与评论数已隐藏',
                style: TextStyle(color: ClearColors.textFaint, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnalysisSection extends StatelessWidget {
  const _AnalysisSection({
    required this.index,
    required this.title,
    required this.icon,
    required this.content,
  });

  final int index;
  final String title;
  final IconData icon;
  final String content;

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
          Row(
            children: [
              Icon(icon, size: 16, color: ClearColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: ClearColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$index',
                style: TextStyle(
                  color: ClearColors.divider,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            content,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: ClearColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _PresetAnalysis {
  const _PresetAnalysis({
    required this.imageDescription,
    required this.emotionAnalysis,
    required this.logicAnalysis,
    required this.factCheck,
    required this.suggestions,
  });

  final String imageDescription;
  final String emotionAnalysis;
  final String logicAnalysis;
  final String factCheck;
  final String suggestions;
}
