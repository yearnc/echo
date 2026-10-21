import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/model_config_repository.dart';
import '../../domain/models/model_config.dart';
import '../../domain/services/model_call_common.dart';
import '../../domain/services/model_gateway.dart';
import '../../domain/services/model_probe.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';

/// 单条模型配置的编辑页。
///
/// 保存之前可以先"测试连接"——真发一句过去，对方回了才算通。
/// 这样用户不会带着一个错的地址去用分析功能，然后以为是 APP 坏了。
class ModelEditPage extends ConsumerStatefulWidget {
  const ModelEditPage({super.key, this.configId});

  /// 为空表示"新建草稿"——这时候还没落库，保存时才真正创建。
  final String? configId;

  @override
  ConsumerState<ModelEditPage> createState() => _ModelEditPageState();
}

class _ModelEditPageState extends ConsumerState<ModelEditPage> {
  final TextEditingController _labelCtrl = TextEditingController();
  final TextEditingController _baseUrlCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();
  final TextEditingController _keyCtrl = TextEditingController();

  ModelConfig? _config;
  String _provider = 'custom';
  ModelKind _kind = ModelKind.chat;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _obscureKey = true;
  bool _hasSavedKey = false;
  bool _enabled = false;
  bool _supportsVision = false;
  ProbeResult? _probe;

  /// 进页面时的表单快照。当前值和它不一致，就说明有没保存的改动。
  /// 用快照比较而不是"碰一下就置脏"，是为了不误报——
  /// 新建时表单里本来就填着预设，那不是用户的改动。
  String _initialSnapshot = '';

  String get _snapshot => [
    _provider,
    _labelCtrl.text.trim(),
    _baseUrlCtrl.text.trim(),
    _modelCtrl.text.trim(),
    _enabled ? '1' : '0',
    _supportsVision ? '1' : '0',
  ].join('|');

  bool get _dirty =>
      !_loading &&
      (_snapshot != _initialSnapshot || _keyCtrl.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.configId;

    // 新建草稿：拿第一个预设起个手，但**不写库**——
    // 只有保存过的东西才配出现在列表里。
    if (id == null) {
      final preset = ModelConfig.presetsOf(_kind).first;
      setState(() {
        _provider = preset.id;
        _labelCtrl.text = preset.label;
        _baseUrlCtrl.text = preset.baseUrl;
        _modelCtrl.text = preset.model;
        _loading = false;
        _initialSnapshot = _snapshot;
      });
      return;
    }

    final repo = ref.read(modelConfigRepositoryProvider);
    final config = await repo.findById(id);
    final hasKey = config == null ? false : await repo.hasKey(config.id);
    if (!mounted) return;

    setState(() {
      _config = config;
      _provider = config?.provider ?? 'custom';
      _kind = config?.kind ?? ModelKind.chat;
      _labelCtrl.text = config?.label ?? '';
      _baseUrlCtrl.text = config?.baseUrl ?? '';
      _modelCtrl.text = config?.model ?? '';
      _enabled = config?.enabled ?? false;
      _supportsVision = config?.supportsVision ?? false;
      _hasSavedKey = hasKey;
      _loading = false;
      _initialSnapshot = _snapshot;
    });
  }

  void _applyPreset(ModelPreset preset) {
    setState(() {
      _provider = preset.id;
      _labelCtrl.text = preset.label;
      _baseUrlCtrl.text = preset.baseUrl;
      // 预设已经按用途分过组了（对话 / 文生图 / 语音合成），
      // 点哪一条就填哪一条的型号，不用用户再记名字。
      _modelCtrl.text = preset.model;
      _probe = null;
    });
  }

  /// 换用途。型号要一起清掉：对话的型号放到文生图或语音合成上一定跑不通。
  void _switchKind(ModelKind kind) {
    if (_kind == kind) return;
    setState(() {
      _kind = kind;
      _modelCtrl.text = '';
      _probe = null;
    });
  }

