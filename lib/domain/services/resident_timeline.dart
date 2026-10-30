import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/private_message_repository.dart';
import '../models/model_config.dart';
import '../models/private_message.dart';
import 'model_gateway.dart';

/// 固定住民的唯一上下文时间线（v4.5 / schema v47）。
///
/// 参考 Open-ClaudeCode 的做法：一条持久、只追加的会话记录；system 前缀
/// 稳定、历史只往后长，缓存才命得中。只有到上下文窗口的高水位才做一次
/// “摘要 + 保留最近一段”，平时绝不回头改旧消息。
///
/// 这里不保存模型的原始 tool_calls / tool 结果：那些只在当轮有效，
/// 落盘既贵又容易和下一轮的服务商格式打架。真正需要跨轮记得的事，
/// 以 screen / bubble / action / dm 事件各写一行。
class ResidentTimeline {
  ResidentTimeline(this._db, this._messages, this._gateway);

  final AppDatabase _db;
  final PrivateMessageRepository _messages;
  final ModelGateway _gateway;

  /// 没说的时候按 128k 上下文窗口算。模型名里写了 32k / 128k 之类的以它为准。
  static const int defaultContextWindow = 128 * 1024;

  /// 到窗口的 85% 才压缩，给输出和系统提示词留余量。
  static const double compactRatio = 0.85;

  /// 压缩时保留最近约 30% 的逐字上下文，前面才会被摘要吃掉。
  static const double keepRatio = 0.30;

  /// 压缩后的摘要最多写这么多 token。宁可长一点，也不要把经历丢了。
  static const int summaryMaxTokens = 8192;

  static const String _watermarkPrefix = 'resident.context.watermark.';

  final Set<String> _compacting = {};

  // ---------------------------------------------------------------------------
  // 写入
  // ---------------------------------------------------------------------------

  /// 把已经出现的私信同步进时间线。
  ///
  /// 不用 `recentTurns` 的条数限制：**从水位往后全部补进来**，
  /// 已有的靠事件 id 幂等忽略。后补的消息落在末尾，前缀不会被动过。
  Future<void> syncMessages(String residentId) async {
    try {
      final watermark = await _readWatermark(residentId);
      final turns = await _messages.turnsSince(
        residentId,
        afterMs: watermark,
      );
      if (turns.isEmpty) return;
      var maxMs = watermark;
      for (final turn in turns) {
        // `fromMe` 是“我（用户）发的”。对住民来说正好相反：
        // 用户说的话是收到的消息，住民自己说的话才是 assistant。
        await _append(
          id: 'dm:${turn.id}',
          residentId: residentId,
          kind: turn.fromMe ? 'dm_in' : 'dm_out',
          role: turn.fromMe ? 'user' : 'assistant',
          content: _dmLine(turn),
          caption: turn.caption,
          at: turn.createdAt,
          meta: 'message:${turn.id}',
        );
        if (turn.createdAt.millisecondsSinceEpoch > maxMs) {
          maxMs = turn.createdAt.millisecondsSinceEpoch;
        }
      }
      // 下次从 >= 水位查；同一毫秒的重复消息会被 id 幂等挡住。
      await _writeWatermark(residentId, maxMs);
    } catch (error) {
      debugPrint('[上下文] 同步私信没成：$error');
    }
  }

  Future<void> appendScreen(
    String residentId, {
    required String content,
    required DateTime at,
    String caption = '',
    String meta = '',
  }) => _append(
    id: 'screen:$residentId:${at.microsecondsSinceEpoch}',
    residentId: residentId,
    kind: 'screen',
    role: 'user',
    content: content,
    caption: caption,
    at: at,
    meta: meta,
  );

  Future<void> appendBubble(
    String residentId, {
    required String content,
    required DateTime at,
  }) => _append(
    id: 'bubble:$residentId:${at.microsecondsSinceEpoch}',
    residentId: residentId,
    kind: 'bubble',
    role: 'assistant',
    content: '[${_timeLabel(at)}] 你在屏幕上说：“$content”',
    at: at,
  );

  Future<void> appendAction(
    String residentId, {
    required String content,
    required DateTime at,
    String meta = '',
  }) => _append(
    id: 'action:$residentId:${at.microsecondsSinceEpoch}:${meta.hashCode}',
    residentId: residentId,
    kind: 'action',
    role: 'assistant',
    content: '[${_timeLabel(at)}] 你做了：$content',
    at: at,
    meta: meta,
  );

