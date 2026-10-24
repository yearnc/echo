import 'dart:convert';

/// 一条分析维度。
///
/// `value` 是给人看的结论（“近 7 天发了 6 条”），`detail` 是可核对的来源
/// （“来自 posts：scope=clear 且作者是我”）。页面不展示安慰性的形容，
/// 只展示能回到具体记录的数字。
class ClearInsightMetric {
  const ClearInsightMetric({
    required this.id,
    required this.label,
    required this.value,
    this.detail = '',
    this.source = 'real',
  });

  final String id;
  final String label;
  final String value;
  final String detail;

  /// real = 本机真实记录；ai = 将来接模型生成时的标记。
  final String source;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'value': value,
    'detail': detail,
    'source': source,
  };

  factory ClearInsightMetric.fromJson(Map<String, dynamic> json) =>
      ClearInsightMetric(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        value: json['value'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        source: json['source'] as String? ?? 'real',
      );
}

/// 一次清醒分析（按维度）。
class ClearInsight {
  const ClearInsight({
    required this.generatedAt,
    required this.periodStart,
    required this.periodEnd,
    required this.metrics,
    this.summary = '',
    this.source = 'real',
  });

  final DateTime generatedAt;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String summary;
  final List<ClearInsightMetric> metrics;
  final String source;

  String encodePayload() =>
      jsonEncode([for (final metric in metrics) metric.toJson()]);

  static List<ClearInsightMetric> decodePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>)
            ClearInsightMetric.fromJson(item)
          else if (item is Map)
            ClearInsightMetric.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 给朗读用的纯文本：一句话结论 + 每个维度的结论。
  String toSpeechText() {
    final buffer = StringBuffer();
    if (summary.trim().isNotEmpty) buffer.write(summary.trim());
    for (final metric in metrics) {
      if (buffer.isNotEmpty) buffer.write('；');
      buffer.write('${metric.label}：${metric.value}');
    }
    final text = buffer.toString();
    return text.length <= 180 ? text : '${text.substring(0, 180)}…';
  }
}
