import 'package:flutter/material.dart';

/// 双模式色板。
///
/// 两种模式的视觉语言刻意拉开距离，这不是换肤，而是产品语义的一部分：
/// - [EchoColors]：回响模式。深色、带辉光、信息密度高——一个"永远在回应你"的社区。
/// - [ClearColors]：清醒模式。暖白纸感、克制、留白多——一个安静的房间。
///
/// 所有颜色都定义在这里，页面里不允许出现裸十六进制色值。
class EchoColors {
  const EchoColors._();

  // 背景层：越靠上层越亮，用于制造层级而不是靠阴影
  static const Color bg = Color(0xFF0B0A12);
  static const Color surface = Color(0xFF16142A);
  static const Color surfaceHigh = Color(0xFF1F1B37);
  static const Color overlay = Color(0xFF272141);

  // 品牌色：紫罗兰（开发助手的紫）+ 青蓝点缀
  static const Color primary = Color(0xFF8B5CF6);
  static const Color primaryDim = Color(0xFF6D46C9);
  static const Color accent = Color(0xFF22D3EE);

  /// 点赞红——刻意选偏粉的色相，避开"警告红"的语义。
  static const Color like = Color(0xFFFF5C8A);

  // 文字
  static const Color text = Color(0xFFEDEAF7);
  static const Color textMuted = Color(0xFF948CB8);
  static const Color textFaint = Color(0xFF6B6489);

  static const Color divider = Color(0xFF2A2742);
  static const Color hot = Color(0xFFFF8A3D);
  static const Color success = Color(0xFF4ADE80);

  /// 深色页面里的外发光，用于点赞粒子、热榜火焰等氛围元素。
  static const Color glow = Color(0x598B5CF6);
}

class ClearColors {
  const ClearColors._();

  // 暖白纸感：不用纯白，避免刺眼，也让"记录"更像笔记本
  static const Color bg = Color(0xFFF7F5F0);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceHigh = Color(0xFFF1EEE6);
  static const Color overlay = Color(0xFFE9E5DA);

  // 主色：克制的墨绿；点缀：陶土橙（真实、手工的联想）
  static const Color primary = Color(0xFF3F6B57);
  static const Color primaryDim = Color(0xFF315446);
  static const Color accent = Color(0xFFC2703D);

  static const Color text = Color(0xFF22201C);
  static const Color textMuted = Color(0xFF6E6A62);
  static const Color textFaint = Color(0xFF9C978C);

  static const Color divider = Color(0xFFE4E0D6);
  static const Color success = Color(0xFF4F8A5B);
}
