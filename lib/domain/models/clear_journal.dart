/// 清醒模式的两类产出（规划书 §4）。
///
/// 回响模式生产的是**别人给的反应**，这里生产的是**自己想清楚的事**
/// 和**真正做过的事**——价值重建闭环的两端。
library;

/// 用户写下的一条「我真正重视的事」。
///
/// 不设"重要程度"字段：排序本身就是权重，[sortOrder] 越小越靠前。
class ValueItem {
  const ValueItem({
    required this.id,
    required this.content,
    required this.sortOrder,
    required this.createdAt,
  });

  final String id;
  final String content;
  final int sortOrder;

  /// 领域模型里统一用 [DateTime]（库里存毫秒），与 Post 等模型保持一致。
  final DateTime createdAt;

  ValueItem copyWith({String? content, int? sortOrder}) => ValueItem(
    id: id,
    content: content ?? this.content,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
  );
}

/// 真实行动的分类（规划书 §4：「线下行动、运动、阅读、社交、创作」）。
///
/// `other` 是兜底而不是"没分类"：写下来的每件事都该被归到某处，
/// 否则周报统计会出现一块说不清的去处。
enum RealActionCategory {
  sport('运动'),
  reading('阅读'),
  social('社交'),
  creation('创作'),
  other('其他');

  const RealActionCategory(this.label);

  final String label;

  String get id => name;

  static RealActionCategory fromId(String? id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => RealActionCategory.other,
  );
}

/// 记下这件事时的心情（B11：给周报补上情绪这一维）。
///
/// **可空**——不强迫每次都记。心情是顺手写一笔的东西，一旦每次都被要求
/// 选一个，它很快变成负担，然后就没有人再记了。
enum RealActionMood {
  steady('踏实'),
  happy('开心'),
  calm('平静'),
  tired('有点累'),
  low('低落');

  const RealActionMood(this.label);

  final String label;

  String get id => name;

  static RealActionMood? fromId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final mood in values) {
      if (mood.id == id) return mood;
    }
    return null;
  }
}

/// 数一数这些心情各出现了几次，从多到少。
///
/// 次数相同的按枚举顺序排——不用随机、不用哈希，
/// 同一周的记录每次看都该是同一个顺序。
List<(RealActionMood, int)> tallyMoods(List<RealActionMood> moods) {
  final counts = <RealActionMood, int>{};
  for (final mood in moods) {
    counts[mood] = (counts[mood] ?? 0) + 1;
  }

  final entries = [
    for (final mood in RealActionMood.values)
      if (counts[mood] != null) (mood, counts[mood]!),
  ];
  entries.sort((a, b) => b.$2.compareTo(a.$2));
  return entries;
}

/// 一条真实行动记录。
class RealAction {
  const RealAction({
    required this.id,
    required this.title,
    this.description = '',
    this.category = RealActionCategory.other,
    this.mood,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String description;
  final RealActionCategory category;

  /// 做这件事时的心情；null 表示没记。
  final RealActionMood? mood;

  final DateTime createdAt;
}
