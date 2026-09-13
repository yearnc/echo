import 'package:flutter/material.dart';

/// 一套完整的界面配色。
///
/// 明暗由这份调色板决定，而不是由模式决定——模式负责"在哪个社区"，
/// 外观负责"用哪套明暗"，两者正交。以前这两件事被绑在一起：
/// 切到回响模式就一定是深紫，切到清醒模式就一定是暖白，用户没有选择权。
///
/// 深色那套原本是 [EchoColors] 的值，浅色那套原本是 [ClearColors] 的值；
/// 浅色版另外补齐了深色版独有的三个语义色（点赞红、热度橙、外发光）。
class AppPalette {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.overlay,
    required this.primary,
    required this.primaryDim,
    required this.accent,
    required this.like,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.divider,
    required this.hot,
    required this.success,
    required this.glow,
  });

  /// 背景层：越靠上层越亮，用来制造层级而不是靠阴影。
  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color overlay;

  final Color primary;
  final Color primaryDim;
  final Color accent;

  /// 点赞红——偏粉的色相，避开"警告红"的语义。
  final Color like;

  final Color text;
  final Color textMuted;
  final Color textFaint;

  final Color divider;
  final Color hot;
  final Color success;

  /// 深色页面里的外发光（点赞粒子、热榜火焰等氛围元素）。
  final Color glow;
}

/// 深色：回响模式原本的配色（深紫、带辉光、信息密度高）。
const AppPalette kPaletteDark = AppPalette(
  bg: Color(0xFF0B0A12),
  surface: Color(0xFF16142A),
  surfaceHigh: Color(0xFF1F1B37),
  overlay: Color(0xFF272141),
  primary: Color(0xFF8B5CF6),
  primaryDim: Color(0xFF6D46C9),
  accent: Color(0xFF22D3EE),
  like: Color(0xFFFF5C8A),
  text: Color(0xFFEDEAF7),
  textMuted: Color(0xFF948CB8),
  textFaint: Color(0xFF6B6489),
  divider: Color(0xFF2A2742),
  hot: Color(0xFFFF8A3D),
  success: Color(0xFF4ADE80),
  glow: Color(0x598B5CF6),
);

/// 浅色：清醒模式原本的配色（暖白纸感、克制、留白多）。
const AppPalette kPaletteLight = AppPalette(
  bg: Color(0xFFF7F5F0),
  surface: Color(0xFFFFFFFF),
  surfaceHigh: Color(0xFFF1EEE6),
  overlay: Color(0xFFE9E5DA),
  primary: Color(0xFF3F6B57),
  primaryDim: Color(0xFF315446),
  accent: Color(0xFFC2703D),
  like: Color(0xFFD9436F),
  text: Color(0xFF22201C),
  textMuted: Color(0xFF6E6A62),
  textFaint: Color(0xFF9C978C),
  divider: Color(0xFFE4E0D6),
  hot: Color(0xFFD9672E),
  success: Color(0xFF4F8A5B),
  glow: Color(0x333F6B57),
);
