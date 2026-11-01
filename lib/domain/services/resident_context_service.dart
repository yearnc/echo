import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/private_message_repository.dart';
import '../models/custom_resident.dart';
import 'resident_context_window.dart';
import 'resident_tool_session.dart';

/// 一位住民的常驻上下文窗口的唯一持有者。
///
/// 唤醒、通话、游戏都从这里取同一个窗口：同一段人设、同一份记忆、
/// 同一段私信。以前窗口藏在 [ResidentWakeService] 里，通话只能另拼一套
/// system prompt，于是同一个人换了块屏幕就像失忆。
///
/// 这里只做窗口的构建、续期、追加和作废；具体这一轮该说什么，
/// 由调用方在窗口末尾追加载荷，绝不回头重写前缀。
class ResidentContextService {
  ResidentContextService({
    required this.residents,
    required this.messages,
    required this.session,
  });

  final CustomResidentRepository residents;
  final PrivateMessageRepository messages;
  final ResidentToolSession session;

  final Map<String, ResidentContextWindow> _windows = {};

  /// 同一位住民同时只允许一次窗口构建，避免并发开两个窗口。
  final Map<String, Future<void>> _locks = {};

  ResidentContextWindow? peek(String residentId) => _windows[residentId];

  /// 窗口作废：删私信、清空上下文、改人设时调用。
  void invalidate(String residentId) => _windows.remove(residentId);

  Future<ResidentContextWindow> open(
    CustomResident resident, {
    required bool allowVoice,
    required bool allowImages,
  }) {
    final id = resident.id;
    final previous = _locks[id] ?? Future<void>.value();
    final gate = Completer<void>();
    _locks[id] = gate.future;
    return previous
        .catchError((Object _) {})
        .then(
          (_) => _open(
            resident,
            allowVoice: allowVoice,
            allowImages: allowImages,
          ),
        )
        .whenComplete(() {
          gate.complete();
          if (identical(_locks[id], gate.future)) _locks.remove(id);
        });
  }

  /// 方便通话/游戏只拿 residentId 的场景。
  Future<ResidentContextWindow?> openById(
    String residentId, {
    required bool allowVoice,
    required bool allowImages,
  }) async {
    final resident = await residents.findById(residentId);
    if (resident == null) return null;
    return open(
      resident,
      allowVoice: allowVoice,
      allowImages: allowImages,
    );
  }

  Future<ResidentContextWindow> _open(
    CustomResident resident, {
    required bool allowVoice,
    required bool allowImages,
  }) async {
    final now = DateTime.now();
    final system = session.systemPromptFor(resident, voiceReady: allowVoice);
    final hash = '${system.hashCode}:${allowVoice ? 1 : 0}:${allowImages ? 1 : 0}';
    var window = _windows[resident.id];
    if (window != null && (window.expired(now) || window.promptHash != hash)) {
      window = null;
    }
    if (window == null) {
      final memory = (await session.memoryLinesFor(resident)).trim();
      final recent = await messages.recentTurns(
        resident.id,
        limit: ResidentContextWindow.baseDmCount,
      );
      window = ResidentContextWindow(
        residentId: resident.id,
        promptHash: hash,
        messages: [
          {
            'role': 'system',
            'content': memory.isEmpty ? system : '$system\n\n你记得：$memory',
          },
        ],
        syncedThroughMs: 0,
        dmIds: {},
        includeImages: allowImages,
        now: now,
      );
      for (final turn in recent) {
        await window.appendDm(turn);
      }
      _windows[resident.id] = window;
      debugPrint('[上下文] ${resident.name}：新建窗口（${recent.length} 条私信）');
    } else {
      final fresh = await messages.turnsSince(
        resident.id,
        afterMs: window.syncedThroughMs,
      );
      for (final turn in fresh) {
        await window.appendDm(turn);
      }
      if (fresh.isNotEmpty) {
        debugPrint('[上下文] ${resident.name}：追加入窗口 ${fresh.length} 条');
      }
    }
    window.touch(now);
    return window;
  }

  /// 往活跃窗口里追加一条消息。
  ///
  /// 只追加到末尾，不改前缀；窗口过期就不写，下次按私信重建。
  void appendMessage(String residentId, Map<String, dynamic> message) {
    final window = _windows[residentId];
    if (window == null || window.expired(DateTime.now())) return;
    window.messages.add(message);
  }

  /// 往活跃窗口里追加一条气泡（assistant 侧）。
  ///
  /// 气泡不是私信，不落 `private_messages`，但它是住民说过的话；
  /// 不追加的话，它进私信就否认自己说过。看过的画面只留一句摘要。
  void appendBubbleToWindow(
    String residentId,
    String text, {
    String seen = '',
  }) {
    final note = seen.trim();
    appendMessage(residentId, {
      'role': 'assistant',
      'content': note.isEmpty
          ? '[屏幕气泡] $text'
          : '[屏幕气泡] $text\n（当时看到：${_clip(note, 60)}）',
    });
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';
}

final residentContextServiceProvider = Provider<ResidentContextService>(
  (ref) => ResidentContextService(
    residents: ref.watch(customResidentRepositoryProvider),
    messages: ref.watch(privateMessageRepositoryProvider),
    session: ref.watch(residentToolSessionProvider),
  ),
);
