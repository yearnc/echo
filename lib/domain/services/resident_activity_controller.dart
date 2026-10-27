import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/resident_activity.dart';

/// 哪位住民此刻在做什么。聊天页只读自己那一位。
class ResidentActivityController
    extends Notifier<Map<String, ResidentActivity>> {
  @override
  Map<String, ResidentActivity> build() => const {};

  void show(String residentId, String label, ResidentActivityKind kind) {
    if (residentId.isEmpty) return;
    final previous = state[residentId];
    if (previous != null &&
        previous.label == label &&
        previous.kind == kind) {
      // 同一个状态反复汇报（每轮都“思考”）：保留最初时间，不抖动。
      return;
    }
    state = {
      ...state,
      residentId: ResidentActivity(
        label: label,
        kind: kind,
        since: DateTime.now(),
      ),
    };
  }

  void clear(String residentId) {
    if (!state.containsKey(residentId)) return;
    final next = Map<String, ResidentActivity>.from(state)..remove(residentId);
    state = next;
  }
}

final residentActivityProvider =
    NotifierProvider<ResidentActivityController, Map<String, ResidentActivity>>(
      ResidentActivityController.new,
    );

/// 给工具会话用的小回调：只汇报“现在在做什么”。
typedef ResidentActivitySink =
    void Function(String residentId, String label, ResidentActivityKind kind);
