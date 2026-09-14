import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_texts.dart';
import '../../data/repositories/addiction_repository.dart';
import '../models/safety_settings.dart';
import 'safety_controller.dart';

/// 防沉迷提醒的判定（规划书 §6.9 / §13）。
///
/// 刻意**没有**"强制阻止"这一档：到了阈值只给一句话，不锁屏、不劝退、
/// 不把使用时长变成需要打败的关卡。沉浸感本身是这个产品要研究的东西，
/// 一个会拦住用户的工具没法让人看清自己是怎么被留住的。
class AddictionGuard {
  const AddictionGuard({
    required this.repository,
    required this.readSettings,
  });

  final AddictionRepository repository;
  final SafetySettings Function() readSettings;

  /// 记一次"查看反馈"。详情页打开、从通知点进来都算。
  Future<void> recordView(String postId) =>
      repository.recordFeedbackView(postId: postId);

  /// 该不该提醒？该提醒就返回文案，否则 null。
  ///
  /// 判断顺序：总开关关掉 → 不提醒；次数不够 → 不提醒；窗口内已经提醒过 →
  /// 不再提醒；都过了才记一条日志并给出文案。
  Future<String?> evaluate() async {
    final settings = readSettings();
    if (!settings.addictionGuard) return null;

    final count = await repository.countFeedbackViews();
    if (count < settings.feedbackViewThreshold) return null;

    final last = await repository.lastEventAt(
      AddictionEventType.feedbackThreshold,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last != null &&
        now - last < AddictionRepository.defaultWindowMs) {
      return null;
    }

    await repository.logEvent(
      AddictionEventType.feedbackThreshold,
      value: count,
    );
    return AppTexts.addictionReminder;
  }
}

final addictionGuardProvider = Provider<AddictionGuard>(
  (ref) => AddictionGuard(
    repository: ref.watch(addictionRepositoryProvider),
    readSettings: () => ref.read(safetyControllerProvider),
  ),
);
