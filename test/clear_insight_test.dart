import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/addiction_repository.dart';
import 'package:echo/data/repositories/clear_insight_repository.dart';
import 'package:echo/data/repositories/clear_journal_repository.dart';
import 'package:echo/data/repositories/dashboard_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/usage_repository.dart';
import 'package:echo/domain/models/clear_journal.dart';
import 'package:echo/domain/services/clear_insight_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PostRepository posts;
  late ClearJournalRepository journal;
  late UsageRepository usage;
  late ClearInsightService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    posts = PostRepository(db);
    journal = ClearJournalRepository(db);
    usage = UsageRepository(db);
    service = ClearInsightService(
      dashboard: DashboardRepository(db),
      journal: journal,
      addiction: AddictionRepository(db),
      usage: usage,
      insights: ClearInsightRepository(db),
    );
  });

  tearDown(() async => db.close());

  test('没有任何记录时不出假分析', () async {
    expect(await service.compute(), isNull);
  });

  test('有记录时按维度算出可追溯的数字', () async {
    final postId = await posts.create(content: '今天走了很久', scope: 'clear');
    await journal.addAction(
      title: '跑了两公里',
      category: RealActionCategory.sport,
      mood: RealActionMood.calm,
    );
    await db
        .into(db.aiInteractions)
        .insert(
          AiInteractionsCompanion.insert(
            id: 'ai1',
            postId: postId,
            personaId: 'voice_1',
            type: 'comment',
            scheduledAt: DateTime.now().millisecondsSinceEpoch,
            status: const Value('done'),
            content: const Value('挺好的'),
          ),
        );

    final insight = await service.compute();
    expect(insight, isNotNull);
    expect(insight!.source, 'real');
    expect(insight.summary, contains('写下 1 条记录'));
    expect(insight.summary, contains('1 次 AI 回应'));
    expect(insight.summary, contains('线下记下 1 件'));

    final byId = {for (final metric in insight.metrics) metric.id: metric};
    expect(byId['posting']!.value, contains('1 条记录'));
    expect(byId['feedback']!.value, contains('1 条评论'));
    expect(byId['ai_share']!.value, contains('全部由 AI 生成'));
    expect(byId['mood']!.value, contains('平静'));
  });

  test('跨天使用会话按自然日拆开', () async {
    await usage.logSession(
      start: DateTime(2026, 10, 23, 23, 30),
      end: DateTime(2026, 10, 24, 0, 30),
    );

    final rows = await usage.all();
    expect(rows, hasLength(2), reason: '跨夜的一小时要拆成两天');
    final total = rows.fold<int>(0, (sum, row) => sum + row.durationMs);
    expect(total, const Duration(minutes: 60).inMilliseconds);
  });
}
