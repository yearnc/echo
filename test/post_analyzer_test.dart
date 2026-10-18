import 'package:flutter_test/flutter_test.dart';

import 'package:echo/domain/models/post_understanding.dart';
import 'package:echo/domain/services/post_analyzer.dart';

void main() {
  group('帖子解析', () {
    test('玩梗帖：语气、领域、笑点、实体都解析出来', () {
      final result = PostAnalyzer.parse(
        '''
        {
          "tone": "玩梗",
          "domain": "游戏",
          "entities": ["原神", "木偶大人", "望月者计划", "原神"],
          "point": "用望月者计划的梗自嘲抽卡",
          "joke_mechanism": "圈内黑话 + 自嘲",
          "emotion": "",
          "insider_angle": "抽卡歪了还要嘴硬",
          "needs_web": false,
          "confidence": 0.86
        }
        ''',
        postId: 'p1',
        model: 'm',
      );

      expect(result, isNotNull);
      expect(result!.tone, '玩梗');
      expect(result.domain, '游戏');
      expect(result.entities, ['原神', '木偶大人', '望月者计划']);
      expect(result.jokeMechanism, '圈内黑话 + 自嘲');
      expect(result.insiderAngle, '抽卡歪了还要嘴硬');
      expect(result.isConfident, isTrue);
    });

    test('感伤帖：情绪落点在，评论才知道接什么', () {
      final result = PostAnalyzer.parse(
        '{"tone":"感伤","domain":"情感","point":"想起以前的事",'
        '"emotion":"怀念高中同学","confidence":0.7}',
        postId: 'p2',
        model: 'm',
      );

      expect(result!.isEmotional, isTrue);
      expect(result.emotion, '怀念高中同学');
      expect(result.toPromptBlock(), contains('情绪落点'));
    });

    test('confidence 低时，提示块明确只许提问/围观', () {
      final result = PostAnalyzer.parse(
        '{"tone":"玩梗","domain":"其他","point":"没看懂",'
        '"confidence":0.2}',
        postId: 'p3',
        model: 'm',
      );

      expect(result!.isConfident, isFalse);
      expect(result.toPromptBlock(), contains('不许装懂'));
    });

    test('不是 JSON 或什么都没有时返回 null', () {
      expect(
        PostAnalyzer.parse('不是 JSON', postId: 'p', model: 'm'),
        isNull,
      );
      expect(
        PostAnalyzer.parse('{}', postId: 'p', model: 'm'),
        isNull,
      );
    });

    test('实体最多留 8 个，重复的去掉', () {
      final entities = List.generate(12, (i) => '"e$i"').join(',');
      final result = PostAnalyzer.parse(
        '{"tone":"分享","entities":[$entities,"e0"],"confidence":0.6}',
        postId: 'p',
        model: 'm',
      );

      expect(result!.entities, hasLength(8));
    });
  });

  group('提示词', () {
    test('要求判断语气、领域、梗、情绪、圈内角度', () {
      final prompt = PostAnalyzer.systemPrompt();
      expect(prompt, contains('玩梗'));
      expect(prompt, contains('感伤'));
      expect(prompt, contains('joke_mechanism'));
      expect(prompt, contains('insider_angle'));
      expect(prompt, contains('confidence'));
    });

    test('给评论者的提示块带上语气和领域', () {
      final block = PostUnderstanding(
        postId: 'p',
        tone: '玩梗',
        domain: '游戏',
        point: '自嘲抽卡',
        jokeMechanism: '反差',
        confidence: 0.9,
        updatedAt: DateTime(2026),
      ).toPromptBlock();

      expect(block, contains('语气：玩梗'));
      expect(block, contains('领域：游戏'));
      expect(block, contains('笑点：反差'));
    });
  });
}
