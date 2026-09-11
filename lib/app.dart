import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'data/bootstrap_provider.dart';
import 'domain/services/mode_controller.dart';
import 'domain/services/scheduler_service.dart';

/// 应用根组件。
///
/// 主题跟着模式走：回响模式用深色（沉浸），清醒模式用暖白（安静）。
/// 这不是"跟随系统"，而是产品语义——两种模式看世界的方式本来就不同。
///
/// 它还负责一件事：**前台心跳**。排期只在 APP 启动时补发是不够的——
/// 用户开着 APP 等十分钟什么都不会发生（这是 2026-09-11 实测发现的缺口）。
/// 所以这里每 30 秒扫一次队列，到点的互动当场兑现。
class EchoApp extends ConsumerStatefulWidget {
  const EchoApp({super.key});

  @override
  ConsumerState<EchoApp> createState() => _EchoAppState();
}

class _EchoAppState extends ConsumerState<EchoApp> {
  /// 前台补发间隔。够快，感觉像"实时"；够慢，不至于每帧都查库。
  static const Duration _flushInterval = Duration(seconds: 30);

  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();
    _heartbeat = Timer.periodic(_flushInterval, (_) async {
      // 出错也不能让心跳断掉：这一次没补上，下一个 30 秒还会再试
      try {
        await ref.read(schedulerServiceProvider).flushDue();
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
    final bootstrap = ref.watch(appBootstrapProvider);

    if (bootstrap.isLoading) {
      return const _Splash();
    }
    if (bootstrap.hasError) {
      return _StartupError(message: '${bootstrap.error}');
    }

    return MaterialApp.router(
      title: '回响 Echo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.clear,
      darkTheme: AppTheme.echo,
      themeMode: mode.isEcho ? ThemeMode.dark : ThemeMode.light,
      routerConfig: appRouter,
      builder: (context, child) {
        // 固定文字缩放，避免系统大字体把信息流卡片挤变形
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: child ?? const SizedBox.shrink(),
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
    return const MaterialApp(
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
                const Icon(Icons.error_outline, color: EchoColors.like, size: 32),
                const SizedBox(height: 14),
                const Text(
                  '本地数据库启动失败',
                  style: TextStyle(color: EchoColors.text, fontSize: 16),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: EchoColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
