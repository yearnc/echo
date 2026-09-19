import 'dart:convert';

import '../models/ai_persona.dart';
import '../models/model_config.dart';
import '../models/post.dart';
import '../models/resident_post.dart';
import 'model_gateway.dart';

/// 用用户自己的模型写内容。
///
/// **一次请求把这一批住民的评论全写了**，不逐条调用。两个理由：
/// 一次发帖要五到八条评论，逐条就是五到八次往返，又慢又贵；而且同一批一起
/// 写出来的，能互相避开同一句话——"这张天空照真好看"被三个人说，一眼就是假的。
class ModelContentGenerator {
  ModelContentGenerator(this._gateway);

  final ModelGateway _gateway;

  Future<Map<String, String>> comments({
    required ModelConfig config,
    required List<AiPersona> personas,
    required Post post,
  }) async {
    if (personas.isEmpty) return const {};

    final raw = await _gateway.complete(
      config: config,
      messages: [
        {'role': 'system', 'content': systemPrompt(personas)},
        {'role': 'user', 'content': postPrompt(post)},
      ],
      // 这里要的是像人，不是稳定——同一句话被复读才是问题
      temperature: 0.9,
      maxTokens: 800,
      timeout: const Duration(seconds: 25),
    );

    return parseComments(raw, personas);
  }

  /// 住民自己发的动态（B3）。同样是**一次请求写完整批**。
  ///
  /// 跟评论分两个方法而不是揉成一个，是因为口吻不同：评论是接别人的话，
  /// 动态是自己起头。混在一起让模型写，出来的常常是"动态像评论"。
  Future<List<ResidentPostDraft>> residentPosts({
    required ModelConfig config,
    required List<ResidentMoment> moments,
  }) async {
    if (moments.isEmpty) return const [];

    final raw = await _gateway.complete(
      config: config,
      messages: [
        {'role': 'system', 'content': residentSystemPrompt(moments)},
        {'role': 'user', 'content': '请写出这 ${moments.length} 条动态。'},
      ],
      temperature: 0.95,
      maxTokens: 700,
      timeout: const Duration(seconds: 25),
    );

    final contents = parseIndexedContents(raw, moments.length);
    final drafts = <ResidentPostDraft>[];
    for (var i = 0; i < moments.length; i++) {
      final content = contents[i + 1];
      if (content == null) continue;
      drafts.add(
        ResidentPostDraft(
          personaId: moments[i].persona.id,
          content: content,
          topicName: _topicOf(moments[i].persona),
        ),
      );
    }
    return drafts;
  }

  /// 系统提示词：把这批人是谁讲清楚，再说要什么形状的东西。
  ///
  /// 纯函数，单独测。提示词是这一层最容易悄悄退化的东西——
  /// 改一个词、少一行约束，产出的质量就掉一档，而界面上什么都看不出来。
  static String systemPrompt(List<AiPersona> personas) {
    final buffer = StringBuffer()
      ..writeln('你是「回响大学」这个校园社区里的几名普通学生，现在要给同学的一条帖子写评论。')
      ..writeln()
      ..writeln('要点：')
      ..writeln('- 每条 15—60 字，像真人随手打出来的，别端着')
      ..writeln('- 不复述帖子内容，不用「加油哦」「太棒了」这种谁都能说的话')
      ..writeln('- 不要提到自己是 AI，不要解释自己在做什么')
      ..writeln('- 同一批评论之间不要雷同，也不要点评彼此')
      ..writeln()
      ..writeln('这次要评论的人：');

    for (var i = 0; i < personas.length; i++) {
      final persona = personas[i];
      buffer
        ..writeln('[${i + 1}] ${persona.name}')
        ..writeln('    身份：${persona.personalityType}｜${persona.bio}')
        ..writeln('    说话方式：${persona.languageStyle}')
        ..writeln('    语气要求：${persona.tone}');
    }

    buffer
      ..writeln()
      ..writeln('只输出一个 JSON 数组，不要代码块、不要任何解释：')
      ..writeln('[{"index": 1, "content": "评论内容"}, ...]');

    return buffer.toString();
  }

