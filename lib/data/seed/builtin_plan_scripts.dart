import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/models/plan_script.dart';

/// 把原来的三幕演示脚本（`assets/demo/act1~3.json`）转成策划脚本。
///
/// 只保留**属于这条帖子的**事件：评论、点赞、设定计数，以及清醒模式要用的
/// 客观分析。其余一律丢弃——包括切模式、跳页面这两类。
///
/// 原因见 `PlanStepType` 的注释：策划模式只安排"这条帖子会收到什么回应"，
/// 不操控 APP 的其他状态。所以第三幕的"切到清醒模式""打开价值澄清"
/// 现在都靠人手动完成——那几步本来就该是真实操作。
///
/// 幕标题、解说字幕、进度条、引导卡这些**拍摄专用装饰**同样丢弃：
/// 策划模式下画面里就是 APP 本身，没有舞台。
///
/// 第三幕的 `postRef: act1` 在这里被展开成第一幕的开局内容：
/// "同一张照片"是那一幕的关键，所以它必须能直接填进发布页。
class BuiltinPlanScripts {
  const BuiltinPlanScripts._();

  static const List<String> _assets = [
    'assets/demo/act1.json',
    'assets/demo/act2.json',
    'assets/demo/act3.json',
  ];

  static const Set<String> _keptTypes = {
    PlanStepType.comment,
    PlanStepType.likeBurst,
    PlanStepType.stats,
    PlanStepType.analysis,
  };

  static const Map<String, String> _names = {
    'act1': '第一幕 · 天空照',
    'act2': '第二幕 · 深夜垃圾桶',
    // 名字里不再提"切清醒模式"——那一步现在由人在拍摄时手动做
    'act3': '第三幕 · 同一张天空照',
  };

  static Future<List<PlanScript>> load() async {
    final raws = <Map<String, dynamic>>[];
    for (final path in _assets) {
      final raw = await rootBundle.loadString(path);
      raws.add(jsonDecode(raw) as Map<String, dynamic>);
    }

    // 先收集每一幕自己的帖子，供 postRef 展开用
    final postByAct = <String, Map<String, dynamic>>{};
    for (final raw in raws) {
      final post = raw['post'] as Map<String, dynamic>?;
      if (post != null) postByAct[raw['id'] as String] = post;
    }

    return raws.map((raw) => _convert(raw, postByAct)).toList(growable: false);
  }

  static PlanScript _convert(
    Map<String, dynamic> raw,
    Map<String, Map<String, dynamic>> postByAct,
  ) {
    final actId = raw['id'] as String? ?? 'act';
    final ownPost = raw['post'] as Map<String, dynamic>?;
    final refId = raw['postRef'] as String?;
    final post = ownPost ?? (refId == null ? null : postByAct[refId]);

    final rawSteps = [
      ...(raw['preSteps'] as List<dynamic>? ?? const []),
      ...(raw['steps'] as List<dynamic>? ?? const []),
    ];

    final steps = <PlanStep>[];
    for (final item in rawSteps) {
      if (item is! Map<String, dynamic>) continue;
      final type = item['type'] as String? ?? '';
      if (!_keptTypes.contains(type)) continue;
      steps.add(PlanStep.fromJson(item));
    }
    steps.sort((a, b) => (a.rangeMs?.$1 ?? 0).compareTo(b.rangeMs?.$1 ?? 0));

    return PlanScript(
      id: 'builtin_$actId',
      name: _names[actId] ?? (raw['title'] as String? ?? '未命名脚本'),
      isBuiltIn: true,
      postContent: post?['content'] as String? ?? '',
      postImages: (post?['images'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(growable: false),
      topicName: post?['topicName'] as String?,
      steps: steps,
    );
  }
}
