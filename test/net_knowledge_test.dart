import 'package:echo/domain/services/net_knowledge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('临时网民常识库', () {
    test('玩梗帖会优先拿到接梗的分寸', () {
      final picked = NetKnowledge.pick(
        tone: '玩梗',
        domain: '游戏',
        entities: const ['原神'],
      );
      expect(picked, isNotEmpty);
      expect(picked.take(2).map((entry) => entry.category), contains('接梗'));
    });

    test('求助帖会先给“只陪不劝”', () {
      final picked = NetKnowledge.pick(
        tone: '求助',
        domain: '情感',
        entities: const [],
      );
      expect(picked.first.id, 'no_advice');
    });

    test('同样的帖子每次挑到的都是同一批', () {
      List<String> ids() => [
        for (final entry in NetKnowledge.pick(
          tone: '吐槽',
          domain: '生活',
          entities: const ['加班'],
        ))
          entry.id,
      ];
      expect(ids(), ids());
    });

    test('块里有小标题，也提醒不要照抄', () {
      final block = NetKnowledge.blockFor(
        tone: '日常',
        domain: '生活',
        entities: const [],
      );
      expect(block, contains('网民的说话方式'));
      expect(block, contains('不是模板'));
    });

    test('最多给 limit 条', () {
      final picked = NetKnowledge.pick(
        tone: '日常',
        domain: '生活',
        entities: const [],
        limit: 3,
      );
      expect(picked, hasLength(3));
    });
  });
}
