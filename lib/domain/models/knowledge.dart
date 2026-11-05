import 'dart:convert';

/// 知识库的归属与可见性（v4.11）。
///
/// 两件事刻意分开：
/// - **内容**（[KnowledgeEntry]）只负责"这是什么、从哪来、怎么用"；
/// - **归属**（[KnowledgeBase] + [KnowledgeTarget]）决定"谁看得到"。
///
/// 混在一起会让"给某位住民加一条梗"变成"改所有网民的提示词"，
/// 缓存和权限都会跟着乱。
enum KnowledgeScope {
  independent('independent', '独立知识库'),
  shared('shared', '共享知识库');

  const KnowledgeScope(this.key, this.label);

  final String key;
  final String label;

  static KnowledgeScope fromKey(String? raw) => values.firstWhere(
    (scope) => scope.key == raw,
    orElse: () => KnowledgeScope.independent,
  );
}

/// 独立库的归属：只服务临时网民，或只服务某一位固定住民。
enum KnowledgeOwnerKind {
  transient('transient', '只服务临时网民'),
  resident('resident', '只服务固定住民');

  const KnowledgeOwnerKind(this.key, this.label);

  final String key;
  final String label;

  static KnowledgeOwnerKind fromKey(String? raw) => values.firstWhere(
    (kind) => kind.key == raw,
    orElse: () => KnowledgeOwnerKind.transient,
  );
}

/// 共享库的服务对象。
///
/// 临时网民没有持久身份，"全体网民"是唯一合理的粒度；
/// 固定住民既可以全军覆没，也可以逐个点名。
enum KnowledgeTargetKind {
  transientAll('transient_all', '全体临时网民'),
  residentAll('resident_all', '全体固定住民'),
  resident('resident', '指定固定住民');

  const KnowledgeTargetKind(this.key, this.label);

  final String key;
  final String label;

  static KnowledgeTargetKind fromKey(String? raw) => values.firstWhere(
    (kind) => kind.key == raw,
    orElse: () => KnowledgeTargetKind.residentAll,
  );
}

class KnowledgeBase {
  const KnowledgeBase({
    required this.id,
    required this.name,
    required this.scope,
    required this.ownerKind,
    this.description = '',
    this.ownerResidentId = '',
    this.builtin = false,
    this.enabled = true,
    this.autoUpdate = false,
    this.lastUpdatedAt = 0,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final String id;
  final String name;
  final String description;
  final KnowledgeScope scope;
  final KnowledgeOwnerKind ownerKind;

  /// scope = independent && ownerKind = resident 时有效。
  final String ownerResidentId;

  /// 内置库不可删除；条目仍可编辑。
  final bool builtin;
  final bool enabled;

  /// 是否允许系统每周自动更新。
  final bool autoUpdate;
  final int lastUpdatedAt;
  final int createdAt;
  final int updatedAt;

  bool get isShared => scope == KnowledgeScope.shared;
  bool get servesTransient =>
      scope == KnowledgeScope.independent &&
      ownerKind == KnowledgeOwnerKind.transient;

  KnowledgeBase copyWith({
    String? name,
    String? description,
    KnowledgeScope? scope,
    KnowledgeOwnerKind? ownerKind,
    String? ownerResidentId,
    bool? builtin,
    bool? enabled,
    bool? autoUpdate,
    int? lastUpdatedAt,
    int? updatedAt,
  }) => KnowledgeBase(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    scope: scope ?? this.scope,
    ownerKind: ownerKind ?? this.ownerKind,
    ownerResidentId: ownerResidentId ?? this.ownerResidentId,
    builtin: builtin ?? this.builtin,
    enabled: enabled ?? this.enabled,
    autoUpdate: autoUpdate ?? this.autoUpdate,
    lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class KnowledgeEntry {
  const KnowledgeEntry({
    required this.id,
    required this.baseId,
    required this.title,
    this.summary = '',
    this.content = '',
    this.examples = const [],
    this.tags = const [],
    this.sourceUrl = '',
    this.sourceTitle = '',
    this.verifiedAt = 0,
    this.expiresAt = 0,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final String id;
  final String baseId;
  final String title;

  /// 一句话索引：常驻提示词的就是它。
  final String summary;

  /// 正文：来源、用处、例子。
  final String content;
  final List<String> examples;
  final List<String> tags;
  final String sourceUrl;
  final String sourceTitle;
  final int verifiedAt;

  /// 0 = 不过期。
  final int expiresAt;
  final int createdAt;
  final int updatedAt;

  bool expiredAt(DateTime now) =>
      expiresAt > 0 && expiresAt <= now.millisecondsSinceEpoch;

  /// 给模型看的完整一段。来源单独成行：模型可以转述，但不该把 URL 抄进评论。
  String toPromptBlock() {
    final buffer = StringBuffer()..write('- $title');
    if (summary.trim().isNotEmpty) buffer.write('：${summary.trim()}');
    final body = content.trim();
    if (body.isNotEmpty) buffer.write('\n  $body');
    if (examples.isNotEmpty) {
      buffer.write('\n  例子：${examples.take(3).map((e) => '「$e」').join(' ')}');
    }
    if (sourceTitle.trim().isNotEmpty || sourceUrl.trim().isNotEmpty) {
      final source = [
        if (sourceTitle.trim().isNotEmpty) sourceTitle.trim(),
        if (sourceUrl.trim().isNotEmpty) sourceUrl.trim(),
      ].join(' · ');
      buffer.write('\n  来源：$source');
    }
    return buffer.toString();
  }

  /// 给列表页的一行。
  String get exampleLine => examples.take(2).join(' / ');

  static List<String> decodeList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [
          for (final item in decoded)
            if (item is String && item.trim().isNotEmpty) item.trim(),
        ];
      }
    } catch (_) {
      // 老数据或手写坏了：按换行拆，至少不丢内容。
    }
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }
}

class KnowledgeTarget {
  const KnowledgeTarget({
    required this.baseId,
    required this.kind,
    this.targetId = '',
  });

  final String baseId;
  final KnowledgeTargetKind kind;
  final String targetId;

  @override
  bool operator ==(Object other) =>
      other is KnowledgeTarget &&
      other.baseId == baseId &&
      other.kind == kind &&
      other.targetId == targetId;

  @override
  int get hashCode => Object.hash(baseId, kind, targetId);
}
