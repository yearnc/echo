import 'package:flutter/material.dart';

import 'app_palette.dart';

/// 取色入口。
///
/// 历史背景：早先 [EchoColors] / [ClearColors] 是两套写死的常量色板，
/// 页面里每个颜色都直接引用它们，于是"明暗"实际上是被模式绑死的。
/// 现在外观可以独立切换，这两个类改成**指向当前生效的调色板**——
/// 页面里那三百多处引用一行都不用改，取到的值却会跟着外观设置走。
///
/// 两个名字都留着：回响侧页面写 [EchoColors.text] 读起来仍然是"回响模式的文字色"，
/// 清醒侧写 [ClearColors.text] 也一样；它们现在同源。
AppPalette _current = kPaletteDark;

/// 当前生效的调色板。
AppPalette get currentPalette => _current;

/// 换一套调色板。调用方（外观控制器）负责让界面重建。
void applyPalette(AppPalette palette) {
  _current = palette;
}

/// 回响侧页面的取色入口。
abstract final class EchoColors {
  static Color get bg => _current.bg;
  static Color get surface => _current.surface;
  static Color get surfaceHigh => _current.surfaceHigh;
  static Color get overlay => _current.overlay;
  static Color get primary => _current.primary;
  static Color get primaryDim => _current.primaryDim;
  static Color get accent => _current.accent;
  static Color get like => _current.like;
  static Color get text => _current.text;
  static Color get textMuted => _current.textMuted;
  static Color get textFaint => _current.textFaint;
  static Color get divider => _current.divider;
  static Color get hot => _current.hot;
  static Color get success => _current.success;
  static Color get glow => _current.glow;
}

/// 清醒侧页面的取色入口（与 [EchoColors] 同源）。
abstract final class ClearColors {
  static Color get bg => _current.bg;
  static Color get surface => _current.surface;
  static Color get surfaceHigh => _current.surfaceHigh;
  static Color get overlay => _current.overlay;
  static Color get primary => _current.primary;
  static Color get primaryDim => _current.primaryDim;
  static Color get accent => _current.accent;
  static Color get like => _current.like;
  static Color get text => _current.text;
  static Color get textMuted => _current.textMuted;
  static Color get textFaint => _current.textFaint;
  static Color get divider => _current.divider;
  static Color get hot => _current.hot;
  static Color get success => _current.success;
  static Color get glow => _current.glow;
}