  Future<void> _test() async {
    final baseUrl = _baseUrlCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    final apiKey = _keyCtrl.text.trim();

    if (baseUrl.isEmpty || model.isEmpty) {
      _snack('先把地址和模型名填上');
      return;
    }
    if (apiKey.isEmpty && !_hasSavedKey) {
      _snack('先把 API Key 填上');
      return;
    }

    // 新建草稿时还没有存过密钥，走到这里的必然是"填了新的"或"库里已有"
    final key = apiKey.isNotEmpty
        ? apiKey
        : (await ref
                  .read(modelConfigRepositoryProvider)
                  .readKey(_config?.id ?? '') ??
              '');

    setState(() {
      _testing = true;
      _probe = null;
    });

    // 三种用途各打各的接口：对话 /chat/completions、出图 /images/generations、
    // 语音 /audio/speech。拿对话接口去验后两者，只会得到一句误导人的"地址不对"。
    final probe = ref.read(modelProbeProvider);
    final result = switch (_kind) {
      ModelKind.image => await probe.testImage(
        baseUrl: baseUrl,
        apiKey: key,
        model: model,
      ),
      ModelKind.tts => await probe.testTts(
        baseUrl: baseUrl,
        apiKey: key,
        model: model,
      ),
      // 图片理解也是对话接口；用一句文本验连通性，真正的看图在运行时。
      ModelKind.vision => await probe.test(
        baseUrl: baseUrl,
        apiKey: key,
        model: model,
      ),
      ModelKind.chat => await probe.test(
        baseUrl: baseUrl,
        apiKey: key,
        model: model,
      ),
    };

    if (!mounted) return;
    setState(() {
      _testing = false;
      _probe = result;
    });
  }

  /// 从剪贴板把密钥贴进来。
  ///
  /// 手机上「长按粘贴」在密码框里常常用不了：不少 ROM 会给密码输入框
  /// 拉起自家的安全键盘，而安全键盘不给粘贴。所以这里直接读剪贴板写进框里，
  /// 绕开输入法，也就不受它的限制。
  Future<void> _pasteKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (text.isEmpty) {
      _snack('剪贴板里没有文字');
      return;
    }

