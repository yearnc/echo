import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/model_usage_repository.dart';
import 'package:echo/domain/services/model_call_common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ModelUsageRepository usage;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    usage = ModelUsageRepository(db);
  });

  tearDown(() async => db.close());

  test('同一天同一模型累加，不逐次落库', () async {
    await usage.record(
      model: 'deepseek-flash',
      usage: const ModelUsage(
        promptTokens: 1000,
        completionTokens: 100,
        cachedTokens: 800,
      ),
    );
    await usage.record(
      model: 'deepseek-flash',
      usage: const ModelUsage(
        promptTokens: 500,
        completionTokens: 50,
        cachedTokens: 400,
        cacheWriteTokens: 200,
      ),
    );

    final summary = await usage.summary(days: 1);
    expect(summary.calls, 2);
    expect(summary.promptTokens, 1500);
    expect(summary.cachedTokens, 1200);
    expect(summary.cacheWriteTokens, 200);
    expect(summary.completionTokens, 150);
    expect(summary.cacheHitRate, 80);
    expect(summary.byModel.single.model, 'deepseek-flash');
  });

  test('服务商没返回 usage 时不记假数据', () async {
    await usage.record(model: 'x', usage: ModelUsage.zero);
    final summary = await usage.summary(days: 1);
    expect(summary.hasData, isFalse);
    expect(summary.calls, 0);
  });

  test('不同模型分开统计', () async {
    await usage.record(
      model: 'a',
      usage: const ModelUsage(promptTokens: 100, cachedTokens: 50),
    );
    await usage.record(
      model: 'b',
      usage: const ModelUsage(promptTokens: 200, cachedTokens: 200),
    );
    final summary = await usage.summary(days: 7);
    expect(summary.byModel.length, 2);
    expect(summary.cacheHitRate, 83);
  });
}
