import 'package:echo/data/demo/demo_script_repository.dart';
import 'package:echo/domain/models/demo_script.dart';
import 'package:echo/features/demo/demo_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

DemoStep step(int atMs, String type, {String? personaId, int? likes}) =>
    DemoStep(atMs: atMs, type: type, personaId: personaId, likes: likes);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DemoTimeline', () {
    test('按时间点批量放出到期动作', () {
      final timeline = DemoTimeline([
        step(1000, 'stats', likes: 3),
        step(3000, 'comment', personaId: 'persona_001'),
        step(6000, 'comment', personaId: 'persona_002'),
      ]);

      expect(timeline.advanceTo(500), isEmpty);
      expect(timeline.advanceTo(1200), hasLength(1));
      // 一次跨过两个时间点：两个动作应该一起出来，不能漏
      expect(timeline.advanceTo(6500), hasLength(2));
      expect(timeline.isFinished, isTrue);
      expect(timeline.advanceTo(9999), isEmpty);
    });

    test('单步只放一个，并且能读到下一个时间点', () {
      final timeline = DemoTimeline([
        step(2000, 'comment', personaId: 'a'),
        step(5000, 'comment', personaId: 'b'),
      ]);

      expect(timeline.nextAtMs, 2000);
      final first = timeline.stepOnce();
      expect(first?.personaId, 'a');
      expect(timeline.nextAtMs, 5000);
      expect(timeline.cursor, 1);
    });

    test('单步到结尾后再取返回 null', () {
      final timeline = DemoTimeline([step(100, 'overlay')]);
      timeline.stepOnce();

      expect(timeline.stepOnce(), isNull);
      expect(timeline.isFinished, isTrue);
    });

    test('重置后回到开场', () {
      final timeline = DemoTimeline([
        step(1000, 'stats'),
        step(2000, 'comment'),
      ]);
      timeline.advanceTo(3000);
      expect(timeline.isFinished, isTrue);

      timeline.reset();

      expect(timeline.cursor, 0);
      expect(timeline.isFinished, isFalse);
      expect(timeline.nextAtMs, 1000);
    });

    test('进度按最后一个动作的时间点计算并夹在 0..1', () {
      final timeline = DemoTimeline([step(0, 'stats'), step(10000, 'end_card')]);

      expect(timeline.progressAt(0), 0);
      expect(timeline.progressAt(5000), closeTo(0.5, 0.001));
      expect(timeline.progressAt(20000), 1);
    });
  });

  group('DemoScript 解析', () {
    test('preSteps 与 steps 合并后按时间排序', () {
      final script = DemoScript.fromJson(const {
        'id': 'actX',
        'title': '测试幕',
        'subtitle': '副标题',
        'durationHintMs': 1000,
        'preSteps': [
          {'atMs': 500, 'type': 'settings_hint', 'text': '先设置'},
        ],
        'steps': [
          {'atMs': 9000, 'type': 'end_card', 'text': '结束'},
          {'atMs': 2000, 'type': 'comment', 'personaId': 'p1', 'content': '评论'},
        ],
      });

      expect(script.steps.map((s) => s.atMs), [500, 2000, 9000]);
      expect(script.effectiveDurationMs, 9000);
    });

    test('缺字段时不崩，用默认值兜底', () {
      final script = DemoScript.fromJson(const {'id': 'actMin'});

      expect(script.title, '未命名');
      expect(script.steps, isEmpty);
      expect(script.post, isNull);
    });

    test('分析结果按固定顺序输出五项', () {
      final analysis = DemoAnalysis.fromJson(const {
        'imageDescription': '画面描述',
        'emotionAnalysis': '情绪',
        'suggestions': '建议',
      });

      expect(analysis.entries.map((e) => e.key),
          ['图片客观描述', '文本情绪分析', '改进建议']);
      expect(analysis.entries.first.value, '画面描述');
    });
  });

  group('真实脚本资产', () {
    test('三幕脚本都能读取并解析', () async {
      final scripts = await const DemoScriptRepository().loadAll();

      expect(scripts, hasLength(3));
      expect(scripts.map((s) => s.id), ['act1', 'act2', 'act3']);
    });

    test('第一幕评论足够多（演示模式要"热闹"）', () async {
      final script = await const DemoScriptRepository().loadById('act1');
      final comments = script.steps.where((s) => s.isComment).toList();

      expect(comments.length, greaterThanOrEqualTo(10),
          reason: '三幕的观赏性依赖热闹的评论区');
      expect(comments.any((c) => c.mediaType == 'voice'), isTrue,
          reason: '要有语音评论，否则展示不出语音能力');
      expect(comments.every((c) => c.personaId != null), isTrue);
    });

    test('第二幕有千字长评与 AI 推荐文案', () async {
      final script = await const DemoScriptRepository().loadById('act2');

      final longReview = script.steps.firstWhere((s) => s.highlight);
      expect(longReview.content!.length, greaterThan(400),
          reason: '长评越夸张，讽刺越明显');

      final captions =
          script.steps.where((s) => s.type == 'caption_suggestion').toList();
      expect(captions, hasLength(1));
      expect(captions.first.captions, hasLength(3));
    });

    test('第三幕复用第一幕的帖子（同一张照片）', () async {
      final repo = const DemoScriptRepository();
      final act1 = await repo.loadById('act1');
      final act3 = await repo.loadById('act3');

      expect(act3.post, isNull);
      expect(act3.postRef, 'act1');
      expect(act1.post, isNotNull);
      expect(act3.steps.any((s) => s.type == 'mode' && s.toMode == 'clear'), isTrue);
    });

    test('第一幕最终点赞数过百', () async {
      final script = await const DemoScriptRepository().loadById('act1');
      var likes = 0;
      for (final s in script.steps) {
        if (s.type == 'stats') likes = s.likes ?? likes;
        if (s.type == 'like_burst') likes += s.delta ?? 0;
      }

      expect(likes, greaterThan(100));
    });
  });
}
