import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../core/router/app_router.dart';
import '../../data/media/media_service.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/model_config_repository.dart';
import '../../data/repositories/resident_memory_repository.dart';
import '../../domain/models/custom_resident.dart';
import '../../domain/models/model_config.dart';
import '../../domain/models/resident_voice.dart';
import '../../domain/services/chat_transcript_import.dart';
import '../../domain/services/model_gateway.dart';
import '../../domain/services/resident_memory_import_service.dart';
import '../../domain/services/resident_voice_profile_service.dart';
import '../../domain/services/resident_wake_service.dart';
import '../shared_widgets/image_source_sheet.dart';
import '../shared_widgets/user_avatar.dart';
import 'chat_import_sheet.dart';

/// 固定住民的完整编辑页。
///
/// 参考酒馆角色卡的分层：基本 / 人设 / 说话 / 行为。
/// 头像从相册导入，不再从内置池里挑。
class CustomResidentEditorPage extends ConsumerStatefulWidget {
  const CustomResidentEditorPage({super.key, this.residentId});

  final String? residentId;

  @override
  ConsumerState<CustomResidentEditorPage> createState() =>
      _CustomResidentEditorPageState();
}

class _CustomResidentEditorPageState
    extends ConsumerState<CustomResidentEditorPage> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _description = TextEditingController();
  final _languageStyle = TextEditingController();
  final _tone = TextEditingController();
  final _exampleDialogue = TextEditingController();
  final _extraInstructions = TextEditingController();
  final _tags = TextEditingController();
  final _memoryLimit = TextEditingController(text: '400');
  final _voiceDescription = TextEditingController();
  final _voiceSampleText = TextEditingController();

  String _avatar = '';
  String _modelConfigId = '';
  bool _memory = true;
  bool _voiceEnabled = false;
  ResidentVoiceMode _voiceMode = ResidentVoiceMode.description;
  String _voiceSamplePath = '';
  String _voiceRef = '';
  String _originalVoiceDescription = '';
  ResidentVoiceMode _originalVoiceMode = ResidentVoiceMode.description;
  String? _voiceStatus;
  bool _voiceBusy = false;

  /// 新建住民时先读好、等保存后再写进记忆的对话。
  List<ImportedTurn> _pendingTurns = const [];
  bool _importBusy = false;
  String? _importStatus;

  bool _loading = false;
  bool _saving = false;
  DateTime? _createdAt;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final id = widget.residentId;
    if (id != null) {
      _loading = true;
      _load(id);
    }
  }

  Future<void> _load(String id) async {
    final resident = await ref
        .read(customResidentRepositoryProvider)
        .findById(id);
    if (!mounted) return;
    if (resident == null) {
      setState(() => _loading = false);
      return;
    }
    _name.text = resident.name;
    _bio.text = resident.bio;
    // 旧数据里性格/场景是分开的，编辑页统一并成一段人设。
    _description.text = [
      resident.description,
      resident.personality,
      resident.scenario,
    ].where((part) => part.trim().isNotEmpty).join('\n\n');
    _languageStyle.text = resident.languageStyle;
    _tone.text = resident.tone;
    _exampleDialogue.text = resident.exampleDialogue;
    _extraInstructions.text = resident.extraInstructions;
    _tags.text = resident.tags.join('，');
    _avatar = resident.avatarAsset;
    _modelConfigId = resident.modelConfigId;
    _memory = resident.memoryEnabled;
    _memoryLimit.text = resident.memoryLimit?.toString() ?? '';
    _voiceEnabled = resident.voiceEnabled;
    _voiceDescription.text = resident.voiceDescription;
    _voiceSamplePath = resident.voiceSamplePath;
    _voiceSampleText.text = resident.voiceSampleText;
    _voiceRef = resident.voiceRef;
    // 老数据里 OpenAI 的“文字描述”也记在 description 下，靠 voiceRef 区分：
    // cloud:... 说明当时走的是云端描述，不是本机五选一。
    _voiceMode =
        resident.voiceMode == ResidentVoiceMode.description &&
            resident.voiceRef.startsWith('cloud:')
        ? ResidentVoiceMode.cloudDescription
        : resident.voiceMode;
    _originalVoiceDescription = resident.voiceDescription;
    _originalVoiceMode = resident.voiceMode;
    _createdAt = resident.createdAt;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _bio,
      _description,
      _languageStyle,
      _tone,
      _exampleDialogue,
      _extraInstructions,
      _tags,
      _memoryLimit,
      _voiceDescription,
      _voiceSampleText,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await pickImageWithSource(context, ref);
    if (picked == null || !mounted) return;
    setState(() => _avatar = picked);
  }

  Future<void> _pickVoiceSample() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.audio);
      if (files.isEmpty) return;
      final picked = files.single;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) setState(() => _voiceStatus = '这个音频读不出来');
        return;
      }
      final rawExt = p.extension(picked.name);
      final oldSample = _voiceSamplePath;
      final savedRef = await ref
          .read(mediaServiceProvider)
          .saveVoiceSample(
            bytes,
            extension: rawExt.isEmpty ? '.mp3' : rawExt,
          );
      if (oldSample.isNotEmpty) {
        await ref.read(mediaServiceProvider).deleteByRef(oldSample);
      }
      if (!mounted) return;
      setState(() {
        _voiceSamplePath = savedRef;
        _voiceRef = '';
        _voiceStatus = _voiceMode.usesTranscript
            ? '参考音频已选好；填上里面说的那句话，再点“生成音色”'
            : '参考音频已选好；点“生成音色”试试，不行就换一种方式';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _voiceStatus = '选音频失败：$error');
    }
  }

  Future<void> _cloneVoice() async {
    if (_voiceBusy) return;
    if (!_voiceMode.usesSample) {
      setState(() => _voiceStatus = '这种方式不需要参考音频');
      return;
    }
    if (_voiceSamplePath.trim().isEmpty) {
      setState(() => _voiceStatus = '先上传一段参考音频');
      return;
    }
    final transcript = _voiceSampleText.text.trim();
    if (_voiceMode.usesTranscript && transcript.isEmpty) {
      setState(() => _voiceStatus = '要填上参考音频里说的那句话，克隆才对得准');
      return;
    }
    if (!_voiceMode.usesTranscript) {
      // 目前接入的云端服务注册时都要求逐字稿；本机 ZipVoice 也一样。
      setState(() => _voiceStatus = '当前语音服务还没有接入这种方式，换成“参考音频 + 转录文本”吧');
      return;
    }

    setState(() {
      _voiceBusy = true;
      _voiceStatus = '正在生成音色…';
    });
    try {
      final cloud = await ref.read(cloudTtsConfigProvider.future);
      final canCloudClone =
          cloud != null &&
          ref.read(residentVoiceProfileServiceProvider).supportsClone(cloud);

      if (!canCloudClone) {
        // 本机 ZipVoice：不需要注册，音频和逐字稿都在本地，
        // 保存后合成时直接读这两样。
        if (!_voiceSamplePath.toLowerCase().endsWith('.wav')) {
          throw StateError('本机克隆需要 wav 参考音频（mp3/m4a 先转成 wav）');
        }
        if (!mounted) return;
        setState(() {
          _voiceRef = 'local:zipvoice';
          _voiceStatus = '本机克隆已就绪；wav 参考音频和逐字稿会随住民保存在本机';
        });
        return;
      }

      final path = _voiceSamplePath.replaceFirst('file:', '');
      final bytes = await File(path).readAsBytes();
      final ext = p.extension(path).toLowerCase();
      final mime = switch (ext) {
        '.wav' => 'audio/wav',
        '.m4a' => 'audio/mp4',
        '.ogg' => 'audio/ogg',
        '.flac' => 'audio/flac',
        _ => 'audio/mpeg',
      };
      final refValue = await ref
          .read(residentVoiceProfileServiceProvider)
          .cloneFromSample(
            audio: bytes,
            text: transcript,
            customName: _name.text.trim(),
            mime: mime,
          );
      if (!mounted) return;
      setState(() {
        _voiceRef = refValue;
        _voiceStatus = '云端音色已生成，保存后生效';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _voiceStatus = '生成失败：$error');
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  /// 读一段旧聊天，交给这位住民整理成记忆。
  Future<void> _importChat() async {
    final turns = await showModalBottomSheet<List<ImportedTurn>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ChatImportSheet(),
    );
    if (turns == null || turns.isEmpty) return;

    final id = widget.residentId;
    if (id == null) {
      // 新建住民还没有 id：先把对话留着，保存后一起写。
      setState(() {
        _pendingTurns = turns;
        _importStatus = '已读取 ${turns.length} 段对话；点保存后会一起写进记忆';
      });
      return;
    }
    await _runImport(id, turns);
  }

  Future<void> _runImport(String residentId, List<ImportedTurn> turns) async {
    setState(() {
      _importBusy = true;
      _importStatus = '正在让 TA 整理记忆…';
    });
    try {
      final resident = await ref
          .read(customResidentRepositoryProvider)
          .findById(residentId);
      if (resident == null) {
        throw const MemoryImportException('住民还没保存好');
      }
      final count = await ref
          .read(residentMemoryImportServiceProvider)
          .import(resident: resident, turns: turns);
      if (!mounted) return;
      setState(
        () => _importStatus = count == 0
            ? '这段对话里没有值得长期记住的事'
            : '已写进 $count 条记忆',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _importStatus = '整理失败：$error');
    } finally {
      if (mounted) setState(() => _importBusy = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '给 TA 起个名字吧');
      return;
    }

    setState(() {
      _saving = true;
      _nameError = null;
    });

    final limitText = _memoryLimit.text.trim();
    final newLimit = limitText.isEmpty ? null : int.tryParse(limitText);

    // 调低上限：先把"会归档几条"说清楚，别让用户以为记忆被删了。
    final id = widget.residentId;
    if (id != null && newLimit != null) {
      final memories = ref.read(residentMemoryRepositoryProvider);
      final current = await memories.count(id);
      if (current > newLimit) {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('调低记忆上限？'),
            content: Text(
              '当前有 $current 条，将把 ${current - newLimit} 条较早的记忆移入归档。'
              '归档不会删除，之后可以在记忆页手动恢复。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('确认'),
              ),
            ],
          ),
        );
        if (ok != true) {
          if (mounted) setState(() => _saving = false);
          return;
        }
      }
    }

    var voiceRef = _voiceRef.trim();
    if (_voiceEnabled) {
      // 以当前模型能力为准：换过语音服务之后，老的方式可能已经不支持了。
      final modes = ref
          .read(residentVoiceProfileServiceProvider)
          .modesFor(await ref.read(cloudTtsConfigProvider.future));
      final mode = modes.contains(_voiceMode) ? _voiceMode : modes.first;
      _voiceMode = mode;
      final description = _voiceDescription.text.trim();
      switch (mode) {
        case ResidentVoiceMode.description:
          // 五选一：存 local:<sid>，不再根据描述散列。
          final sid = ResidentVoice.localSidOf(voiceRef) ??
              ResidentVoice.sidFor(
                widget.residentId ?? _name.text.trim(),
              );
          voiceRef = 'local:$sid';
        case ResidentVoiceMode.cloudDescription:
          final changed =
              description != _originalVoiceDescription.trim() ||
              _originalVoiceMode != ResidentVoiceMode.cloudDescription;
          if (voiceRef.isEmpty ||
              changed ||
              !voiceRef.startsWith('cloud:')) {
            voiceRef = await ref
                .read(residentVoiceProfileServiceProvider)
                .fromDescription(description);
          }
        case ResidentVoiceMode.referenceTranscript:
          if (voiceRef.isEmpty) {
            if (_voiceSamplePath.trim().isEmpty ||
                _voiceSampleText.text.trim().isEmpty) {
              if (mounted) {
                setState(() {
                  _saving = false;
                  _voiceStatus = '先上传参考音频、填上转录文本，再点“生成音色”';
                });
              }
              return;
            }
            // 本机 ZipVoice 不需要预先注册。
            voiceRef = 'local:zipvoice';
          }
        case ResidentVoiceMode.referenceOnly:
        case ResidentVoiceMode.referenceDescription:
          if (mounted) {
            setState(() {
              _saving = false;
              _voiceStatus = '当前语音服务还不支持这种方式，换一种吧';
            });
          }
          return;
      }
    } else {
      voiceRef = '';
    }
    _voiceRef = voiceRef;
    _originalVoiceDescription = _voiceDescription.text.trim();
    _originalVoiceMode = _voiceMode;

    final resident = CustomResident(
      id: widget.residentId ?? CustomResidentRepository.newId(),
      name: name,
      avatarAsset: _avatar,
      bio: _bio.text.trim(),
      description: _description.text.trim(),
      // 三块人设合并成一段后，旧的两个字段不再由编辑页写入。
      personality: '',
      scenario: '',
      languageStyle: _languageStyle.text.trim(),
      tone: _tone.text.trim(),
      exampleDialogue: _exampleDialogue.text.trim(),
      extraInstructions: _extraInstructions.text.trim(),
      tags: _tags.text
          .split(RegExp(r'[,，\s]+'))
          .where((tag) => tag.trim().isNotEmpty)
          .toList(growable: false),
      memoryEnabled: _memory,
      memoryLimit: newLimit,
      modelConfigId: _modelConfigId,
      voiceEnabled: _voiceEnabled,
      voiceDescription: _voiceDescription.text.trim(),
      voiceSamplePath: _voiceSamplePath,
      voiceSampleText: _voiceSampleText.text.trim(),
      voiceRef: voiceRef,
      voiceMode: _voiceMode,
      createdAt: _createdAt ?? DateTime.now(),
    );

    try {
      await ref.read(customResidentRepositoryProvider).upsert(resident);
      if (newLimit != null) {
        await ref
            .read(residentMemoryRepositoryProvider)
            .archiveOverflow(resident.id, newLimit);
      }

      // 新建时先读好、还没写进记忆的那段对话：保存后交给住民整理。
      // 失败只更新状态，不影响住民本身已经保存成功。
      if (_pendingTurns.isNotEmpty) {
        final pending = _pendingTurns;
        _pendingTurns = const [];
        await _runImport(resident.id, pending);
      }
      if (!mounted) return;

      // 刚建好的住民直接进私信页，并且马上叫醒他：
      // 没有手写开场白了，第一句话得他自己看着你说。
      if (widget.residentId == null) {
        unawaited(
          ref
              .read(residentWakeServiceProvider)
              .wake(resident.id, trigger: WakeTrigger.setup),
        );
        context.go('/chat/${resident.id}');
        return;
      }

      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  String _voiceLabel(String ref) {
    if (ref == 'local:zipvoice') return '本机克隆音色（ZipVoice）';
    if (ref.startsWith('local:')) return '本机音色 #${ref.substring(6)}';
    if (ref.startsWith('cloud:speech:')) return '云端克隆音色';
    if (ref.startsWith('cloud:')) return '云端音色 ${ref.substring(6)}';
    return ref;
  }

  @override
  Widget build(BuildContext context) {
    final cloudTts = ref.watch(cloudTtsConfigProvider).value;
    final modes = ref
        .watch(residentVoiceProfileServiceProvider)
        .modesFor(cloudTts);
    final canClone = modes.any((mode) => mode.usesSample);
    final mode = modes.contains(_voiceMode) ? _voiceMode : modes.first;
    final selectedSid = ResidentVoice.localSidOf(_voiceRef) ??
        ResidentVoice.sidFor(widget.residentId ?? _name.text.trim());
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.residentId == null ? '添加固定住民' : '编辑固定住民'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _BasicSection(
                  avatar: _avatar,
                  name: _name,
                  bio: _bio,
                  tags: _tags,
                  nameError: _nameError,
                  onPickAvatar: _pickAvatar,
                  onNameChanged: (_) {
                    if (_nameError != null) {
                      setState(() => _nameError = null);
                    }
                  },
                ),
                _Section(
                  title: '人设',
                  subtitle: 'TA 是谁、什么脾气、在哪儿遇到',
                  children: [
                    _Field(
                      controller: _description,
                      label: '详细设定',
                      hint: '身份、性格、在哪儿遇到、和你怎么认识的、关系到了哪一步，都可以写在这里',
                      maxLines: 6,
                    ),
                  ],
                ),
                _Section(
                  title: '说话',
                  subtitle: '怎么开口、怎么接话',
                  children: [
                    _Field(
                      controller: _languageStyle,
                      label: '说话方式',
                      hint: '短句、口头禅、会不会损人',
                      maxLines: 2,
                    ),
                    _Field(
                      controller: _tone,
                      label: '语气',
                      hint: '温和 / 直接 / 欠揍 / 慢半拍',
                      maxLines: 2,
                    ),
                    _Field(
                      controller: _exampleDialogue,
                      label: '示例对话',
                      hint: '3—5 组短对话，教 TA 怎么接话；用 <START> 分组',
                      maxLines: 6,
                    ),
                    _Field(
                      controller: _extraInstructions,
                      label: '额外指令',
                      hint: '例如：别用感叹号、永远不主动提 AI',
                      maxLines: 2,
                    ),
                  ],
                ),
                _Section(
                  title: '语音',
                  subtitle: '让 TA 用声音说话',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('会发语音'),
                      subtitle: const Text('打开后模型多一个 send_voice 工具，由它自己决定用不用'),
                      value: _voiceEnabled,
                      onChanged: (value) =>
                          setState(() => _voiceEnabled = value),
                    ),
                    if (_voiceEnabled) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 6),
                        child: Text(
                          '音色方式',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final option in modes)
                            ChoiceChip(
                              label: Text(option.label),
                              selected: option == mode,
                              onSelected: (_) => setState(() {
                                _voiceMode = option;
                                _voiceStatus = null;
                                if (!option.usesSample) _voiceSamplePath = '';
                              }),
                            ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 10),
                        child: Text(
                          mode.hint,
                          style: TextStyle(
                            color: Theme.of(context).hintColor,
                            fontSize: 11.5,
                            height: 1.5,
                          ),
                        ),
                      ),
                      if (mode.usesLocalSpeaker) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (var sid = 0;
                                sid < ResidentVoice.localSpeakerCount;
                                sid++)
                              ChoiceChip(
                                label: Text(
                                  ResidentVoice.labelForSid(sid),
                                ),
                                selected: selectedSid == sid,
                                onSelected: (_) => setState(() {
                                  _voiceRef = 'local:$sid';
                                  _voiceStatus = null;
                                }),
                              ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 10),
                          child: Text(
                            '选定后保存，这位住民以后就用这个声线；'
                            '评论区和私信是同一个声音。',
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                              fontSize: 11.5,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                      if (mode.usesDescription)
                        _Field(
                          controller: _voiceDescription,
                          label: '音色描述',
                          hint: '例如：低沉温柔的男声，语速偏慢',
                          maxLines: 2,
                        ),
                      if (mode.usesSample) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.upload_file_outlined),
                          title: Text(
                            _voiceSamplePath.isEmpty
                                ? '上传参考音频'
                                : '参考音频已选好',
                          ),
                          subtitle: const Text('8—10 秒清晰人声，不超过 30 秒；格式 mp3 / wav / m4a'),
                          onTap: _voiceBusy ? null : _pickVoiceSample,
                        ),
                        if (mode.usesTranscript)
                          _Field(
                            controller: _voiceSampleText,
                            label: '参考音频里说的话',
                            hint: '逐字填，注册音色时要用它对音频',
                            maxLines: 2,
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonal(
                            onPressed: _voiceBusy ? null : _cloneVoice,
                            child: Text(_voiceBusy ? '生成中…' : '生成音色'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '选了云端克隆，合成时会直接用这条云端音色；'
                          '没有配云端 TTS 时请用本机克隆（wav + 逐字稿）。',
                          style: TextStyle(
                            color: Theme.of(context).hintColor,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                      if (!canClone && modes.length == 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
                          child: Text(
                            '本机克隆需要 wav 参考音频 + 转录文本；'
                            '也可以去「模型」里配一条硅基流动 CosyVoice2 做云端克隆。',
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (_voiceRef.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Text(
                            '当前音色：${_voiceLabel(_voiceRef)}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      if (_voiceStatus != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 6),
                          child: Text(
                            _voiceStatus!,
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      Text(
                        '需要对话模型支持工具调用（function calling）；'
                        '住民才会自己决定发语音。',
                        style: TextStyle(
                          color: Theme.of(context).hintColor,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
                _Section(
                  title: '行为',
                  subtitle: '模型、记忆和出现频率',
                  children: [
                    _ResidentModelField(
                      value: _modelConfigId,
                      onChanged: (value) =>
                          setState(() => _modelConfigId = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('长期记忆'),
                      subtitle: const Text('记住你们聊过的事'),
                      value: _memory,
                      onChanged: (value) => setState(() => _memory = value),
                    ),
                    _Field(
                      controller: _memoryLimit,
                      label: '记忆上限',
                      hint: '留空 = 无上限',
                      keyboardType: TextInputType.number,
                      maxLines: 1,
                      showCount: false,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.forum_outlined),
                      title: const Text('导入聊天记录'),
                      subtitle: Text(
                        _importStatus ??
                            '从 DeepSeek 分享链接或粘贴文本里，让 TA 自己写记忆',
                      ),
                      trailing: _importBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right, size: 18),
                      onTap: _importBusy ? null : _importChat,
                    ),
                  ],
                ),
                if (widget.residentId != null)
                  _Section(
                    title: '日志',
                    subtitle: 'TA 什么时候醒过、给自己留了什么话',
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history),
                        title: Text('「${_name.text.trim()}」的日志'),
                        subtitle: Text(widget.residentId!),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => context.push(
                          RoutePaths.residentWakeLog(widget.residentId!),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }
}

/// 给这一位住民单独选一个对话模型。
///
/// 模型配置中心里可能存了好几条对话模型（便宜的、会写长文的、看图能力强的），
/// 这里让用户按住民分配。空值表示跟随“当前启用的那条”。
class _ResidentModelField extends ConsumerWidget {
  const _ResidentModelField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(modelConfigsProvider).value ?? const [];
    final chats = [
      for (final config in configs)
        if (config.kind == ModelKind.chat && config.isComplete) config,
    ];
    final known = chats.any((config) => config.id == value);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        initialValue: known ? value : '',
        decoration: const InputDecoration(
          labelText: '对话模型',
          helperText: '留空 = 跟随当前启用的模型',
          helperMaxLines: 2,
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('跟随当前启用')),
          for (final config in chats)
            DropdownMenuItem(
              value: config.id,
              child: Text(
                '${config.label} · ${config.model}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (picked) => onChanged(picked ?? ''),
      ),
    );
  }
}

class _BasicSection extends StatelessWidget {
  const _BasicSection({
    required this.avatar,
    required this.name,
    required this.bio,
    required this.tags,
    required this.nameError,
    required this.onPickAvatar,
    required this.onNameChanged,
  });

  final String avatar;
  final TextEditingController name;
  final TextEditingController bio;
  final TextEditingController tags;
  final String? nameError;
  final VoidCallback onPickAvatar;
  final ValueChanged<String> onNameChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: onPickAvatar,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      UserAvatar(
                        name: name.text,
                        avatarRef: avatar.isEmpty ? null : avatar,
                        size: 72,
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_library_outlined,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: name,
                    onChanged: onNameChanged,
                    decoration: InputDecoration(
                      labelText: '昵称',
                      hintText: '例如：小满',
                      errorText: nameError,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Field(
              controller: bio,
              label: '一句话简介',
              hint: '列表里显示：住楼下，爱拍照',
              maxLines: 1,
            ),
            _Field(
              controller: tags,
              label: '标签',
              hint: '游戏搭子、夜猫子、爱吐槽（逗号分隔，不发给模型）',
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.showCount = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              alignLabelWithHint: maxLines > 1,
            ),
          ),
          if (showCount)
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Text(
                  '${value.text.runes.length} 字',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
