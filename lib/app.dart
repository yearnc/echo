import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_palette.dart';
import 'core/theme/app_theme.dart';
import 'data/bootstrap_provider.dart';
import 'domain/services/appearance_controller.dart';
import 'domain/services/mode_controller.dart';
import 'domain/services/scheduler_service.dart';

/// 应用根组件。
///
/// 主题跟着模式走：回响模式用深色（沉浸），清醒模式用暖白（安静）。
/// 这不是"跟随系统"，而是产品语义——两种模式看世界的方式本来就不同。
///
/// 它还负责一件事：**前台心跳**。排期只在 APP 启动时补发是不够的——
/// 用户开着 APP 等十分钟什么都不会发生（这是 2026-09-11 实测发现的缺口）。
///
/// 心跳有两档，因为两种排期的精度要求不同：
/// - **随机排期**（普通发帖）：30 秒一档足够，"陆续有人路过"本来就不精确
/// - **策划排期**（策划帖）：1 秒一档。脚本里写"第 1 秒有点赞"，
///   就必须真的在第 1 秒跳出来——30 秒的粒度会把这句台词毁掉
///
/// 所以定时器固定跑 1 秒，每拍只做一次很轻的计数查询；
/// 只有确实存在未执行的策划事件时才去兑现，空闲时几乎不花钱。
class EchoApp extends ConsumerStatefulWidget {
  const EchoApp({super.key});

  @override
  ConsumerState<EchoApp> createState() => _EchoAppState();
}

class _EchoAppState extends ConsumerState<EchoApp> {
  static const Duration _tick = Duration(seconds: 1);

  /// 随机排期每多少拍扫一次（1 拍 = 1 秒）。
  static const int _idleFlushEveryTicks = 30;

  Timer? _heartbeat;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _heartbeat = Timer.periodic(_tick, (_) async {
      // 出错也不能让心跳断掉：这一拍没补上，下一拍还会再试
      try {
        final scheduler = ref.read(schedulerServiceProvider);

        if (await scheduler.pendingPlanCount() > 0) {
          await scheduler.flushPlanEvents();
        }

        _ticks++;
        if (_ticks >= _idleFlushEveryTicks) {
          _ticks = 0;
          await scheduler.flushDue();
        }
      } catch (_) {
        // 静默：补发失败不该弹窗打断用户
      }
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(modeControllerProvider);
    final appearance = ref.watch(appearanceControllerProvider);
    final bootstrap = ref.watch(appBootstrapProvider);

    if (bootstrap.isLoading) {
      return const _Splash();
    }
    if (bootstrap.hasError) {
      return _StartupError(message: '${bootstrap.error}');
    }

    // 明暗由外观设置决定（auto 时跟模式走）。
    final palette = switch (appearance) {
      AppearanceMode.auto => mode.isEcho ? kPaletteDark : kPaletteLight,
      AppearanceMode.light => kPaletteLight,
      AppearanceMode.dark => kPaletteDark,
    };
    // 页面里的颜色是直接读调色板的，不是走 Theme——所以换调色板之后
    // 必须让整棵树重建一次，key 变化正好做这件事。
    applyPalette(palette);
    final isDark = identical(palette, kPaletteDark);

    return MaterialApp.router(
      key: ValueKey(isDark ? 'theme-dark' : 'theme-light'),
      title: '回响 Echo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.clear,
      darkTheme: AppTheme.echo,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: appRouter,
      builder: (context, child) {
        // 固定文字缩放，避免系统大字体把信息流卡片挤变形
        final media = MediaQuery.of(context);
        // 状态栏 / 手势条也是画面的一部分：深色底配浅色图标，浅色底配深色图标。
        // 不显式指定的话，Android 会按**系统**主题给图标着色——
        // 回响模式（深色）碰上系统浅色时，图标会糊在背景里看不见。
        final overlay = isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
          child: MediaQuery(
            data: media.copyWith(textScaler: TextScaler.noScaling),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

/// 启动页：开库与播种通常只在这一瞬间可见。
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: EchoColors.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '回响',
                style: TextStyle(
                  color: EchoColors.text,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              SizedBox(height: 14),
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: EchoColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 启动失败：本地数据库起不来时要把原因说清楚，而不是白屏。
class _StartupError extends StatelessWidget {
  const _StartupError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: EchoColors.bg,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: EchoColors.like, size: 32),
                const SizedBox(height: 14),
                Text(
                  '本地数据库启动失败',
                  style: TextStyle(color: EchoColors.text, fontSize: 16),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: EchoColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