    setState(() {
      _keyCtrl.text = text;
      // 贴完顺手露出来，让用户能核对一眼再保存
      _obscureKey = false;
      _probe = null;
    });
  }

  Future<void> _save() async {
    final baseUrl = _baseUrlCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    if (baseUrl.isEmpty || model.isEmpty) {
      _snack('地址和模型名不能空着');
      return;
    }
    // 存之前先挡下地址本身的问题：漏掉 https:// 这种错，要等到调用时才
    // 变成一句"连不上这个地址"，用户会跑去查网络——而错在地址栏里
    final problem = describeBaseUrlProblem(baseUrl);
    if (problem != null) {
      _snack(problem);
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(modelConfigRepositoryProvider);

    // 新建草稿：到这一步才真正落库
    final config =
        _config ??
        ModelConfig(
          id: ModelConfigRepository.newId(),
          provider: _provider,
          label: '',
          baseUrl: baseUrl,
          model: model,
        );

    final saved = config.copyWith(
      provider: _provider,
      label: _labelCtrl.text.trim().isEmpty
          ? ModelConfig.presetOf(_provider, kind: _kind).label
          : _labelCtrl.text.trim(),
      baseUrl: baseUrl,
      model: model,
      kind: _kind,
      supportsVision: _supportsVision,
    );

    await repo.save(saved);

    final key = _keyCtrl.text.trim();
    if (key.isNotEmpty) {
      await repo.writeKey(saved.id, key);
    }

    if (_enabled) {
      await repo.setEnabled(saved.id);
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _config = saved;
      _hasSavedKey = _hasSavedKey || key.isNotEmpty;
      _keyCtrl.clear();
      _initialSnapshot = _snapshot;
    });
    ref.invalidate(modelHasKeyProvider(saved.id));
    // 设置页的"云端语音可用吗"也跟着这条配置走，保存完让它重查一次
    ref.invalidate(cloudTtsConfigProvider);
    _snack('已保存');
    _leave();
  }

  /// 走人。先把快照对齐（这样 canPop 就放行了），下一帧再真的 pop。
  void _leave() {
    setState(() => _initialSnapshot = _snapshot);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.pop();
    });
  }

  Future<void> _handlePop() async {
    final choice = await _confirmDiscard();
    if (!mounted) return;

    switch (choice) {
      case _LeaveChoice.save:
        await _save();
      case _LeaveChoice.discard:
        _leave();
      case _LeaveChoice.stay:
      case null:
        break;
    }
  }

  Future<_LeaveChoice?> _confirmDiscard() {
    return showDialog<_LeaveChoice>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EchoColors.surface,
        title: Text(
          '还有改动没保存',
          style: TextStyle(color: EchoColors.text, fontSize: 15),
        ),
        content: Text(
          '现在离开的话，刚才改的就不算数了。',
          style: TextStyle(
            color: EchoColors.textMuted,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_LeaveChoice.stay),
            child: Text('继续编辑', style: TextStyle(color: EchoColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_LeaveChoice.discard),
            child: Text('不保存', style: TextStyle(color: EchoColors.like)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_LeaveChoice.save),
            child: Text('保存', style: TextStyle(color: EchoColors.primary)),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDelete() async {
    final config = _config;
    if (config == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EchoColors.surface,
        title: Text(
          '删除配置',
          style: TextStyle(color: EchoColors.text, fontSize: 15),
        ),
        content: Text(
          '「${config.label}」将被删除，存在系统钥匙串里的密钥也会一起清掉。',
          style: TextStyle(
            color: EchoColors.textMuted,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: TextStyle(color: EchoColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('删除', style: TextStyle(color: EchoColors.like)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(modelConfigRepositoryProvider).delete(config.id);
    ref.invalidate(cloudTtsConfigProvider);
    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: EchoColors.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // 有没保存的改动时拦住返回，问一句再走
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handlePop();
      },
      child: Scaffold(
        backgroundColor: EchoColors.bg,
        appBar: AppBar(
          backgroundColor: EchoColors.surface,
          iconTheme: IconThemeData(color: EchoColors.text),
          title: Text(
            '模型配置',
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
            const _Label('用途'),
            Wrap(
              spacing: 8,
              children: [
                for (final kind in ModelKind.values)
                  _PresetChip(
                    label: kind.label,
                    selected: _kind == kind,
                    onTap: () => _switchKind(kind),
                  ),
              ],
            ),
            if (_kind != ModelKind.chat) ...[
              const SizedBox(height: 8),
              Text(
                switch (_kind) {
                  ModelKind.image => '兼容 OpenAI 的 /images/generations 接口。',
                  ModelKind.tts => '兼容 OpenAI 的 /audio/speech 接口，音色由服务商提供。',
                  ModelKind.vision =>
                    '兼容 OpenAI 的 image_url 入参；用作帖子图片的“先看懂”。',
                  ModelKind.chat => '',
                },
                style: TextStyle(
                  color: EchoColors.textFaint,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
            ],
            if (_kind == ModelKind.chat)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('这个模型能看图'),
                subtitle: const Text('开启后，私信里你发的图片会原样带进对话'),
                value: _supportsVision,
                onChanged: (value) => setState(() => _supportsVision = value),
              ),
            const SizedBox(height: 20),
            const _Label('服务商'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in ModelConfig.presetsOf(_kind))
                  _PresetChip(
                    label: preset.label,
                    selected: _provider == preset.id,
                    onTap: () => _applyPreset(preset),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _Label('名称'),
            TextField(
              controller: _labelCtrl,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: EchoColors.text, fontSize: 14),
              decoration: const InputDecoration(hintText: '给它起个好认的名字'),
            ),
            const SizedBox(height: 18),
            const _Label('Base URL'),
            TextField(
              controller: _baseUrlCtrl,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: EchoColors.text, fontSize: 13.5),
              decoration: const InputDecoration(hintText: 'https://…/v1'),
            ),
            const SizedBox(height: 18),
            const _Label('模型名'),
            TextField(
              controller: _modelCtrl,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: EchoColors.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: switch (_kind) {
                  ModelKind.image => 'gpt-image-1.5',
                  ModelKind.tts => 'FunAudioLLM/CosyVoice2-0.5B',
                  ModelKind.vision => 'qwen-vl-max',
                  ModelKind.chat => 'deepseek-flash',
                },
              ),
            ),
            if (ModelConfig.presetOf(_provider, kind: _kind)
                .altModels
                .isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final alt
                      in ModelConfig.presetOf(_provider, kind: _kind).altModels)
                    _PresetChip(
                      label: alt,
                      selected: _modelCtrl.text.trim() == alt,
                      onTap: () => setState(() {
                        _modelCtrl.text = alt;
                        _probe = null;
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            _Label(_hasSavedKey ? 'API Key（已存，留空则不修改）' : 'API Key'),
            TextField(
              controller: _keyCtrl,
              onChanged: (_) => setState(() {}),
              obscureText: _obscureKey,
              style: TextStyle(color: EchoColors.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: _hasSavedKey ? '••••••••' : '服务商控制台里申请的那串密钥',
                // 两个按钮：左边从剪贴板贴，右边显示/隐藏。
                // 「贴」那个是为手机准备的——密码框会拉起厂商的安全键盘，
                // 安全键盘不给粘贴，手打一串密钥太容易错一个字符。
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.content_paste, size: 18),
                      color: EchoColors.textFaint,
                      tooltip: '从剪贴板粘贴',
                      onPressed: _pasteKey,
                    ),
                    IconButton(
                      icon: Icon(
                        _obscureKey ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                        color: EchoColors.textFaint,
                      ),
                      onPressed: () => setState(() => _obscureKey = !_obscureKey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '密钥只保存在本机钥匙串。',
              style: TextStyle(
                color: EchoColors.textFaint,
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            // 两种用途都能测，只是打的是各自的接口：对话发一句"你好"，
            // 出图真让它画一张。之前只给对话做，是因为拿对话接口去验图片模型
            // 只会得到一句"地址不对"——那比不测更糟。
            OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt, size: 16),
              label: Text(
                _testing
                    ? '正在测…'
                    : switch (_kind) {
                        ModelKind.image => '测试出图',
                        ModelKind.tts => '测试合成',
                        ModelKind.vision => '测试连接',
                        ModelKind.chat => '测试连接',
                      },
              ),
            ),
            if (_probe != null) ...[
              const SizedBox(height: 12),
              _ProbeCard(result: _probe!),
            ],
            const SizedBox(height: 20),
            // 同发布页的策划模式卡片：ListTile 的水波纹画在最近的 Material 上，
            // 外面套一层有背景色的 DecoratedBox 会让它永远不可见（并被断言拦下）
            Material(
              color: EchoColors.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: EchoColors.divider),
              ),
              child: SwitchListTile(
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
                dense: true,
                title: Text(
                  '启用这条配置',
                  style: TextStyle(color: EchoColors.text, fontSize: 13.5),
                ),
                subtitle: Text(
                  '同一时间只有一条配置生效',
                  style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _saving ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('删除这条配置'),
              style: TextButton.styleFrom(foregroundColor: EchoColors.like),
            ),
          ],
        ),
      ),
    );
  }
}

/// 离开时的选择：留下继续改 / 不要了 / 先保存。
enum _LeaveChoice { stay, discard, save }

class _ProbeCard extends StatelessWidget {
  const _ProbeCard({required this.result});

  final ProbeResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.ok ? EchoColors.success : EchoColors.like;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  result.message,
                  style: TextStyle(color: color, fontSize: 12.5, height: 1.5),
                ),
              ),
              if (result.elapsedMs > 0)
                Text(
                  '${result.elapsedMs} ms',
                  style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
                ),
            ],
          ),
          if (result.reply != null) ...[
            const SizedBox(height: 8),
            Text(
              '它说：${result.reply}',
              style: TextStyle(
                color: EchoColors.textMuted,
                fontSize: 12.5,
                height: 1.6,
              ),
            ),
          ],
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

class _PresetChip extends StatelessWidget {
  const _PresetChip({
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