  /// 住民自己发动态的提示词。
  static String residentSystemPrompt(List<ResidentMoment> moments) {
    final buffer = StringBuffer()
      ..writeln('你是「回响大学」这个校园社区里的几名学生，现在要各自发一条自己的动态（不是评论别人）。')
      ..writeln()
      ..writeln('要点：')
      ..writeln('- 每条 15—60 字，像随手发的，别写成小作文')
      ..writeln('- 内容要和发布时刻相符：清晨、中午、深夜发的东西不一样')
      ..writeln('- 不要提到自己是 AI，不要解释自己在做什么')
      ..writeln('- 几条之间不要雷同')
      ..writeln()
      ..writeln('这次要发动态的人：');

    for (var i = 0; i < moments.length; i++) {
      final moment = moments[i];
      final persona = moment.persona;
      buffer
        ..writeln(
          '[${i + 1}] ${persona.name}'
          '（${persona.circle.isEmpty ? '同校圈' : persona.circle}）',
        )
        ..writeln('    身份：${persona.personalityType}｜${persona.bio}')
        ..writeln('    说话方式：${persona.languageStyle}');
      if (persona.routines.isNotEmpty) {
        buffer.writeln('    平常这个点在：${_routineHint(persona, moment.at)}');
      }
      buffer.writeln('    发布时刻：${momentLabel(moment.at)}');
    }

    buffer
      ..writeln()
      ..writeln('只输出一个 JSON 数组，不要代码块、不要任何解释：')
      ..writeln('[{"index": 1, "content": "动态内容"}, ...]');

    return buffer.toString();
  }

  /// 把时刻说成人话。
  ///
  /// 只给 "13:20" 模型不一定反应得过来这是午休时间，所以带上时段。
  static String momentLabel(DateTime at) {
    final hour = at.hour;
    final phase = switch (hour) {
      >= 5 && < 8 => '清晨',
      >= 8 && < 11 => '上午',
      >= 11 && < 14 => '中午',
      >= 14 && < 17 => '下午',
      >= 17 && < 19 => '傍晚',
      >= 19 && < 23 => '晚上',
      _ => '深夜',
    };
    final hh = hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '${at.month}月${at.day}日 $phase $hh:$mm';
  }

  /// 这个点他大概在哪、在干嘛；没有作息就返回一句空的占位。
  static String _routineHint(AiPersona persona, DateTime at) {
    for (final routine in persona.routines) {
      if ((routine.hour - at.hour).abs() > 1) continue;
      if (routine.place.isEmpty) return routine.activity;
      return '${routine.place}，${routine.activity}';
    }
    return '没什么固定安排';
  }

  static String? _topicOf(AiPersona persona) =>
      persona.circle.isEmpty ? null : persona.circle;

  /// 用户提示词：帖子本身。图片只报张数——多模态等 B8 之后再说，
  /// 眼下不假装模型看得见图。
  static String postPrompt(Post post) {
    final buffer = StringBuffer()
      ..writeln('帖子正文：')
      ..writeln(post.content);

    final topic = post.topicName;
    if (topic != null && topic.trim().isNotEmpty) {
      buffer.writeln('（话题：#$topic）');
    }
    if (post.hasImages) {
      buffer.writeln('（这条帖子还带了 ${post.images.length} 张图）');
    }
    return buffer.toString();
  }

  /// 把模型返回的 JSON 数组解成「住民 id → 内容」。
  static Map<String, String> parseComments(
    String raw,
    List<AiPersona> personas,
  ) {
    final byIndex = parseIndexedContents(raw, personas.length);
    return {
      for (final entry in byIndex.entries)
        personas[entry.key - 1].id: entry.value,
    };
  }

  /// 把 `[{"index": 1, "content": "..."}]` 解成 编号 → 内容（编号从 1 起）。
  ///
  /// 认不出来的条目一律**丢掉**（调用方会用样本补上），绝不猜——
  /// 把 A 的话挂在 B 名下，比这条没生成出来糟糕得多。
  static Map<int, String> parseIndexedContents(String raw, int count) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return const {};

    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is! List) return const {};

      final byIndex = <int, String>{};
      for (final item in decoded) {
        if (item is! Map) continue;

        // 用 is 判断而不是 as：模型偶尔把编号写成字符串、把内容写成数字，
        // 一次类型转换失败会端掉整批（异常落到外层 catch），而这里只想跳过这一条
        final indexRaw = item['index'];
        final contentRaw = item['content'];
        final index = indexRaw is num ? indexRaw.toInt() : null;
        final content = contentRaw is String ? contentRaw.trim() : null;
        if (index == null || content == null || content.isEmpty) continue;
        // 模型可能自己加几个人，或者把编号写飞；越界的一律不要
        if (index < 1 || index > count) continue;

        byIndex[index] = content;
      }
      return byIndex;
    } catch (_) {
      return const {};
    }
  }
}
