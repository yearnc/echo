import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/services/mode_controller.dart';

/// 发布页（规划书 §6.1）。
///
/// 阶段 A 只做发布本身：文字、图片、话题，以及回响模式下那组
/// "你能决定别人怎么回应你"的旋钮（回复频率 / 点赞量 / 拟人程度）。
/// 这组旋钮放在发布页而不是深层设置里，是刻意的——它让"我在安排反馈"这件事
/// 在每一次发帖时都被看见一次。
class ComposePage extends ConsumerStatefulWidget {
  const ComposePage({super.key});

  @override
  ConsumerState<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends ConsumerState<ComposePage> {
  final TextEditingController _controller = TextEditingController();
  String _topic = '日常';
  String _density = '中';
  String _likeLevel = '中';
  int _humanLevel = 3;
  final List<String> _attached = [];

  static const List<String> _topics = ['日常', '随手拍', '学习', '运动', '深夜', '吐槽'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(modeControllerProvider);
    final isEcho = mode.isEcho;

    return Container(
      color: isEcho ? EchoColors.bg : ClearColors.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            isEcho ? '发布' : '记录',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: isEcho ? EchoColors.text : ClearColors.text,
                  fontSize: 24,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            isEcho ? '说点什么，会有人回应你的。' : '写下一件今天真实发生的事。',
            style: TextStyle(
              color: isEcho ? EchoColors.textMuted : ClearColors.textMuted,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 7,
            minLines: 5,
            style: TextStyle(
              color: isEcho ? EchoColors.text : ClearColors.text,
              height: 1.6,
            ),
            decoration: InputDecoration(
              hintText: isEcho ? '今天想说什么…' : '今天真实发生的一件小事…',
              fillColor: isEcho ? EchoColors.surfaceHigh : ClearColors.surface,
            ),
          ),
          const SizedBox(height: 12),
          _AttachRow(
            attached: _attached,
            isEcho: isEcho,
            onPick: () => _pickImage(),
          ),
          const SizedBox(height: 18),
          if (isEcho) ...[
            const _SectionLabel('话题'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final topic in _topics)
                  _ChoiceChip(
                    label: '#$topic',
                    selected: _topic == topic,
                    onTap: () => setState(() => _topic = topic),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _SectionLabel('你希望它被怎么对待'),
            _SettingRow(
              label: '回复频率',
              value: _density,
              options: const ['低', '中', '高', '自动'],
              onChanged: (v) => setState(() => _density = v),
            ),
            _SettingRow(
              label: '点赞量',
              value: _likeLevel,
              options: const ['低', '中', '高', '自动'],
              onChanged: (v) => setState(() => _likeLevel = v),
            ),
            _SettingRow(
              label: '拟人程度',
              value: '$_humanLevel 档',
              options: const ['1', '2', '3', '4', '5'],
              onChanged: (v) =>
                  setState(() => _humanLevel = int.parse(v)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: EchoColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EchoColors.divider),
              ),
              child: const Text(
                '这些设置只影响 AI 生成内容的表现形式。反馈会在 0—48 小时内随机出现。',
                style: TextStyle(
                    color: EchoColors.textFaint, fontSize: 11.5, height: 1.6),
              ),
            ),
          ] else
            const _ClearModeNote(),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _publish,
              style: isEcho
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: ClearColors.primary,
                    ),
              child: Text(isEcho ? '发布' : '记录'),
            ),
          ),
        ],
      ),
    );
  }

  void _pickImage() {
    // 阶段 A：图片选择走 image_picker（真机/桌面各自弹原生选择器）。
    // 这里先只给出交互占位，M2 接上 picker 与私有目录拷贝。
    setState(() => _attached.add('待选择图片'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('图片选择会在下一个里程碑接上（需要真机或桌面选择器）')),
    );
  }

  void _publish() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先写点什么吧')));
      return;
    }
    _controller.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存（写入数据库在下一个里程碑）')),
    );
  }
}

class _AttachRow extends StatelessWidget {
  const _AttachRow({
    required this.attached,
    required this.isEcho,
    required this.onPick,
  });

  final List<String> attached;
  final bool isEcho;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final surface = isEcho ? EchoColors.surface : ClearColors.surface;
    final divider = isEcho ? EchoColors.divider : ClearColors.divider;
    final muted = isEcho ? EchoColors.textMuted : ClearColors.textMuted;

    return Row(
      children: [
        InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: divider),
            ),
            child: Icon(Icons.add_photo_alternate_outlined, color: muted, size: 22),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            attached.isEmpty ? '最多 9 张图' : '已附带 ${attached.length} 张（占位）',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(text,
          style: const TextStyle(
              color: EchoColors.textFaint,
              fontSize: 11.5,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? EchoColors.primary.withValues(alpha: 0.16)
              : EchoColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? EchoColors.primary.withValues(alpha: 0.5)
                : EchoColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: selected ? EchoColors.primary : EchoColors.textMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(label,
                style: const TextStyle(color: EchoColors.textMuted, fontSize: 13)),
          ),
          Expanded(
            child: Wrap(
              spacing: 7,
              children: [
                for (final option in options)
                  GestureDetector(
                    onTap: () => onChanged(option),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: value.startsWith(option)
                            ? EchoColors.primary.withValues(alpha: 0.18)
                            : EchoColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: value.startsWith(option)
                              ? EchoColors.primary.withValues(alpha: 0.5)
                              : EchoColors.divider,
                        ),
                      ),
                      child: Text(
                        option,
                        style: TextStyle(
                          fontSize: 12,
                          color: value.startsWith(option)
                              ? EchoColors.primary
                              : EchoColors.textMuted,
                        ),
                      ),
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

class _ClearModeNote extends StatelessWidget {
  const _ClearModeNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ClearColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ClearColors.divider),
      ),
      child: const Text(
        '清醒模式下不会生成任何虚拟反馈。如果想看看内容的客观分析，可以在发布后进入「分析」页。',
        style: TextStyle(color: ClearColors.textMuted, fontSize: 12, height: 1.6),
      ),
    );
  }
}
