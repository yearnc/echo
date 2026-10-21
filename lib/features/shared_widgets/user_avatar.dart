import 'dart:io';

import 'package:flutter/material.dart';

/// 头像：**图片优先，文字兜底**（规划书素材策略）。
///
/// 只认三种 reference 写法，业务层不需要知道文件从哪来：
/// - `asset:assets/avatars/persona_001.png` → 内置图片
/// - `file:<绝对路径>`                       → 用户上传（存在 APP 私有目录）
/// - 空字符串 / 文件不存在 / 加载失败          → 文字头像（昵称首字 + 稳定配色）
///
/// 素材还没到位时（开发期的默认状态）全部走文字头像，界面不会崩，
/// 后续把图片丢进 `assets/avatars/` 就能自动生效，业务代码一行不用改。
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.avatarRef,
    this.size = 40,
    this.showRing = false,
  });

  final String name;
  final String? avatarRef;
  final double size;

  /// 回响模式里给"活跃住民"加一圈光环。
  final bool showRing;

  static const List<Color> _fallbackPalette = [
    Color(0xFF8B5CF6),
    Color(0xFF22D3EE),
    Color(0xFFFF5C8A),
    Color(0xFFFF8A3D),
    Color(0xFF4ADE80),
    Color(0xFF60A5FA),
    Color(0xFFF472B6),
    Color(0xFFA78BFA),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _fallbackColor();
    final hasImage = _looksLikeImage();

    // 有图时**不能**再铺一层半透明底色：圆形裁切的抗锯齿边缘会和底色
    // 混出一圈“背景残留”，看起来像头像没铺满。底色只留给文字头像。
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hasImage ? Colors.transparent : color.withValues(alpha: 0.18),
        border: showRing
            ? Border.all(
                color: hasImage
                    ? Theme.of(context).colorScheme.outline.withValues(
                        alpha: 0.45,
                      )
                    : color.withValues(alpha: 0.55),
                width: 1.4,
              )
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildContent(color),
    );
  }

  /// 是否可能是一张图。文件不存在的仍走文字兜底；asset 交给 errorBuilder。
  bool _looksLikeImage() {
    final ref = avatarRef?.trim() ?? '';
    if (ref.startsWith('asset:') || ref.startsWith('http')) return true;
    if (ref.startsWith('file:')) {
      return File(ref.substring('file:'.length)).existsSync();
    }
    return false;
  }

  Widget _buildContent(Color color) {
    final ref = avatarRef?.trim() ?? '';
    if (ref.isEmpty) return _textFallback(color);

    if (ref.startsWith('asset:')) {
      return SizedBox.expand(
        child: Image.asset(
          ref.substring('asset:'.length),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, _, _) => _textFallback(color),
        ),
      );
    }

    if (ref.startsWith('file:')) {
      final file = File(ref.substring('file:'.length));
      if (!file.existsSync()) return _textFallback(color);
      return SizedBox.expand(
        child: Image.file(
          file,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, _, _) => _textFallback(color),
        ),
      );
    }

    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return SizedBox.expand(
        child: Image.network(
          ref,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, _, _) => _textFallback(color),
        ),
      );
    }

    return _textFallback(color);
  }

  Widget _textFallback(Color color) {
    // 图片加载失败时把底色补回来，不然文字头像会挂在透明背景上。
    return ColoredBox(
      color: color.withValues(alpha: 0.18),
      child: Center(
        child: Text(
          _initial(),
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1,
          ),
        ),
      ),
    );
  }

  /// 用 runes 取首字，避免 emoji 昵称被截成半个代理对。
  String _initial() {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first);
  }

  /// 用昵称哈希定色：同一个人格每次渲染颜色一致，像是"他自己的颜色"。
  Color _fallbackColor() =>
      _fallbackPalette[name.hashCode.abs() % _fallbackPalette.length];
}
