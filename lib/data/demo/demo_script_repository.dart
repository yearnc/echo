import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/demo_script.dart';

/// 三幕脚本的读取。
///
/// 脚本来自 assets，因此**演示模式永远不需要网络**——
/// 这是微视频拍摄能"稳定、零成本、可重复"的前提。
class DemoScriptRepository {
  const DemoScriptRepository();

  static const List<String> assetPaths = [
    'assets/demo/act1.json',
    'assets/demo/act2.json',
    'assets/demo/act3.json',
  ];

  Future<List<DemoScript>> loadAll() async {
    final scripts = <DemoScript>[];
    for (final path in assetPaths) {
      scripts.add(await _loadOne(path));
    }
    return scripts;
  }

  Future<DemoScript> loadById(String actId) async {
    final path = assetPaths.firstWhere(
      (p) => p.endsWith('$actId.json'),
      orElse: () => assetPaths.first,
    );
    return _loadOne(path);
  }

  Future<DemoScript> _loadOne(String path) async {
    final raw = await rootBundle.loadString(path);
    return DemoScript.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

final demoScriptRepositoryProvider =
    Provider<DemoScriptRepository>((ref) => const DemoScriptRepository());

/// 三幕脚本列表（控制台用）。
final demoScriptsProvider = FutureProvider<List<DemoScript>>(
  (ref) => ref.watch(demoScriptRepositoryProvider).loadAll(),
);

final demoScriptByIdProvider = FutureProvider.family<DemoScript, String>(
  (ref, actId) => ref.watch(demoScriptRepositoryProvider).loadById(actId),
);
