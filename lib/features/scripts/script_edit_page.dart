import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/plan_script_repository.dart';
import '../../domain/models/ai_persona.dart';
import '../../domain/models/plan_script.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';

/// 脚本编辑器。
///
/// 一个脚本 = 名称 + 开局内容（可选） + 一串事件。
/// 事件的时间单位是**秒**：`30` 是发帖后第 30 秒，`30~90` 是这 60 秒里
/// 随机取一个时刻（写区间更像真实社区，不会像秒表一样齐）。
class ScriptEditPage extends ConsumerStatefulWidget {
  const ScriptEditPage({super.key, required this.scriptId});

  final String scriptId;

  @override
  ConsumerState<ScriptEditPage> createState() => _ScriptEditPageState();
}

class _ScriptEditPageState extends ConsumerState<ScriptEditPage> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _contentCtrl = TextEditingController();

  PlanScript? _script;
  List<AiPersona> _personas = const [];
  List<PlanStep> _steps = [];
  String? _topic;
  bool _loading = true;
  bool _saving = false;

  static const List<String> _topics = ['日常', '随手拍', '学习', '运动', '深夜', '吐槽'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final script = await ref
        .read(planScriptRepositoryProvider)
        .findById(widget.scriptId);
    final personas = await ref.read(personaRepositoryProvider).loadAll();
    if (!mounted) return;
    setState(() {
      _script = script;
      _personas = personas;
      _nameCtrl.text = script?.name ?? '';
      _contentCtrl.text = script?.postContent ?? '';
      _topic = script?.topicName;
      _steps = List.of(script?.steps ?? const <PlanStep>[]);
      _loading = false;
    });
  }

  int _byAt(PlanStep a, PlanStep b) =>
      (a.rangeMs?.$1 ?? 0).compareTo(b.rangeMs?.$1 ?? 0);

  Future<void> _addStep() async {
    final step = await showModalBottomSheet<PlanStep>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EchoColors.surface,
      builder: (_) => _StepEditor(personas: _personas),
    );
    if (step == null) return;
    setState(() => _steps = [..._steps, step]..sort(_byAt));
  }

  Future<void> _editStep(int index) async {
    final step = await showModalBottomSheet<PlanStep>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EchoColors.surface,
      builder: (_) => _StepEditor(personas: _personas, initial: _steps[index]),
    );
    if (step == null) return;
    setState(() {
      _steps = [..._steps]..[index] = step;
      _steps.sort(_byAt);
    });
  }

  Future<void> _save() async {
    final script = _script;
    if (script == null) return;

    setState(() => _saving = true);
    await ref
        .read(planScriptRepositoryProvider)
        .save(
          script.copyWith(
            name: _nameCtrl.text.trim().isEmpty
                ? '未命名脚本'
                : _nameCtrl.text.trim(),
            postContent: _contentCtrl.text,
            topicName: _topic,
            clearTopic: _topic == null,
            steps: _steps,
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: EchoColors.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isBuiltIn = _script?.isBuiltIn ?? false;

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          isBuiltIn ? '编辑内置脚本' : '编辑脚本',
          style: TextStyle(color: EchoColors.text, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving ? '保存中' : '保存',
              style: TextStyle(color: EchoColors.primary),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const SafeArea(child: AiDisclaimerBar()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          const _Label('脚本名称'),
          TextField(
            controller: _nameCtrl,
            style: TextStyle(color: EchoColors.text, fontSize: 14),
            decoration: const InputDecoration(hintText: '给它起个名字'),
          ),
          const SizedBox(height: 20),
          const _Label('开局内容（可选，选脚本时会填进发布页）'),
          TextField(
            controller: _contentCtrl,
            maxLines: 4,
            minLines: 3,
            style: TextStyle(color: EchoColors.text, height: 1.6),
            decoration: const InputDecoration(hintText: '帖子正文…'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final topic in _topics)
                _TopicChip(
                  label: '#$topic',
                  selected: _topic == topic,
                  onTap: () =>
                      setState(() => _topic = _topic == topic ? null : topic),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const _Label('事件'),
              const SizedBox(width: 8),
              Text(
                '${_steps.length} 条',
                style: TextStyle(color: EchoColors.textFaint, fontSize: 12),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addStep,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加事件', style: TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(
                  foregroundColor: EchoColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_steps.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                '还没有事件。加一条"第 5 秒，谁说了什么"，脚本才会动起来。',
                style: TextStyle(
                  color: EchoColors.textMuted,
                  fontSize: 12.5,
                  height: 1.7,
                ),
              ),
            )
          else
            for (var i = 0; i < _steps.length; i++)
              _StepTile(
                step: _steps[i],
                personas: _personas,
                onTap: () => _editStep(i),
                onDelete: () =>
                    setState(() => _steps = [..._steps]..removeAt(i)),
              ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: EchoColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: EchoColors.divider),
            ),
            child: Text(
              '时间的单位是秒。填 30 表示发帖后第 30 秒；填 30~90 表示这 60 秒里随机一个时刻。',
              style: TextStyle(
                color: EchoColors.textFaint,
                fontSize: 11.5,
                height: 1.7,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: EchoColors.textFaint,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({
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
          ),
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.personas,
    required this.onTap,
    required this.onDelete,
  });

  final PlanStep step;
  final List<AiPersona> personas;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: EchoColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: step.isValid ? EchoColors.divider : EchoColors.like,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                '${step.at}s',
                style: TextStyle(
                  color: EchoColors.primary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    PlanStepType.label(step.type),
                    style: TextStyle(color: EchoColors.text, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _summary(step, personas),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 15, color: EchoColors.textFaint),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  static String _summary(PlanStep step, List<AiPersona> personas) {
    switch (step.type) {
      case PlanStepType.comment:
        final name = personas
            .where((p) => p.id == step.personaId)
            .map((p) => p.name)
            .firstOrNull;
        final voice = step.mediaType == 'voice' ? '语音 · ' : '';
        return '$voice${name ?? step.personaId ?? '未指定'}：${step.content ?? ''}';
      case PlanStepType.likeBurst:
        return '+${step.delta ?? 0} 个赞';
      case PlanStepType.stats:
        return '赞 ${step.likes ?? '-'} · 评论 ${step.comments ?? '-'}';
      case PlanStepType.analysis:
        return '展示五项客观分析';
      default:
        return '';
    }
  }
}

/// 单条事件的编辑器。
class _StepEditor extends StatefulWidget {
  const _StepEditor({required this.personas, this.initial});

  final List<AiPersona> personas;
  final PlanStep? initial;

  @override
  State<_StepEditor> createState() => _StepEditorState();
}

class _StepEditorState extends State<_StepEditor> {
  late String _type;
  late String? _personaId;
  late bool _voice;

  late final TextEditingController _atCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _deltaCtrl;
  late final TextEditingController _likesCtrl;
  late final TextEditingController _commentsCtrl;
  late final TextEditingController _imageCtrl;
  late final TextEditingController _emotionCtrl;
  late final TextEditingController _logicCtrl;
  late final TextEditingController _factCtrl;
  late final TextEditingController _suggestCtrl;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _type = initial?.type ?? PlanStepType.comment;
    _personaId =
        initial?.personaId ??
        (widget.personas.isEmpty ? null : widget.personas.first.id);
    _voice = initial?.mediaType == 'voice';

    _atCtrl = TextEditingController(text: initial?.at ?? '5');
    _contentCtrl = TextEditingController(text: initial?.content ?? '');
    _deltaCtrl = TextEditingController(text: '${initial?.delta ?? 10}');
    _likesCtrl = TextEditingController(text: '${initial?.likes ?? 0}');
    _commentsCtrl = TextEditingController(text: '${initial?.comments ?? 0}');
    _imageCtrl = TextEditingController(
      text: initial?.analysis?.imageDescription ?? '',
    );
    _emotionCtrl = TextEditingController(
      text: initial?.analysis?.emotionAnalysis ?? '',
    );
    _logicCtrl = TextEditingController(
      text: initial?.analysis?.logicAnalysis ?? '',
    );
    _factCtrl = TextEditingController(text: initial?.analysis?.factCheck ?? '');
    _suggestCtrl = TextEditingController(
      text: initial?.analysis?.suggestions ?? '',
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _atCtrl,
      _contentCtrl,
      _deltaCtrl,
      _likesCtrl,
      _commentsCtrl,
      _imageCtrl,
      _emotionCtrl,
      _logicCtrl,
      _factCtrl,
      _suggestCtrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final step = _build();
    if (step == null) return;
    Navigator.of(context).pop(step);
  }

  PlanStep? _build() {
    final at = _atCtrl.text.trim();
    final probe = PlanStep(at: at, type: _type);
    if (!probe.isValid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('时间要写成 30 或 30~90 这样的秒数')));
      return null;
    }

    if (_type == PlanStepType.comment && (_personaId == null)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先选一个来评论的住民')));
      return null;
    }

    return PlanStep(
      at: at,
      type: _type,
      personaId: _type == PlanStepType.comment ? _personaId : null,
      mediaType: _type == PlanStepType.comment && _voice ? 'voice' : 'text',
      content: _type == PlanStepType.comment ? _contentCtrl.text.trim() : null,
      transcript: _type == PlanStepType.comment && _voice
          ? _contentCtrl.text.trim()
          : null,
      delta: _type == PlanStepType.likeBurst
          ? int.tryParse(_deltaCtrl.text) ?? 0
          : null,
      likes: _type == PlanStepType.stats ? int.tryParse(_likesCtrl.text) : null,
      comments: _type == PlanStepType.stats
          ? int.tryParse(_commentsCtrl.text)
          : null,
      analysis: _type == PlanStepType.analysis
          ? PlanAnalysis(
              imageDescription: _emptyToNull(_imageCtrl.text),
              emotionAnalysis: _emptyToNull(_emotionCtrl.text),
              logicAnalysis: _emptyToNull(_logicCtrl.text),
              factCheck: _emptyToNull(_factCtrl.text),
              suggestions: _emptyToNull(_suggestCtrl.text),
            )
          : null,
    );
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.initial == null ? '添加事件' : '编辑事件',
                    style: TextStyle(
                      color: EchoColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _submit,
                    style: TextButton.styleFrom(
                      foregroundColor: EchoColors.primary,
                    ),
                    child: const Text('确定'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const _FieldLabel('类型'),
              _Dropdown<String>(
                value: _type,
                items: [
                  for (final type in PlanStepType.all)
                    DropdownMenuItem(
                      value: type,
                      child: Text(PlanStepType.label(type)),
                    ),
                ],
                onChanged: (value) => setState(() => _type = value ?? _type),
              ),
              const SizedBox(height: 14),
              const _FieldLabel('时间（秒）'),
              TextField(
                controller: _atCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: TextStyle(color: EchoColors.text, fontSize: 14),
                decoration: const InputDecoration(hintText: '30 或 30~90'),
              ),
              const SizedBox(height: 16),
              ..._typeFields(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _typeFields() {
    switch (_type) {
      case PlanStepType.comment:
        return [
          const _FieldLabel('谁来评论'),
          _Dropdown<String>(
            value: widget.personas.any((p) => p.id == _personaId)
                ? _personaId
                : null,
            items: [
              for (final persona in widget.personas)
                DropdownMenuItem(value: persona.id, child: Text(persona.name)),
            ],
            onChanged: (value) => setState(() => _personaId = value),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('评论内容'),
          TextField(
            controller: _contentCtrl,
            maxLines: 3,
            minLines: 2,
            style: TextStyle(color: EchoColors.text, height: 1.5),
            decoration: const InputDecoration(hintText: '它会说什么…'),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '语音条',
                style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
              ),
              Switch(
                value: _voice,
                onChanged: (value) => setState(() => _voice = value),
              ),
            ],
          ),
        ];

      case PlanStepType.likeBurst:
        return [
          const _FieldLabel('这一批多少个赞'),
          TextField(
            controller: _deltaCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(color: EchoColors.text, fontSize: 14),
            decoration: const InputDecoration(hintText: '10'),
          ),
        ];

      case PlanStepType.stats:
        return [
          const _FieldLabel('把计数直接设成'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _likesCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: EchoColors.text, fontSize: 14),
                  decoration: const InputDecoration(hintText: '赞'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _commentsCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: EchoColors.text, fontSize: 14),
                  decoration: const InputDecoration(hintText: '评论'),
                ),
              ),
            ],
          ),
        ];

      case PlanStepType.analysis:
        return [
          const _FieldLabel('五项客观分析（可留空）'),
          _AnalysisField(controller: _imageCtrl, hint: '图片客观描述'),
          _AnalysisField(controller: _emotionCtrl, hint: '文本情绪分析'),
          _AnalysisField(controller: _logicCtrl, hint: '逻辑结构分析'),
          _AnalysisField(controller: _factCtrl, hint: '事实核查提示'),
          _AnalysisField(controller: _suggestCtrl, hint: '改进建议'),
        ];

      default:
        return const [];
    }
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      dropdownColor: EchoColors.surfaceHigh,
      style: TextStyle(color: EchoColors.text, fontSize: 13.5),
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}

class _AnalysisField extends StatelessWidget {
  const _AnalysisField({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        maxLines: 2,
        minLines: 1,
        style: TextStyle(color: EchoColors.text, fontSize: 13, height: 1.5),
        decoration: InputDecoration(hintText: hint),
      ),
    );
  }
}
