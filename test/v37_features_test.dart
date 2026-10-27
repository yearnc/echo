import 'package:drift/drift.dart' show TableUpdate;
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/private_message_repository.dart';
import 'package:echo/domain/models/custom_resident.dart';
import 'package:echo/domain/models/model_config.dart';
import 'package:echo/domain/models/tool_settings.dart';
import 'package:echo/domain/services/resident_voice_profile_service.dart';
import 'package:echo/domain/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('版本比较', () {
    test('新版本比旧版本大', () {
      expect(UpdateCheckResult.compareVersions('v3.7.0', '3.6.4'), greaterThan(0));
      expect(UpdateCheckResult.compareVersions('3.6.4', 'v3.7.0'), lessThan(0));
    });

    test('忽略前缀、构建号和预发布后缀', () {
      expect(UpdateCheckResult.compareVersions('v3.7.0+15', '3.7.0'), 0);
      expect(UpdateCheckResult.compareVersions('3.7.0-rc1', '3.7.0'), 0);
      expect(UpdateCheckResult.compareVersions('3.10.0', '3.9.9'), greaterThan(0));
    });

    test('同版本不算有更新', () {
      const result = UpdateCheckResult(
        currentVersion: '3.7.0',
        latestVersion: 'v3.7.0',
      );
      expect(result.hasUpdate, isFalse);
    });
  });

  group('工具限额', () {
    test('默认 12 轮 / 30 秒', () {
      const settings = ToolSettings.defaults;
      expect(settings.maxRounds, 12);
      expect(settings.timeoutSeconds, 30);
      expect(settings.timeout, const Duration(seconds: 30));
      expect(settings.voiceTimeout, const Duration(seconds: 90));
    });

    test('超范围会被夹住', () {
      final high = const ToolSettings().copyWith(maxRounds: 999);
      final low = const ToolSettings().copyWith(timeoutSeconds: 1);
      expect(high.maxRounds, ToolSettings.maxRoundsLimit);
      expect(low.timeoutSeconds, ToolSettings.minTimeoutSeconds);
    });
  });

  group('四种音色方式', () {
    const service = ResidentVoiceProfileService(gateway: null);
    const base = ModelConfig(
      id: 'm',
      provider: 'custom',
      label: 'x',
      baseUrl: 'https://example.com/v1',
      model: 'x',
      kind: ModelKind.tts,
    );

    test('没配云端时也有两套本机方式', () {
      final modes = service.modesFor(null);
      expect(modes, [
        ResidentVoiceMode.description,
        ResidentVoiceMode.referenceTranscript,
      ]);
    });

    test('云端只支持参考音频 + 逐字稿时，不会多出别的方式', () {
      final modes = service.modesFor(
        base.copyWith(
          provider: 'siliconflow-tts',
          baseUrl: 'https://api.siliconflow.cn/v1',
          ttsReferenceTranscript: true,
        ),
      );
      expect(modes, [
        ResidentVoiceMode.description,
        ResidentVoiceMode.referenceTranscript,
      ]);
    });

    test('支持哪几种就返回哪几种', () {
      final modes = service.modesFor(
        base.copyWith(
          ttsVoiceDescription: true,
          ttsReferenceOnly: true,
          ttsReferenceDescription: true,
          ttsReferenceTranscript: true,
        ),
      );
      expect(modes, [
        ResidentVoiceMode.description,
        ResidentVoiceMode.referenceTranscript,
        ResidentVoiceMode.cloudDescription,
        ResidentVoiceMode.referenceOnly,
        ResidentVoiceMode.referenceDescription,
      ]);
    });
  });

  group('私信分段可打断', () {
    late AppDatabase db;
    late PrivateMessageRepository messages;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      messages = PrivateMessageRepository(db);
    });

    tearDown(() async => db.close());

    test('同一轮几段都标成待发，按顺序排', () async {
      final at = DateTime.now().add(const Duration(minutes: 5));
      await messages.scheduleIncoming(
        personaId: 'r1',
        content: '第一段',
        at: at,
        deliveryGroup: 'wake_1',
        deliveryIndex: 0,
      );
      await messages.scheduleIncoming(
        personaId: 'r1',
        content: '第二段',
        at: at.add(const Duration(seconds: 6)),
        deliveryGroup: 'wake_1',
        deliveryIndex: 1,
      );

      final pending = await messages.pendingSegments('r1');
      expect(pending.length, 2);
      expect(pending.first.content, '第一段');
      expect(pending.last.index, 1);
      expect(pending.first.groupId, 'wake_1');
    });

    test('用户可以打断：没发的段先暂停，界面看不到但下一轮能拿到', () async {
      final at = DateTime.now().add(const Duration(minutes: 5));
      await messages.scheduleIncoming(
        personaId: 'r1',
        content: '还没发出去',
        at: at,
        deliveryGroup: 'wake_1',
      );

      final paused = await messages.pausePendingSegments('r1');

      expect(paused.length, 1);
      expect(paused.single.content, '还没发出去');
      // 暂停中的段还会交给下一轮模型，但不会出现在聊天界面。
      expect((await messages.pendingSegments('r1')).length, 1);
      expect(await messages.watchThread('r1').first, isEmpty);
    });

    test('暂停段即使原定时间过了，也要交给下一轮', () async {
      final id = await messages.scheduleIncoming(
        personaId: 'r1',
        content: '拖过了时间',
        at: DateTime.now().add(const Duration(seconds: 1)),
        deliveryGroup: 'wake_1',
      );
      await messages.pausePendingSegments('r1');

      await db.customStatement(
        'UPDATE private_messages SET created_at = ? WHERE id = ?',
        [
          DateTime.now()
              .subtract(const Duration(minutes: 2))
              .millisecondsSinceEpoch,
          id,
        ],
      );

      final pending = await messages.pendingSegments('r1');
      expect(pending.length, 1);
      expect(pending.single.content, '拖过了时间');
    });

    test('模型没处理暂停段时，收尾统一取消', () async {
      final at = DateTime.now().add(const Duration(minutes: 5));
      final id = await messages.scheduleIncoming(
        personaId: 'r1',
        content: '先停下',
        at: at,
        deliveryGroup: 'wake_1',
      );
      await messages.pausePendingSegments('r1');

      expect(await messages.expirePausedSegments([id]), 1);
      expect(await messages.pendingSegments('r1'), isEmpty);
    });

    test('模型可以改一段、取消另一段', () async {
      final at = DateTime.now().add(const Duration(minutes: 5));
      final first = await messages.scheduleIncoming(
        personaId: 'r1',
        content: '原来的话',
        at: at,
        deliveryGroup: 'wake_1',
        deliveryIndex: 0,
      );
      final second = await messages.scheduleIncoming(
        personaId: 'r1',
        content: '不想要了',
        at: at.add(const Duration(seconds: 6)),
        deliveryGroup: 'wake_1',
        deliveryIndex: 1,
      );

      expect(
        await messages.rewritePendingSegment(
          segmentId: first,
          content: '改成接得上的话',
        ),
        isTrue,
      );
      expect(await messages.cancelPendingSegment(second), isTrue);

      final pending = await messages.pendingSegments('r1');
      expect(pending.length, 1);
      expect(pending.single.content, '改成接得上的话');
    });

    test('已经发出去的段不能再取消或改写', () async {
      final id = await messages.scheduleIncoming(
        personaId: 'r1',
        content: '已经到了',
        at: DateTime.now().subtract(const Duration(seconds: 1)),
        deliveryGroup: 'wake_1',
      );
      expect(await messages.cancelPendingSegment(id), isFalse);
      expect(
        await messages.rewritePendingSegment(segmentId: id, content: '改不了'),
        isFalse,
      );
    });

    test('到点且没被取消的段照常出现', () async {
      final future = DateTime.now().add(const Duration(minutes: 5));
      await messages.scheduleIncoming(
        personaId: 'r1',
        content: '会到',
        at: future,
        deliveryGroup: 'wake_1',
        deliveryIndex: 0,
      );
      final dropped = await messages.scheduleIncoming(
        personaId: 'r1',
        content: '取消了',
        at: future.add(const Duration(seconds: 6)),
        deliveryGroup: 'wake_1',
        deliveryIndex: 1,
      );
      await messages.cancelPendingSegment(dropped);

      await db.customStatement(
        'UPDATE private_messages SET created_at = ?',
        [DateTime.now().subtract(const Duration(seconds: 1)).millisecondsSinceEpoch],
      );
      db.notifyUpdates({TableUpdate.onTable(db.privateMessages)});

      final thread = await messages.watchThread('r1').first;
      expect(thread.length, 1);
      expect(thread.single.content, '会到');
    });
  });
}
