/// 临时网民的“常识库”（v3.10）。
///
/// 模型写评论时最缺的不是文采，而是**分寸**：什么时候该接梗、怎么接不尴尬、
/// 什么时候只能陪着、什么时候该闭嘴。这些东西不适合全塞进 system
/// （那里要逐字节稳定，才能命中缓存），所以做成一本按帖子挑几条的小册子，
/// 随每帖的解析结果注入 user 段。
///
/// 不追求“网络梗大全”：写死的梗很快就过时，也会诱导模型硬套。
/// 这里只收**说话方式和禁区**，具体梗交给模型自己判断。
class NetKnowledgeEntry {
  const NetKnowledgeEntry({
    required this.id,
    required this.category,
    required this.note,
    this.tags = const [],
    this.domains = const [],
    this.tones = const [],
  });

  final String id;

  /// 给模型看的小标题：接梗 / 共鸣 / 吐槽 / 提问 / 短评 / 陪伴
  final String category;

  /// 一句话说清怎么做。
  final String note;

  /// 命中关键词时加分。
  final List<String> tags;
  final List<String> domains;
  final List<String> tones;
}

class NetKnowledge {
  const NetKnowledge._();

  /// 内置条目。保持短、可执行；一句一条，别写成教材。
  static const List<NetKnowledgeEntry> entries = [
    NetKnowledgeEntry(
      id: 'joke_follow',
      category: '接梗',
      note: '顺着梗往下说，不要解释这个梗；一解释就冷了。',
      tones: ['玩梗'],
    ),
    NetKnowledgeEntry(
      id: 'joke_reverse',
      category: '接梗',
      note: '先接一句再反转（“确实……就是有点……”），比单纯夸或单纯损自然。',
      tones: ['玩梗', '吐槽'],
    ),
    NetKnowledgeEntry(
      id: 'joke_insider',
      category: '圈内话',
      note: '用圈内的称呼接一句就行；不确定含义就别装懂，改成提问。',
      domains: ['游戏', '行业', '知识'],
    ),
    NetKnowledgeEntry(
      id: 'joke_no_force',
      category: '接梗',
      note: '拿不准就不玩梗。硬造梗比不接梗更尴尬。',
    ),
    NetKnowledgeEntry(
      id: 'echo_concrete',
      category: '共鸣',
      note: '抓一个具体的细节（时间、地点、手上的东西）去共鸣，不要泛泛说“我懂你”。',
      tones: ['分享', '感伤', '日常'],
    ),
    NetKnowledgeEntry(
      id: 'echo_self',
      category: '自嘲',
      note: '拿自己开涮比点评对方安全：“我比你更惨”比“你要想开点”像人话。',
      tones: ['吐槽', '玩梗', '日常'],
    ),
    NetKnowledgeEntry(
      id: 'roast_thing',
      category: '吐槽',
      note: '吐槽事，不吐槽人。可以骂天气、系统、加班、排队。',
      tones: ['吐槽'],
    ),
    NetKnowledgeEntry(
      id: 'ask_small',
      category: '提问',
      note: '问一个对方真能答的小问题（几点、哪家、后来呢），别问人生大道理。',
      tones: ['分享', '知识', '日常'],
    ),
    NetKnowledgeEntry(
      id: 'short_reply',
      category: '短评',
      note: '10—25 字就够。评论区里最像真人的，往往是半句话。',
    ),
    NetKnowledgeEntry(
      id: 'no_advice',
      category: '陪伴',
      note: '对方低落时只陪着：说“在”“我也有过”，不要给方案、不要“加油你可以的”。',
      tones: ['求助', '感伤'],
    ),
    NetKnowledgeEntry(
      id: 'slang_once',
      category: '口语',
      note: '可以偶尔用一个流行词（确实 / 绷不住 / 典 / 上头），一条最多一个。',
    ),
    NetKnowledgeEntry(
      id: 'no_lecture',
      category: '短评',
      note: '不总结、不升华、不说教；别把别人的帖子当成作文题。',
    ),
  ];

  /// 按这一帖的语气、领域和提到的词挑几条；最多 [limit] 条。
  ///
  /// 顺序稳定：先按相关度，再按内置顺序，同样的帖子每次拿到的都是同一批，
  /// 不会让同一帖不同批次的网民前后说法打架。
  static List<NetKnowledgeEntry> pick({
    required String tone,
    required String domain,
    required List<String> entities,
    int limit = 5,
  }) {
    final scored = <(int, int, NetKnowledgeEntry)>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      var score = 0;
      if (entry.tones.any((value) => value.isNotEmpty && tone.contains(value))) {
        score += 3;
      }
      if (entry.domains.any(
        (value) => value.isNotEmpty && domain.contains(value),
      )) {
        score += 2;
      }
      for (final tag in entry.tags) {
        if (entities.any((entity) => entity.contains(tag))) score += 1;
      }
      // 通用条目也参与排序，只是排在贴题的那几条后面。
      scored.add((score, -i, entry));
    }
    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      if (byScore != 0) return byScore;
      return b.$2.compareTo(a.$2);
    });
    return [
      for (final item in scored.take(limit.clamp(1, entries.length))) item.$3,
    ];
  }

  /// 拼成给模型看的一段。没有可用条目时返回空串（调用方就不加这一段）。
  static String blockFor({
    required String tone,
    required String domain,
    required List<String> entities,
    int limit = 5,
  }) {
    final picked = pick(
      tone: tone,
      domain: domain,
      entities: entities,
      limit: limit,
    );
    if (picked.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('【网民的说话方式（参考，别照抄）】');
    for (final entry in picked) {
      buffer.writeln('- ${entry.category}：${entry.note}');
    }
    buffer.write('以上是分寸，不是模板；写出来要像随手打的，不像在完成作业。');
    return buffer.toString();
  }
}
