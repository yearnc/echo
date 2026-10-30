import 'package:drift/drift.dart';

/// 固定住民的**唯一上下文时间线**（v4.5 / schema v47）。
///
/// 屏幕观察和私信以前是两套各自组装的 messages：私信只取最近 10 句、
/// 屏幕上下文只留 12 行，两边还要靠一块内存白板互相“打听”。这里改成
/// 一条只追加的持久时间线：看到什么、说过什么、对方说了什么，全按发生
/// 顺序写进来；每次醒来从同一条线组装消息。
///
/// 只追加是硬要求：缓存命中靠前缀逐字节稳定。新事件只能长在末尾，
/// 不许回头改旧行；旧到一定程度由高水位摘要统一压缩一次。
@DataClassName('ResidentContextEventRow')
@TableIndex(name: 'resident_context_events_id', columns: {#id}, unique: true)
@TableIndex(
  name: 'resident_context_events_resident',
  columns: {#residentId, #seq},
)
class ResidentContextEvents extends Table {
  /// 单调递增的本地顺序。组装消息只认它，不按时间戳重排——
  /// 后补进来的私信要落在末尾，否则前面的前缀一变，缓存全断。
  IntColumn get seq => integer().autoIncrement()();

  /// 幂等键：`dm:<messageId>` / `screen:<micros>` / `bubble:<micros>` /
  /// `summary:<micros>`。重复同步不会写两遍。
  TextColumn get id => text()();
  TextColumn get residentId => text()();

  /// dm_in / dm_out / screen / bubble / action / summary
  TextColumn get kind => text()();

  /// user / assistant —— 摘要也走 user（避免服务商拒绝中途的 system）。
  TextColumn get role => text()();

  /// 已经带好时间前缀的正文，直接进模型上下文。
  TextColumn get content => text()();
  TextColumn get caption => text().withDefault(const Constant(''))();

  /// 供调试用的来源标记（消息 id、工具名、触发方式）。
  TextColumn get meta => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();

  /// 被摘要吃掉的时间；仍留在库里，但不再进上下文。
  IntColumn get compactedAt => integer().nullable()();

  /// 粗估 token，组装时用它判断高水位。
  IntColumn get tokens => integer().withDefault(const Constant(0))();
}
