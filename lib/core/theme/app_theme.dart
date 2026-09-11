import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 双主题构建。
///
/// 排版上刻意做了一件事：回响模式的信息层级靠「亮度差」拉开（深色下加阴影没用），
/// 清醒模式靠「留白 + 细边框」拉开。所以两套 textTheme 的行高与字重是不同的，
/// 不是简单地把颜色换掉。
class AppTheme {
  const AppTheme._();

  static ThemeData get echo => _build(
        brightness: Brightness.dark,
        colors: const _Palette(
          bg: EchoColors.bg,
          surface: EchoColors.surface,
          surfaceHigh: EchoColors.surfaceHigh,
          primary: EchoColors.primary,
          accent: EchoColors.accent,
          text: EchoColors.text,
          textMuted: EchoColors.textMuted,
          divider: EchoColors.divider,
          onPrimary: Colors.white,
        ),
        lineHeight: 1.45,
        leadingWeight: FontWeight.w600,
      );

  static ThemeData get clear => _build(
        brightness: Brightness.light,
        colors: const _Palette(
          bg: ClearColors.bg,
          surface: ClearColors.surface,
          surfaceHigh: ClearColors.surfaceHigh,
          primary: ClearColors.primary,
          accent: ClearColors.accent,
          text: ClearColors.text,
          textMuted: ClearColors.textMuted,
          divider: ClearColors.divider,
          onPrimary: Colors.white,
        ),
        // 清醒模式行高更松，读起来更像纸面
        lineHeight: 1.62,
        leadingWeight: FontWeight.w500,
      );

  static ThemeData _build({
    required Brightness brightness,
    required _Palette colors,
    required double lineHeight,
    required FontWeight leadingWeight,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.primary,
      brightness: brightness,
    ).copyWith(
      primary: colors.primary,
      secondary: colors.accent,
      surface: colors.surface,
      onSurface: colors.text,
      onPrimary: colors.onPrimary,
      outlineVariant: colors.divider,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );

    // 必须显式关掉文本装饰：
    // Flutter 的兜底文本样式（app.dart 里的 _errorTextStyle）带
    //   decoration: underline + decorationColor: 黄色
    // 而 Typography 里部分字号没有声明 decoration: none，
    // 于是把这条**黄色双下划线**继承了下来（同一个组件里 labelLarge 有、bodyMedium 没有）。
    // 统一在这里声明"不要装饰"，把所有继承路径一次性掐断。
    final text = base.textTheme.apply(
      bodyColor: colors.text,
      displayColor: colors.text,
      decoration: TextDecoration.none,
      decorationColor: Colors.transparent,
      decorationStyle: TextDecorationStyle.solid,
    );

    return base.copyWith(
      scaffoldBackgroundColor: colors.bg,
      dividerColor: colors.divider,
      splashFactory: InkSparkle.splashFactory,
      textTheme: text.copyWith(
        // 页面大标题：加大字重与负字距，避免"默认模板感"
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          height: 1.2,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: leadingWeight,
          letterSpacing: -0.2,
          height: 1.3,
        ),
        titleMedium: text.titleMedium?.copyWith(fontWeight: leadingWeight),
        bodyLarge: text.bodyLarge?.copyWith(height: lineHeight),
        bodyMedium: text.bodyMedium?.copyWith(height: lineHeight),
        labelSmall: text.labelSmall?.copyWith(
          color: colors.textMuted,
          letterSpacing: 0.3,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: colors.text,
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(brightness == Brightness.dark ? 18 : 14),
          side: BorderSide(color: colors.divider),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.text,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: colors.divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceHigh,
        hintStyle: TextStyle(color: colors.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.primary, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceHigh,
        contentTextStyle: TextStyle(color: colors.text),
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.textMuted,
        textColor: colors.text,
      ),
    );
  }
}

/// 主题构建用的最小调色板，避免 _build 里直接引用两套具名常量。
class _Palette {
  const _Palette({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.primary,
    required this.accent,
    required this.text,
    required this.textMuted,
    required this.divider,
    required this.onPrimary,
  });

  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color primary;
  final Color accent;
  final Color text;
  final Color textMuted;
  final Color divider;
  final Color onPrimary;
}
