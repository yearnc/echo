import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/chat_transcript_import.dart';

/// 导入一段旧聊天（v3.9）。
///
/// 两条路：DeepSeek 分享链接（推荐，自动抓），或者把对话复制过来粘贴。
/// 这里只负责“读到哪几段话”；写记忆由编辑页交给住民自己做。
class ChatImportSheet extends ConsumerStatefulWidget {
  const ChatImportSheet({super.key});

  @override
  ConsumerState<ChatImportSheet> createState() => _ChatImportSheetState();
}

class _ChatImportSheetState extends ConsumerState<ChatImportSheet> {
  final _link = TextEditingController();
  final _text = TextEditingController();
  bool _useLink = true;
  bool _busy = false;
  String? _error;
  List<ImportedTurn> _turns = const [];

  @override
  void dispose() {
    _link.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final importer = ref.read(chatTranscriptImporterProvider);
    setState(() {
      _busy = true;
      _error = null;
      _turns = const [];
    });
    try {
      final turns = _useLink
          ? await importer.fromShareLink(_link.text)
          : importer.fromPlainText(_text.text);
      if (!mounted) return;
      setState(() => _turns = turns);
    } on ChatImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '读取失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final userTurns = _turns.where((turn) => turn.fromUser).length;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '导入聊天记录',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '把一段旧对话交给 TA，让 TA 自己挑出值得记住的事。'
                '不会把整段对话永久存下来，只有 TA 写下的记忆会留下。',
                style: TextStyle(
                  color: Theme.of(context).hintColor,
                  fontSize: 12,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('分享链接')),
                  ButtonSegment(value: false, label: Text('粘贴文本')),
                ],
                selected: {_useLink},
                onSelectionChanged: (value) => setState(() {
                  _useLink = value.first;
                  _error = null;
                  _turns = const [];
                }),
              ),
              const SizedBox(height: 12),
              if (_useLink)
                TextField(
                  controller: _link,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'DeepSeek 分享链接',
                    hintText: 'https://chat.deepseek.com/share/...',
                    helperText: '在 DeepSeek 里点「分享」→「复制链接」',
                    helperMaxLines: 2,
                  ),
                )
              else
                TextField(
                  controller: _text,
                  minLines: 6,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: '对话文本',
                    hintText: '我：你好\nAI：你好！有什么可以帮你的？',
                    helperText: '每段前写「我：」或「AI：」，一行一段',
                    helperMaxLines: 2,
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.tonal(
                    onPressed: _busy ? null : _read,
                    child: Text(_busy ? '读取中…' : '读取对话'),
                  ),
                  const SizedBox(width: 10),
                  if (_error != null)
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                ],
              ),
              if (_turns.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '读到 ${_turns.length} 段：我说 $userTurns 段，'
                  '对方说 ${_turns.length - userTurns} 段',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _preview(_turns),
                    style: TextStyle(
                      color: Theme.of(context).hintColor,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_turns),
                    child: const Text('让 TA 读一遍，写进记忆'),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '需要这位住民有可用的对话模型；整理时会发送这段对话给它。',
                  style: TextStyle(
                    color: Theme.of(context).hintColor,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _preview(List<ImportedTurn> turns) {
    final buffer = StringBuffer();
    for (final turn in turns.take(6)) {
      final text = turn.text.replaceAll('\n', ' ');
      buffer.writeln(
        '${turn.fromUser ? '我' : '对方'}：'
        '${text.length > 60 ? '${text.substring(0, 60)}…' : text}',
      );
    }
    if (turns.length > 6) buffer.writeln('……');
    return buffer.toString().trimRight();
  }
}
