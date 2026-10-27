import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/media/voice_wave_store.dart';
import 'package:echo/data/repositories/analysis_repository.dart';
import 'package:echo/data/repositories/interaction_repository.dart';
import 'package:echo/data/repositories/notification_repository.dart';
import 'package:echo/data/repositories/plan_event_repository.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/data/repositories/post_voice_repository.dart';
import 'package:echo/domain/models/custom_resident.dart';
import 'package:echo/domain/models/post_voice.dart';
import 'package:echo/domain/models/resident_voice.dart';
import 'package:echo/domain/models/voice_settings.dart';
import 'package:echo/domain/services/content_generator.dart';
import 'package:echo/domain/models/planned_interaction.dart';
import 'package:echo/domain/services/scheduler_service.dart';
import 'package:echo/domain/services/tts_service.dart';
import 'package:echo/domain/services/voice_waveform.dart';
import 'package:echo/core/constants/app_texts.dart';
import 'package:echo/domain/models/post.dart';
import 'package:echo/features/shared_widgets/comment_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一个永远掷出最低值的骰子。
///
/// 「这条评论要不要用语音」是概率判定，但用例要验的是接线
/// （合成完之后字段有没有写对），概率本身交给另一组用例。
class _AlwaysLowRandom implements Random {
  @override
  double nextDouble() => 0.0;

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

/// 假的合成服务：不碰模型、不写文件，只回答"合成成不成功"。
class _FakeTts extends TtsService {
  _FakeTts({this.succeeds = true});

  final bool succeeds;
  int calls = 0;

