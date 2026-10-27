import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/services/backup_service.dart';
import '../../domain/services/mode_controller.dart';

/// 数据备份与恢复（v3.9）。
///
/// 换设备时最怕的不是“没云同步”，而是本地几百条记录跟着旧手机一起消失。
/// 这里给一份全量文件：默认模式防篡改、免密码；也可以选密码模式，
/// 导入时必须输入同一个密码。
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;
  String? _status;

  @override
  Widget build(BuildContext context) {
    final isEcho = ref.watch(modeControllerProvider).isEcho;
    final bg = isEcho ? EchoColors.bg : ClearColors.bg;
    final surface = isEcho ? EchoColors.surface : ClearColors.surface;
    final text = isEcho ? EchoColors.text : ClearColors.text;
    final muted = isEcho ? EchoColors.textMuted : ClearColors.textMuted;
    final faint = isEcho ? EchoColors.textFaint : ClearColors.textFaint;
    final primary = isEcho ? EchoColors.primary : ClearColors.primary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: text),
        title: Text(
          '数据备份与恢复',
          style: TextStyle(
            color: text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isEcho ? EchoColors.divider : ClearColors.divider,
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '把整个 App 的数据装进一个文件',
                  style: TextStyle(
                    color: text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '帖子、评论区、固定住民、记忆、私信、清醒记录和设置都会一起打包。'
                  '模型密钥存在系统钥匙串里，不会进备份文件。',
                  style: TextStyle(color: muted, fontSize: 12.5, height: 1.55),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _ActionTile(
            icon: Icons.save_alt_outlined,
            title: '导出备份',
            subtitle: '默认加密（免密码、防篡改）或设置一个密码',
            color: primary,
            textColor: text,
            mutedColor: muted,
            onTap: _busy ? null : _export,
          ),
          const SizedBox(height: 10),
          _ActionTile(
            icon: Icons.restore_outlined,
            title: '导入备份',
            subtitle: '会覆盖本机当前的全部数据，导入前会再确认一次',
            color: primary,
            textColor: text,
            mutedColor: muted,
            onTap: _busy ? null : _import,
          ),
          const SizedBox(height: 22),
          Text(
            '说明',
            style: TextStyle(
              color: text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _Note(
            color: faint,
            text:
                '· 默认模式不设密码，方便换机；文件被改动过一个字节就解不开，'
                '但拿到文件的人仍可导入，所以它防篡改、不防人。\n'
                '· 密码模式用 PBKDF2（12 万次）+ AES-256-GCM；密码丢了就解不开，'
                '请自己留好。\n'
                '· 备份文件里是这台设备的全部记录，请当作隐私文件保管。',
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            Center(child: CircularProgressIndicator(color: primary)),
          ],
          if (_status != null) ...[
            const SizedBox(height: 18),
            Text(
              _status!,
              style: TextStyle(color: muted, fontSize: 12, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _export() async {
    final password = await _pickExportPassword();
    if (password == null) return; // 取消
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final path = await ref
          .read(backupServiceProvider)
          .export(password: password.isEmpty ? null : password);
      if (!mounted) return;
      try {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(path)], text: '回响 · 全量数据备份'),
        );
      } catch (error) {
        debugPrint('[备份] 分享面板没打开：$error');
      }
      if (!mounted) return;
      setState(() => _status = '已导出到：$path');
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('已导出'),
          content: SelectableText(
            '文件保存在：\n$path\n\n'
            '${password.isEmpty ? '这份备份没有密码，换设备后直接导入即可。' : '这份备份需要密码，导入时会要求输入。'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('好'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _status = '导出失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    // Android 对自定义扩展名的过滤不可靠，先让用户能选到文件。
    final picked = await FilePicker.pickFiles(type: FileType.any);
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null || path.isEmpty) return;

    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final service = ref.read(backupServiceProvider);
      final envelope = await service.read(path);

      var password = '';
      if (envelope.needsPassword) {
        if (!mounted) return;
        final input = await _askPassword(title: '这份备份需要密码', confirm: false);
        if (input == null) return;
        password = input;
      }

      final payload = await service.decode(envelope, password: password);
      if (!mounted) return;

      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('覆盖本机数据？'),
          content: Text(
            '备份时间：${_when(envelope.createdAt)}\n'
            'App 版本：${envelope.appVersion}\n'
            '内容：${payload.tables.length} 张表、${payload.rowCount} 行\n\n'
            '导入会先清空本机现有数据，再写入这份备份。'
            '当前数据没有其他副本的话，请先取消并导出一份。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认导入'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      final result = await service.restore(payload);
      if (!mounted) return;
      setState(
        () => _status =
            '恢复完成：${result.tables} 张表、${result.rows} 行。'
            '如果页面还有旧数据，退出重进一次即可。',
      );
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('导入完成'),
          content: Text(
            '已写入 ${result.rows} 行，覆盖 ${result.tables} 张表。\n\n'
            '模型密钥不在备份里：如果模型页提示没有 Key，重新填一次即可。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('好'),
            ),
          ],
        ),
      );
    } on BackupException catch (error) {
      if (mounted) setState(() => _status = '导入失败：$error');
    } catch (error) {
      if (mounted) setState(() => _status = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 返回：`''` = 默认模式；非空 = 密码；null = 取消。
  Future<String?> _pickExportPassword() async {
    final usePassword = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: (ref.read(modeControllerProvider).isEcho
          ? EchoColors.surface
          : ClearColors.surface),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.lock_open_outlined),
              title: const Text('默认加密（免密码）'),
              subtitle: const Text('换设备后直接导入；防篡改，但不防别人拿到文件'),
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('用密码加密'),
              subtitle: const Text('导入时必须输入同一个密码'),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (usePassword == null) return null;
    if (!usePassword) return '';
    return _askPassword(title: '设置备份密码', confirm: true);
  }

  Future<String?> _askPassword({
    required String title,
    required bool confirm,
  }) async {
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: first,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: '密码'),
              ),
              if (confirm)
                TextField(
                  controller: second,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '再输一次'),
                ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: TextStyle(color: EchoColors.like, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final value = first.text;
                if (value.trim().length < 4) {
                  setDialogState(() => error = '密码至少 4 位');
                  return;
                }
                if (confirm && value != second.text) {
                  setDialogState(() => error = '两次输入不一样');
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  static String _when(DateTime at) =>
      '${at.year}-${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')} '
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.textColor,
    required this.mutedColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color textColor;
  final Color mutedColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: textColor, fontSize: 14.5)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: mutedColor, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: color, fontSize: 12, height: 1.65),
    );
  }
}
