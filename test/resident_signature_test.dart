import 'dart:math';

import 'package:echo/domain/models/resident_post.dart';
import 'package:echo/domain/services/resident_signature.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「谁在什么时候换签名」是纯逻辑，不该只能靠干等三天来验证。
void main() {
  final at = DateTime(2026, 9, 30, 14);

  ResidentPostDraft draft(String id, {String? bio}) =>
      ResidentPostDraft(personaId: id, content: '今天挺好的。', newBio: bio);

  group('谁会被挑中', () {
    test('没人给新签名时，一个都不改', () {
      expect(
        ResidentSignature.pick(
          drafts: [draft('a'), draft('b')],
          at: at,
          lastChangedAt: const {},
          random: Random(1),
          chance: 1,
        ),
        isNull,
      );
    });

    test('空签名不算候选', () {
      expect(
        ResidentSignature.pick(
          drafts: [draft('a', bio: '   '), draft('b', bio: '')],
          at: at,
          lastChangedAt: const {},
          random: Random(1),
          chance: 1,
        ),
        isNull,
      );
    });

    test('写成小作文的不算签名', () {
      final long = '今天下午在图书馆看了一下午的书，出来的时候天都黑了，路灯一盏一盏亮起来。';
      expect(
        ResidentSignature.pick(
          drafts: [draft('a', bio: long)],
          at: at,
          lastChangedAt: const {},
          random: Random(1),
          chance: 1,
        ),
        isNull,
        reason: '超过 ${ResidentSignature.maxLength} 字就不像签名了',
      );
    });

    test('条件都满足时挑出来的，一定在候选里', () {
      final picked = ResidentSignature.pick(
        drafts: [draft('a'), draft('b', bio: '换个签名'), draft('c')],
        at: at,
        lastChangedAt: const {},
        random: Random(1),
        chance: 1,
      );

      expect(picked, isNotNull);
      expect(picked!.personaId, 'b', reason: '只有他给了签名');
      expect(picked.newBio, '换个签名');
    });

    test('概率没到就一个都不改', () {
      // 一次跑一百遍：chance 为 0，一次都不该中
      for (var i = 0; i < 100; i++) {
        expect(
          ResidentSignature.pick(
            drafts: [draft('a', bio: '换个签名')],
            at: at,
            lastChangedAt: const {},
            random: Random(i),
            chance: 0,
          ),
          isNull,
        );
      }
    });
  });

  group('冷却', () {
    test('刚改过的人不再改', () {
      final last = at.subtract(const Duration(hours: 2));

      for (var i = 0; i < 100; i++) {
        expect(
          ResidentSignature.pick(
            drafts: [draft('a', bio: '换个签名')],
            at: at,
            lastChangedAt: {'a': last},
            random: Random(i),
            chance: 1,
          ),
          isNull,
          reason: '冷却期内，连抽中都不该抽中',
        );
      }
    });

    test('冷却过了就又能改了', () {
      final last = at.subtract(ResidentSignature.cooldown);

      expect(
        ResidentSignature.pick(
          drafts: [draft('a', bio: '换个签名')],
          at: at,
          lastChangedAt: {'a': last},
          random: Random(1),
          chance: 1,
        ),
        isNotNull,
      );
    });

    test('在冷却里的被跳过，剩下的人照常', () {
      final last = at.subtract(const Duration(minutes: 30));

      for (var i = 0; i < 50; i++) {
        final picked = ResidentSignature.pick(
          drafts: [draft('a', bio: '换个签名'), draft('b', bio: '换个签名')],
          at: at,
          lastChangedAt: {'a': last},
          random: Random(i),
          chance: 1,
        );

        expect(picked?.personaId, 'b');
      }
    });
  });
}