  @override
  Future<VoiceClip?> speak({
    required String text,
    required String personaId,
    String voiceModel = '',
    String voiceDescription = '',
    bool wantsDescription = false,
    String referenceAudioPath = '',
    String referenceText = '',
    bool preferLocalClone = false,
  }) async {
    calls += 1;
    if (!succeeds) return null;
    return VoiceClip(
      ref: 'file:fake/voice.wav',
      transcript: text,
      durationMs: 1800,
      waveform: const [1.0],
    );
  }
}

void main() {
  // 住民名单是从 assets 读的，得先有 binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('住民音色', () {
    test('所有住民都落在当前本机模型的 5 个音色里', () {
      for (var i = 1; i <= 32; i++) {
        final id = 'persona_${i.toString().padLeft(3, '0')}';
        final sid = ResidentVoice.sidFor(id);
        expect(sid, greaterThanOrEqualTo(0));
        expect(sid, lessThan(ResidentVoice.localSpeakerCount));
      }
    });

    test('旧的 local:42 越界引用会被忽略，重新落到有效音色', () {
      final sid = ResidentVoice.sidFor(
        'resident_x',
        voiceModel: 'local:42',
      );
      expect(sid, lessThan(ResidentVoice.localSpeakerCount));
    });

    test('新的 local:3 会被尊重', () {
      expect(
        ResidentVoice.sidFor('resident_x', voiceModel: 'local:3'),
        3,
      );
    });

    test('同一个住民每次问都是同一个编号', () {
      final first = ResidentVoice.sidFor('persona_007');
      for (var i = 0; i < 20; i++) {
        expect(ResidentVoice.sidFor('persona_007'), first);
      }
    });

    test('带 female 的语气标签不会被当成男声', () {
      // `voice_soft_female` 里也含 "male" 四个字母，这是最容易写错的一处。
      final femaleSids = <int>{
        for (final model in ['voice_soft_female', 'voice_female_soft'])
          ResidentVoice.sidFor('陌生人_$model', voiceModel: model),
      };
      final maleSid = ResidentVoice.sidFor('陌生人_male', voiceModel: 'voice_male_calm');

      for (final sid in femaleSids) {
        expect(sid, isNot(maleSid));
      }
    });

    test('表外的住民也拿得到稳定音色', () {
      final a = ResidentVoice.sidFor('persona_999', voiceModel: 'voice_female_warm');
      final b = ResidentVoice.sidFor('persona_999', voiceModel: 'voice_female_warm');
      expect(a, b);
      expect(a, greaterThanOrEqualTo(0));
    });

    test('同一段音色描述固定到同一个本机音色', () {
      final first = ResidentVoice.sidForDescription('低沉温柔的男声，语速偏慢');
      for (var i = 0; i < 10; i++) {
        expect(
          ResidentVoice.sidForDescription('低沉温柔的男声，语速偏慢'),
          first,
        );
      }
      expect(first, greaterThanOrEqualTo(0));
    });

    test('固定住民的音色引用会传给评论和私信', () {
      final resident = CustomResident(
        id: 'resident_001',
        name: '小满',
        voiceEnabled: true,
        voiceRef: 'local:42',
        createdAt: DateTime(2026, 10, 1),
      );
      expect(resident.toPersona().voiceModel, 'local:42');

      final voice = PostVoice(
        id: 'voice_1',
        postId: 'post_1',
        kind: PostVoiceKind.custom,
        model: 'cloud:speech:abc',
        name: '小满',
        createdAt: DateTime(2026, 10, 1),
      );
      expect(voice.toPersona().voiceModel, 'cloud:speech:abc');
    });

    test('懒得打字的人说话慢一点', () {
      expect(ResidentVoice.speedFor('voice_male_lazy'), lessThan(1.0));
      expect(ResidentVoice.speedFor('voice_bright'), greaterThan(1.0));
      expect(ResidentVoice.speedFor('voice_male_calm'), 1.0);
    });
  });

  group('波形', () {
    test('安静的一段也给最矮的柱子，不留空', () {
      final bars = VoiceWaveform.bars(Float32List(2200));
      expect(bars.length, VoiceWaveform.defaultBars);
      expect(bars.every((bar) => bar > 0), isTrue);
    });

    test('响的那一段比轻的那一段高，最高的一根是 1', () {
      final samples = Float32List(2200);
      for (var i = 0; i < 1100; i++) {
        samples[i] = 0.1;
      }
      for (var i = 1100; i < 2200; i++) {
        samples[i] = 0.8;
      }

      final bars = VoiceWaveform.bars(samples);
      expect(bars.first, lessThan(bars.last));
      expect(bars.reduce(max), closeTo(1.0, 0.0001));
    });

    test('时长按采样点算，不是按字数估', () {
      expect(VoiceWaveform.durationMs(16000, 16000), 1000);
      expect(VoiceWaveform.durationMs(27454, 8000), 3432);
      expect(VoiceWaveform.durationMs(0, 16000), 0);
      // 采样率缺失时不该除出个无穷大
      expect(VoiceWaveform.durationMs(16000, 0), 0);
    });
  });

  group('从落盘的 wav 里读波形', () {
    test('认出自家引擎写出来的 16 位 PCM', () async {
      final file = File('${Directory.systemTemp.path}/echo_wave_test.wav');
      await file.writeAsBytes(_fakeWav([1000, 2000, 3000, 4000]));
      addTearDown(() => file.deleteSync());

      final bars = await VoiceWaveStore().load('file:${file.path}');
      expect(bars.length, VoiceWaveform.defaultBars);
      expect(bars.reduce(max), closeTo(1.0, 0.0001));
    });

    test('文件不在时给等高柱子，不让气泡塌掉', () async {
      final bars = await VoiceWaveStore().load(
        'file:${Directory.systemTemp.path}/根本不存在.wav',
      );
      expect(bars.length, VoiceWaveform.defaultBars);
      expect(bars.toSet().length, 1);
    });
  });

  group('评论兑现之后变成语音', () {
    late AppDatabase db;
    late PostRepository posts;
    late InteractionRepository interactions;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      posts = PostRepository(db);
      interactions = InteractionRepository(db);

    });

    tearDown(() => db.close());

    /// 排一条"早就该兑现"的评论，然后扫一次队列。
    Future<void> flushOneComment({
      required TtsService? voice,
      VoiceSettings Function()? readVoiceSettings,
    }) async {
      final postId = await posts.create(content: '今天楼下桂花开了', scope: 'echo');
      await PostVoiceRepository(db).insertAll([
        PostVoice(
          id: 'voice_1',
          postId: postId,
          kind: PostVoiceKind.ephemeral,
          name: '三楼的灯',
          model: 'voice_soft_female',
          createdAt: DateTime.now(),
        ),
      ]);
      await interactions.insertPlanned(postId, [
        PlannedInteraction(
          personaId: 'voice_1',
          type: 'comment',
          scheduledAt: DateTime.now().subtract(const Duration(minutes: 1)),
          content: '桂花一开，整条街都是甜的。',
          mediaType: 'text',
        ),
      ]);

      final scheduler = SchedulerService(
        interactions: interactions,
        planEvents: PlanEventRepository(db),
        posts: posts,
        notifications: NotificationRepository(db),
        analyses: AnalysisRepository(db),
        generator: SampleContentGenerator(),
        voiceRepo: PostVoiceRepository(db),
        voice: voice,
        readVoiceSettings: readVoiceSettings,
        // 概率那一关直接放行：这条用例要验的是接线，不是随机。
        random: _AlwaysLowRandom(),
      );
      await scheduler.flushDue();
      // 合成是 unawaited 挂出去的，等它跑完。
      await pumpEventQueue();
    }

    test('合成成功后评论变成语音条，转写稿和时长一起落库', () async {
      final fake = _FakeTts();
      await flushOneComment(voice: fake);

      final row = (await db.select(db.aiInteractions).get()).single;
      expect(fake.calls, 1);
      expect(row.mediaType, 'voice');
      expect(row.voicePath, 'file:fake/voice.wav');
      expect(row.transcript, '桂花一开，整条街都是甜的。');
      expect(row.voiceDurationMs, 1800);
    });

    test('合成不出来就保持文字，评论区照常', () async {
      final fake = _FakeTts(succeeds: false);
      await flushOneComment(voice: fake);

      final row = (await db.select(db.aiInteractions).get()).single;
      expect(fake.calls, 1);
      expect(row.mediaType, 'text');
      expect(row.voicePath, isNull);
      // 评论本身还在——语音只是表现形式，不该连累内容。
      expect(row.status, 'done');
    });

    test('语音开关关掉时不再生成新的语音条', () async {
      final fake = _FakeTts();
      await flushOneComment(
        voice: fake,
        readVoiceSettings: () => const VoiceSettings(enabled: false),
      );

      final row = (await db.select(db.aiInteractions).get()).single;
      expect(fake.calls, 0, reason: '开关关了就不该再合成');
      expect(row.mediaType, 'text');
      expect(row.status, 'done', reason: '评论本身照常送到');
    });

    test('没有语音服务时行为和 B8 之前完全一致', () async {
      await flushOneComment(voice: null);

      final row = (await db.select(db.aiInteractions).get()).single;
      expect(row.mediaType, 'text');
      expect(row.status, 'done');
    });
  });

  group('语音条长什么样', () {
    testWidgets('播放键、秒数、转写稿、合规小字都在', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: VoiceBubble(
                comment: PostComment(
                  id: 'c1',
                  postId: 'p1',
                  personaId: 'persona_001',
                  content: '桂花一开，整条街都是甜的。',
                  mediaType: CommentMedia.voice,
                  voiceAsset: 'file:不存在/voice.wav',
                  transcript: '桂花一开，整条街都是甜的。',
                  voiceDurationMs: 3400,
                  createdAt: DateTime(2026, 10, 14, 20),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('3"'), findsOneWidget);
      expect(find.textContaining('桂花一开'), findsOneWidget);
      // 合规文案是硬要求，不许在业务代码里被改掉或省略（规划书 §6.6）。
      expect(find.text(AppTexts.aiVoiceNotice), findsOneWidget);
    });
  });

}

/// 造一个最简 WAV（mono / 16 位 / 给定的采样值）。
Uint8List _fakeWav(List<int> values) {
  final header = ByteData(44);

  void ascii(int offset, String tag) {
    for (var i = 0; i < tag.length; i++) {
      header.setUint8(offset + i, tag.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + values.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // fmt 段长度
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // 单声道
  header.setUint32(24, 8000, Endian.little); // 采样率
  header.setUint32(28, 16000, Endian.little); // 字节率
  header.setUint16(32, 2, Endian.little); // 每帧字节数
  header.setUint16(34, 16, Endian.little); // 位深
  ascii(36, 'data');
  header.setUint32(40, values.length * 2, Endian.little);

  final body = ByteData(values.length * 2);
  for (var i = 0; i < values.length; i++) {
    body.setInt16(i * 2, values[i], Endian.little);
  }

  final bytes = BytesBuilder();
  bytes.add(header.buffer.asUint8List());
  bytes.add(body.buffer.asUint8List());
  return bytes.toBytes();
}
