import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_texts.dart';
import '../../core/theme/app_colors.dart';
import '../../data/media/media_service.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';
import '../shared_widgets/user_avatar.dart';

/// 编辑我的资料：昵称 + 头像。
///
/// 头像走的是全项目同一套三级兜底（[UserAvatar]）：内置图片 → 自己选的图 → 文字头像。
/// 这里只负责"选"和"存引用"，不碰图片本身怎么加载——所以素材换了、加载失败，
/// 这一页都不用改。
class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final _nickname = TextEditingController();

  /// 头像引用（`asset:` / `file:` / 空字符串 = 文字头像）。
  String _avatarRef = '';

  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await ref.read(userProfileRepositoryProvider).load();
    if (!mounted) return;
    setState(() {
      _nickname.text = profile?.nickname ?? '';
      _avatarRef = profile?.avatarRef ?? '';
      _loaded = true;
    });
  }

  /// 昵称没填时预览用默认名——不然头像会显示成"?",看着像坏了。
  String get _previewName {
    final trimmed = _nickname.text.trim();
    return trimmed.isEmpty ? AppTexts.defaultNickname : trimmed;
  }

  Future<void> _pickAvatar() async {
    final picked = await ref.read(mediaServiceProvider).pickFromGallery();
    if (picked == null || !mounted) return;
    setState(() => _avatarRef = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final repo = ref.read(userProfileRepositoryProvider);
    final before = await repo.load();
    await repo.save(nickname: _nickname.text, avatarRef: _avatarRef);

    // 换过自己选的图，就把上一张从私有目录清掉——不然每换一次都留一份
    final previous = before?.avatarRef ?? '';
    if (previous.startsWith('file:') && previous != _avatarRef) {
      await ref.read(mediaServiceProvider).deleteByRef(previous);
    }

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存')));
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          '编辑资料',
          style: TextStyle(color: EchoColors.text, fontSize: 16),
        ),
      ),
      bottomNavigationBar: const SafeArea(child: AiDisclaimerBar()),
      body: !_loaded
          ? Center(child: CircularProgressIndicator(color: EchoColors.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Center(
                  child: UserAvatar(
                    name: _previewName,
                    avatarRef: _avatarRef.trim().isEmpty ? null : _avatarRef,
                    size: 88,
                    showRing: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _saving ? null : _pickAvatar,
                      icon: const Icon(Icons.photo_library_outlined, size: 17),
                      label: const Text('从相册选一张'),
                      style: TextButton.styleFrom(
                        foregroundColor: EchoColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: _saving || _avatarRef.isEmpty
                          ? null
                          : () => setState(() => _avatarRef = ''),
                      style: TextButton.styleFrom(
                        foregroundColor: EchoColors.textMuted,
                      ),
                      child: const Text('用文字头像'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '昵称',
                  style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nickname,
                  maxLength: 16,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: EchoColors.text, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: AppTexts.defaultNickname,
                    hintStyle: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 14,
                    ),
                    counterStyle: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 11,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: EchoColors.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: EchoColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '留空就用默认名。昵称和头像只存在这台设备上，不会上传到任何服务器。',
                  style: TextStyle(
                    color: EchoColors.textFaint,
                    fontSize: 11.5,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: EchoColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: Text(_saving ? '保存中…' : '保存'),
                  ),
                ),
              ],
            ),
    );
  }
}
