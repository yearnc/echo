import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/user_profile_repository.dart';

/// 我的身份：告诉 AI"正在跟谁说话"。
///
/// 这些字段会作为**稳定前缀**拼到每一次模型请求的 system 最前面，
/// 所以只放不常变的东西；改一次身份，缓存前缀整体失效一次，可以接受。
class IdentityPage extends ConsumerStatefulWidget {
  const IdentityPage({super.key});

  @override
  ConsumerState<IdentityPage> createState() => _IdentityPageState();
}

class _IdentityPageState extends ConsumerState<IdentityPage> {
  final _preferredName = TextEditingController();
  final _occupation = TextEditingController();
  final _city = TextEditingController();
  final _interests = TextEditingController();
  final _intro = TextEditingController();

  String _gender = '';
  String _ageRange = '';
  bool _loaded = false;
  bool _saving = false;

  static const _genderOptions = [
    ('male', '男'),
    ('female', '女'),
    ('nonbinary', '非二元'),
    ('secret', '不愿透露'),
  ];
  static const _ageOptions = ['18 岁以下', '18—22', '23—30', '30 岁以上'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _preferredName.dispose();
    _occupation.dispose();
    _city.dispose();
    _interests.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await ref.read(userProfileRepositoryProvider).load();
    if (!mounted) return;
    setState(() {
      _preferredName.text = profile?.preferredName ?? '';
      _occupation.text = profile?.occupation ?? '';
      _city.text = profile?.city ?? '';
      _interests.text = profile?.interests ?? '';
      _intro.text = profile?.intro ?? '';
      _gender = profile?.gender ?? '';
      _ageRange = profile?.ageRange ?? '';
      _loaded = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(userProfileRepositoryProvider)
          .save(
            gender: _gender,
            ageRange: _ageRange,
            occupation: _occupation.text,
            city: _city.text,
            interests: _interests.text,
            preferredName: _preferredName.text,
            intro: _intro.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('身份已保存')));
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
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
          '我的身份',
          style: TextStyle(color: EchoColors.text, fontSize: 16),
        ),
      ),
      body: !_loaded
          ? Center(child: CircularProgressIndicator(color: EchoColors.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                _Hint(),
                const SizedBox(height: 18),
                _Label('希望 AI 怎么称呼你'),
                TextField(
                  controller: _preferredName,
                  maxLength: 12,
                  style: TextStyle(color: EchoColors.text, fontSize: 15),
                  decoration: _decoration('留空就用昵称'),
                ),
                _Label('性别'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in _genderOptions)
                      _Choice(
                        label: option.$2,
                        selected: _gender == option.$1,
                        onTap: () => setState(
                          () => _gender = _gender == option.$1 ? '' : option.$1,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _Label('年龄段'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in _ageOptions)
                      _Choice(
                        label: option,
                        selected: _ageRange == option,
                        onTap: () => setState(
                          () => _ageRange = _ageRange == option ? '' : option,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _Label('身份／职业'),
                TextField(
                  controller: _occupation,
                  style: TextStyle(color: EchoColors.text, fontSize: 15),
                  decoration: _decoration('填写你的身份或职业，可留空'),
                ),
                _Label('所在城市'),
                TextField(
                  controller: _city,
                  style: TextStyle(color: EchoColors.text, fontSize: 15),
                  decoration: _decoration('填写你所在的城市，可留空'),
                ),
                _Label('兴趣爱好'),
                TextField(
                  controller: _interests,
                  maxLines: 2,
                  style: TextStyle(color: EchoColors.text, fontSize: 15),
                  decoration: _decoration('填写你的兴趣，可留空'),
                ),
                _Label('一句话介绍'),
                TextField(
                  controller: _intro,
                  maxLines: 3,
                  maxLength: 120,
                  style: TextStyle(color: EchoColors.text, fontSize: 15),
                  decoration: _decoration('你想让 AI 知道的自己'),
                ),
                const SizedBox(height: 12),
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

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: EchoColors.textFaint, fontSize: 13),
    counterStyle: TextStyle(color: EchoColors.textFaint, fontSize: 11),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: EchoColors.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: EchoColors.primary),
    ),
  );
}

class _Hint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Text(
        '这些资料只存在这台设备上，会作为前缀发给当前配置的模型服务商，'
        '让 AI 用合适的称呼和角度跟你说话。不填也可以，没填的不会编造。',
        style: TextStyle(
          color: EchoColors.textMuted,
          fontSize: 12.5,
          height: 1.7,
        ),
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
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text,
        style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
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
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? EchoColors.primary.withValues(alpha: 0.14)
              : EchoColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? EchoColors.primary : EchoColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? EchoColors.primary : EchoColors.textMuted,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
