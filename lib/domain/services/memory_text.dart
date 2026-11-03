/// 记忆文本的规范化、指纹、相似度与写入门。
///
/// 全部是纯函数：不读数据库、不调模型、不依赖时间，方便单测和回放。
/// 参考 DeepSeek-memory-Ido1um 的做法：
/// - 先剥掉标点和中文虚词，再算指纹；
/// - 用 2-gram Jaccard 判断“换了个说法”的重复；
/// - 写入门只挡明显不该进长期库的内容，宁可漏、不误记。
library;

/// 标点、空白与全角符号。中文记忆里这些不携带语义。
final RegExp _punctuation = RegExp(
  r'''[\s，。！？；、,.!?;:"“”‘’（）()【】\[\]{}<>《》…—\-~～·]''',
);

/// 语气词/结构助词。剥掉后“他喜欢喝茉莉花茶”和“他喜欢喝茉莉花茶呀”会落在同一串。
final RegExp _particles = RegExp(r'[吧呀啊哦呢哈嘛啦著着了]');
final RegExp _fillers = RegExp(r'[要得就还都也]');

/// 系统自动加的人称/渠道前缀。比较相似度前先去掉，避免“他回我：X”和“X”被当成两件事。
/// 记忆摘要基本都是“他/对方/你 + 发生了什么”，比较时把开头的人称一并当噪声。
final RegExp _leadPrefix = RegExp(
  r'^(他|对方|你)(发过一条带图的帖子|发过一条帖子|私信你|回我|说|告诉我)?[:：]?',
);

/// 规范化：只服务于比较和指纹，不用于展示。
String normalizeMemoryText(String text) {
  var value = text.trim().toLowerCase();
  value = value.replaceFirst(_leadPrefix, '');
  value = value.replaceAll(_punctuation, '');
  value = value.replaceAll(_particles, '');
  value = value.replaceAll(_fillers, '');
  return value.trim();
}

/// 32 位 FNV-1a。只做去重键，不需要密码学强度。
String memoryFingerprint(String text) {
  var hash = 0x811c9dc5;
  for (final code in normalizeMemoryText(text).codeUnits) {
    hash ^= code;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// 中文 2-gram 集合。单字查询生成不出来时保留原串。
Set<String> memoryBigrams(String text) {
  final runes = normalizeMemoryText(text).runes.toList(growable: false);
  if (runes.length < 2) {
    return {if (runes.isNotEmpty) String.fromCharCode(runes.first)};
  }
  return {
    for (var i = 0; i + 1 < runes.length; i++)
      String.fromCharCodes(runes.sublist(i, i + 2)),
  };
}

/// Jaccard 相似度：交集 ÷ 并集，0—1。
double memorySimilarity(String a, String b) {
  final first = memoryBigrams(a);
  final second = memoryBigrams(b);
  if (first.isEmpty || second.isEmpty) return 0;
  var intersection = 0;
  for (final gram in first) {
    if (second.contains(gram)) intersection++;
  }
  return intersection / (first.length + second.length - intersection);
}

/// 两条记忆是不是同一件事。
///
/// [tags] 有交集时视为同一主题，阈值放宽到 0.6（和参考项目一致）；
/// 没有共同标签时用 0.72，并额外允许“只差一个渠道前缀”的包含关系。
bool isDuplicateMemory({
  required String summary,
  String content = '',
  List<String> tags = const [],
  required String otherSummary,
  String otherContent = '',
  List<String> otherTags = const [],
}) {
  final a = normalizeMemoryText(summary);
  final b = normalizeMemoryText(otherSummary);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;

  final longer = a.length >= b.length ? a : b;
  final shorter = a.length >= b.length ? b : a;
  final sameTopic = tags.any(
    (tag) => otherTags.any((other) => tag.trim() == other.trim()),
  );

  // 完全包含：短句至少 8 个字、覆盖长句的七成，才是同一件事。
  // 再对照正文，避免“喝茶”和“喝茉莉花茶”这种包含关系被误判。
  if (longer.contains(shorter) &&
      shorter.length >= 8 &&
      shorter.length / longer.length >= 0.7) {
    if (sameTopic) return true;
    final aContent = normalizeMemoryText(content);
    final bContent = normalizeMemoryText(otherContent);
    if (aContent.isNotEmpty &&
        bContent.isNotEmpty &&
        (aContent.contains(bContent) || bContent.contains(aContent))) {
      return true;
    }
  }

  final threshold = sameTopic ? 0.6 : 0.72;
  return memorySimilarity(a, b) >= threshold;
}

/// 写入闸门：返回空串表示放行，否则是给模型看的原因。
///
/// 只挡“明显不该进长期库”的，不追求把候选清空：
/// 太短、寒暄/临时状态、图片占位、技术/元讨论、不确定的推测。
String memoryWriteGate({required String summary, String content = ''}) {
  final text = summary.trim();
  final body = content.trim();
  final whole = text.isEmpty ? body : text;
  if (whole.length < 4) return '太短了，记了也用不上';

  if (RegExp(r'^(你好|在吗|晚安|早安|午安|哈哈|嘿嘿|谢谢|好的|收到|没事|吃了吗|睡了吗)').hasMatch(whole)) {
    return '寒暄和临时状态不值得长期记';
  }

  if (RegExp(r'^(他|对方)?(发来|发了)?(一张|一个)?(图片|照片|表情包)[。！!]?$').hasMatch(whole)) {
    return '“发来一张图片”没有信息；图片里是什么才值得记';
  }

  if (RegExp(
    r'(记忆系统|提示词|工具调用|系统提示|数据库|代码|bug|修复|配置|仓库|readme)',
    caseSensitive: false,
  ).hasMatch(whole)) {
    return '这是关于系统本身的技术讨论，不是关于对方的长期事实';
  }

  if (RegExp(r'^(可能|也许|好像|大概|说不定|估计|不确定|记不清|听说)').hasMatch(whole) ||
      RegExp(r'(可能|也许|好像|大概|说不定|估计|不确定|记不清|听说)')
          .hasMatch(whole)) {
    return '不确定或听说的内容先别记；等确认了再写';
  }

  return '';
}