  Future<void> _append({
    required String id,
    required String residentId,
    required String kind,
    required String role,
    required String content,
    required DateTime at,
    String caption = '',
    String meta = '',
  }) async {
    final clean = content.trim();
    if (clean.isEmpty) return;
    await _db
        .into(_db.residentContextEvents)
        .insert(
          ResidentContextEventsCompanion.insert(
            id: id,
            residentId: residentId,
            kind: kind,
            role: role,
            content: clean,
            caption: Value(caption.trim()),
            meta: Value(meta),
            createdAt: at.millisecondsSinceEpoch,
            tokens: Value(estimateTokens('$clean $caption')),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  // ---------------------------------------------------------------------------
  // 读取
  // ---------------------------------------------------------------------------

  /// 给「住民的上下文」页看：包含已经被压缩的旧事件，方便知道发生过什么。
  Stream<List<ResidentContextEventRow>> watchEvents(String residentId) {
    return (_db.select(_db.residentContextEvents)
          ..where((t) => t.residentId.equals(residentId))
          ..orderBy([(t) => OrderingTerm.desc(t.seq)]))
        .watch();
  }

  /// 清空一位住民的上下文。**只清时间线**，不碰长期记忆、私信原文和帖子。
  ///
  /// 水位推到“现在”：清空后不会把旧私信重新灌回来；
  /// 之后新说的话仍然会正常追加。
  Future<void> clearContext(String residentId) async {
    await (_db.delete(_db.residentContextEvents)
          ..where((t) => t.residentId.equals(residentId)))
        .go();
    await _writeWatermark(
      residentId,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<List<ResidentContextEventRow>> activeEvents(String residentId) {
    return (_db.select(_db.residentContextEvents)
          ..where(
            (t) => t.residentId.equals(residentId) & t.compactedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
        .get();
  }

  /// 组装成 OpenAI 兼容的消息列表。
  ///
  /// 摘要永远排在最前，其余按 seq 只追加——摘要本身是在压缩时补写的，
  /// 它的 seq 比保留下来的最近一段还大，不能直接按 seq 丢进中间。
  Future<List<Map<String, dynamic>>> messages(String residentId) async {
    final rows = await _ordered(residentId);
    return [
      for (final row in rows)
        if (row.content.trim().isNotEmpty)
          {
            'role': row.role == 'assistant' ? 'assistant' : 'user',
            'content': row.content,
          },
    ];
  }

  /// 把所有还没被压缩的上下文拼成一段文字（关闭实时观察时写记忆用）。
  Future<String> allText(String residentId) async {
    final rows = await _ordered(residentId);
    return rows.map((row) => row.content).join('\n');
  }

  /// 最近一段上下文（关闭实时观察时的收尾提示）。摘要始终放在最前。
  Future<String> recentText(String residentId, {int maxChars = 60000}) async {
    final rows = await _ordered(residentId);
    final buffer = <String>[];
    var chars = 0;
    for (var i = rows.length - 1; i >= 0; i--) {
      final line = rows[i].content;
      if (chars + line.length > maxChars && buffer.isNotEmpty) break;
      buffer.add(line);
      chars += line.length;
    }
    return buffer.reversed.join('\n');
  }

  /// 摘要（若有）在前，其余事件保持 seq 顺序。
  Future<List<ResidentContextEventRow>> _ordered(String residentId) async {
    final rows = await activeEvents(residentId);
    final summaries = <ResidentContextEventRow>[];
    final rest = <ResidentContextEventRow>[];
    for (final row in rows) {
      if (row.kind == 'summary') {
        summaries.add(row);
      } else {
        rest.add(row);
      }
    }
    return [...summaries, ...rest];
  }

  /// 用户删掉整段私信时，把对应事件也移出上下文，别让住民还“记得”删掉的话。
  Future<void> deleteDmEvents(String residentId) async {
    await (_db.delete(_db.residentContextEvents)..where(
          (t) =>
              t.residentId.equals(residentId) &
              t.kind.isIn(const ['dm_in', 'dm_out']),
        ))
        .go();
  }

  Future<int> estimatedTokens(String residentId) async {
    final rows = await activeEvents(residentId);
    return rows.fold<int>(0, (sum, row) => sum + row.tokens);
  }

  // ---------------------------------------------------------------------------
  // 高水位压缩
  // ---------------------------------------------------------------------------

  /// 到了高水位才压缩一次：把前段总结成一条摘要，保留最近一段逐字上下文。
  ///
  /// 失败了就保持原样，不砍任何消息；宁可这一轮贵一点，也不要在体验上
  /// 悄悄丢内容。压缩成功后前缀会变一次，之后继续只追加。
  Future<bool> compactIfNeeded({
    required String residentId,
    required ModelConfig config,
  }) async {
    if (!_compacting.add(residentId)) return false;
    try {
      final rows = await activeEvents(residentId);
      if (rows.length < 4) return false;
      final total = rows.fold<int>(0, (sum, row) => sum + row.tokens);
      final window = contextWindowFor(config);
      final threshold = (window * compactRatio).round();
      if (total < threshold) return false;

      final keepBudget = (window * keepRatio).round();
      var keepTokens = 0;
      // 至少保留最后一条，别把整个上下文都吸进摘要里。
      var split = rows.length - 1;
      for (var i = rows.length - 1; i >= 0; i--) {
        keepTokens += rows[i].tokens;
        if (keepTokens >= keepBudget && rows.length - i >= 8) {
          split = i;
          break;
        }
      }
      if (split <= 0 || split >= rows.length) return false;

      final old = rows.sublist(0, split);
      final transcript = old.map((row) => row.content).join('\n');
      final summary = await _gateway.complete(
        config: config,
        messages: [
          {
            'role': 'system',
            'content':
                '你在整理一段长期的对话与观察记录，供之后的自己继续使用。'
                '把下面内容压缩成一份简洁但完整的摘要：保留对方的偏好、经历、'
                '约定、情绪变化，保留你看到过的重要画面和你说过/做过的事，'
                '保留尚未完成的约定。不要编造，不要加入评价，不要写“摘要：”。'
                '用中文，分段写；篇幅服从“别丢信息”，不要为了短而省略。',
          },
          {'role': 'user', 'content': transcript},
        ],
        temperature: 0.2,
        maxTokens: summaryMaxTokens,
        timeout: const Duration(seconds: 90),
      );
      final clean = summary.trim();
      if (clean.isEmpty) return false;

      final now = DateTime.now();
      await _db.transaction(() async {
        // 摘要先落在旧记录后面；查询时旧记录已被标掉，摘要正好排在最近一段之前。
        await _append(
          id:
              'summary:$residentId:${now.microsecondsSinceEpoch}:'
              '${old.length}',
          residentId: residentId,
          kind: 'summary',
          role: 'user',
          content: '【之前对话与观察的摘要】\n$clean',
          at: now,
          meta: 'compact',
        );
        await (_db.update(_db.residentContextEvents)
              ..where((t) => t.id.isIn(old.map((row) => row.id).toList())))
            .write(
              ResidentContextEventsCompanion(
                compactedAt: Value(now.millisecondsSinceEpoch),
              ),
            );
      });
      debugPrint(
        '[上下文] $residentId 压缩完成：${old.length} 条 -> 摘要，'
        '保留 ${rows.length - split} 条（约 ${total - keepTokens} token）',
      );
      return true;
    } catch (error) {
      debugPrint('[上下文] 压缩没成，保留完整上下文：$error');
      return false;
    } finally {
      _compacting.remove(residentId);
    }
  }

  /// 优先用模型配置里声明的窗口（默认 100 万）；
  /// 只有用户填 0 / 负数时才退回按模型名猜，最后再按 100 万。
  static int contextWindowFor(ModelConfig config) {
    if (config.contextWindow > 0) {
      return config.contextWindow.clamp(8000, 4000000);
    }
    final text = '${config.provider} ${config.model}'.toLowerCase();
    final match = RegExp(r'(\d{2,3})\s*k').firstMatch(text);
    if (match != null) {
      final thousands = int.tryParse(match.group(1) ?? '');
      if (thousands != null) return thousands * 1024;
    }
    return defaultContextWindow;
  }

  /// 粗估：中文按 1 token/字，英文数字按 4 字符/ token。
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    var cjk = 0;
    var other = 0;
    for (final rune in text.runes) {
      if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0x3000 && rune <= 0x303F)) {
        cjk++;
      } else {
        other++;
      }
    }
    return cjk + (other / 4).ceil();
  }

  // ---------------------------------------------------------------------------
  // 水位与工具
  // ---------------------------------------------------------------------------

  Future<int> _readWatermark(String residentId) async {
    final row =
        await (_db.select(_db.appSettings)
              ..where(
                (t) => t.key.equals('$_watermarkPrefix$residentId'),
              ))
            .getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? 0;
  }

  Future<void> _writeWatermark(String residentId, int value) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: '$_watermarkPrefix$residentId',
            value: '$value',
          ),
        );
  }

  static String _dmLine(PrivateMessage message) {
    final when = _timeLabel(message.createdAt);
    // 时间线是住民视角：用户发来的叫“对方”，住民自己发的叫“你”。
    final who = message.fromMe ? '对方' : '你';
    final body = switch (message.mediaType) {
      'image' => message.caption.trim().isEmpty
          ? '[发来一张图片]'
          : '[发来一张图片] ${message.caption.trim()}',
      'sticker' => message.caption.trim().isEmpty
          ? '[表情包]'
          : '[表情包] ${message.caption.trim()}',
      'voice' => message.transcript.trim().isEmpty
          ? '[语音]'
          : '（语音）${message.transcript.trim()}',
      'call' => message.content.trim().isEmpty ? '[通话]' : message.content.trim(),
      _ => message.content.trim().isEmpty
          ? '[空消息]'
          : message.content.trim(),
    };
    return '[$when] $who：$body';
  }

  static String _timeLabel(DateTime at) =>
      '${at.month}月${at.day}日 '
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}

final residentTimelineProvider = Provider<ResidentTimeline>((ref) {
  return ResidentTimeline(
    ref.watch(databaseProvider),
    ref.watch(privateMessageRepositoryProvider),
    ref.watch(modelGatewayProvider),
  );
});
