import 'package:drift/drift.dart';

/// 每天的模型用量（v4.5 / schema v48）。
///
/// 只记 token 计数，不记任何消息正文：用来在「我的」页展示缓存命中率。
/// 按“天 + 模型”聚合，不逐次落库，避免数据库被调用记录撑大。
@DataClassName('ModelUsageDailyRow')
@TableIndex(name: 'model_usage_daily_day', columns: {#day})
class ModelUsageDaily extends Table {
  /// `yyyy-MM-dd|model`
  TextColumn get id => text()();
  TextColumn get day => text()();
  TextColumn get model => text()();

  IntColumn get calls => integer().withDefault(const Constant(0))();
  IntColumn get promptTokens => integer().withDefault(const Constant(0))();
  IntColumn get cachedTokens => integer().withDefault(const Constant(0))();
  IntColumn get cacheWriteTokens => integer().withDefault(const Constant(0))();
  IntColumn get completionTokens => integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
