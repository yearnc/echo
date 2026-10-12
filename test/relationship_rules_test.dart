import 'package:echo/domain/services/relationship_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// 关系推进是纯逻辑，所以这里不碰数据库——"发帖两周之后他会不会跟你熟起来"
/// 不该只能靠真的等两周来验证。
void main() {
  final t0 = DateTime(2026, 10, 12, 9);

  RelationshipState apply(
    RelationshipState from,
    RelationshipEvent event, {
    DateTime? at,
  }) => RelationshipRules.apply(current: from, event: event, at: at ?? t0);

  group('档位查表', () {
    test('0 分是陌生，攒够 3 分才眼熟', () {
      expect(RelationshipRules.levelFor(0), 0);
      expect(RelationshipRules.levelFor(2), 0);
      expect(RelationshipRules.levelFor(3), 1);
    });

    test('每一档的门槛都是含等号的', () {
      expect(RelationshipRules.levelFor(9), 1);
      expect(RelationshipRules.levelFor(10), 2);
      expect(RelationshipRules.levelFor(21), 2);
      expect(RelationshipRules.levelFor(22), 3);
      expect(RelationshipRules.levelFor(39), 3);
      expect(RelationshipRules.levelFor(40), 4);
    });

    test('再多也不会超过最后一档', () {
      expect(RelationshipRules.levelFor(100000), 4);
    });

    test('档位名说得出人话', () {
      expect(RelationshipState.stranger('p1').tierLabel, '陌生');
      expect(
        const RelationshipState(personaId: 'p1', level: 2).tierLabel,
        '互关',
      );
      expect(const RelationshipState(personaId: 'p1', level: 4).tierLabel, '好友');
    });
  });

  group('一次互动推进多少', () {
    test('第一次评论：3 分，刚好到眼熟', () {
      final next = apply(RelationshipState.stranger('p1'), RelationshipEvent.comment);

      expect(next.intimacy, 3);
      expect(next.level, 1);
      expect(next.interactionCount, 1);
      expect(next.lastInteractionAt, t0);
    });

    test('点赞只有 1 分，一次点赞还到不了眼熟', () {
      final next = apply(RelationshipState.stranger('p1'), RelationshipEvent.like);

      expect(next.intimacy, 1);
      expect(next.level, 0);
      expect(next.interactionCount, 1);
    });

    test('私信最重，回复次之', () {
      expect(RelationshipEvent.message.weight, 5);
      expect(RelationshipEvent.reply.weight, 4);
      expect(RelationshipEvent.follow.weight, 2);
    });
  });

  group('亲近度的冷却', () {
    test('同一天里连着两次评论，亲近度只长一次，次数照记', () {
      final first = apply(RelationshipState.stranger('p1'), RelationshipEvent.comment);
      final second = apply(first, RelationshipEvent.comment, at: t0.add(const Duration(hours: 4)));

      expect(second.intimacy, 3, reason: '四小时之内，亲近感不该翻倍');
      expect(second.interactionCount, 2, reason: '但"你们互动过两次"是真事');
    });

    test('隔够六小时，才重新长一次', () {
      final first = apply(RelationshipState.stranger('p1'), RelationshipEvent.comment);
      final second = apply(first, RelationshipEvent.comment, at: t0.add(const Duration(hours: 6)));

      expect(second.intimacy, 6);
      expect(second.interactionCount, 2);
    });

    test('冷却期里换成别的互动，也一样不长', () {
      final first = apply(RelationshipState.stranger('p1'), RelationshipEvent.like);
      final second = apply(first, RelationshipEvent.comment, at: t0.add(const Duration(minutes: 30)));

      expect(second.intimacy, 1);
      expect(second.interactionCount, 2);
    });

    test('时间倒着走（时钟被改过）也不会倒扣', () {
      final first = apply(RelationshipState.stranger('p1'), RelationshipEvent.comment);
      final second = apply(first, RelationshipEvent.comment, at: t0.subtract(const Duration(days: 1)));

      expect(second.intimacy, 3);
      expect(second.interactionCount, 2);
    });
  });

  group('档位只升不降', () {
    test('库里已经是熟人时，一次点赞不会把它打回陌生', () {
      const current = RelationshipState(personaId: 'p1', level: 3, intimacy: 22);
      final next = apply(current, RelationshipEvent.like, at: t0.add(const Duration(days: 1)));

      expect(next.level, 3);
      expect(next.intimacy, 23);
    });

    test('攒够之后一档一档往上走', () {
      var state = RelationshipState.stranger('p1');
      final days = <int>[];

      for (var day = 0; day < 20; day++) {
        final at = t0.add(Duration(days: day));
        final before = state.level;
        state = apply(state, RelationshipEvent.comment, at: at);
        if (state.level != before) days.add(state.level);
      }

      expect(days, [1, 2, 3, 4], reason: '眼熟 → 互关 → 熟人 → 好友，一路走上去');
      expect(state.level, 4);
      expect(state.intimacy, 60);
    });
  });

  group('关注是关系走到那一步的结果', () {
    test('还没到互关，谁也不会关注谁', () {
      expect(RelationshipRules.followAfter('none', 1), 'none');
    });

    test('到了互关档，他关注了你', () {
      expect(RelationshipRules.followAfter('none', 2), 'followed');
    });

    test('你先关注过他，那就是互关', () {
      expect(RelationshipRules.followAfter('following', 2), 'mutual');
    });

    test('已经是互关了，再往前走还是互关', () {
      expect(RelationshipRules.followAfter('mutual', 4), 'mutual');
    });

    test('一路互动到互关档，关注状态跟着变', () {
      var state = RelationshipState.stranger('p1');
      for (var day = 0; day < 5; day++) {
        state = apply(state, RelationshipEvent.comment, at: t0.add(Duration(days: day)));
      }

      expect(state.level, 2);
      expect(state.followState, 'followed');
    });
  });

  group('认数据库里的字符串', () {
    test('认得的照认', () {
      expect(RelationshipRules.eventFrom('comment'), RelationshipEvent.comment);
      expect(RelationshipRules.eventFrom('reply'), RelationshipEvent.reply);
      expect(RelationshipRules.eventFrom('message'), RelationshipEvent.message);
      expect(RelationshipRules.eventFrom('follow'), RelationshipEvent.follow);
      expect(RelationshipRules.eventFrom('like'), RelationshipEvent.like);
    });

    test('不认识的一律当点赞——宁可少涨一点，也不把关系推近', () {
      expect(RelationshipRules.eventFrom('repost'), RelationshipEvent.like);
      expect(RelationshipRules.eventFrom(''), RelationshipEvent.like);
    });
  });

  group('水位', () {
    test('时钟被往回调，水位不跟着倒退', () {
      final first = apply(
        RelationshipState.stranger('p1'),
        RelationshipEvent.comment,
      );
      final back = apply(
        first,
        RelationshipEvent.comment,
        at: t0.subtract(const Duration(days: 1)),
      );

      expect(back.lastInteractionAt, t0, reason: '水位留在最后一次真正的互动上');
    });
  });
}
