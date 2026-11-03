import 'package:echo/domain/models/resident_memory.dart';
import 'package:echo/domain/services/memory_maintenance_service.dart';
import 'package:echo/domain/services/memory_text.dart';
import 'package:flutter_test/flutter_test.dart';

ResidentMemory _memory(String id, String summary, {String content = ''}) {
  final at = DateTime(2026, 11, 3);
  return ResidentMemory(
    id: id,
    residentId: 'resident_001',
    summary: summary,
    content: content,
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  group('规范化与指纹', () {
    test('剥掉标点、语气词和渠道前缀', () {
      expect(
        normalizeMemoryText('他回我：喜欢喝茉莉花茶呀！'),
        normalizeMemoryText('喜欢喝茉莉花茶'),
      );
    });

    test('同一件事的指纹一致，不同的事不一致', () {
      expect(
        memoryFingerprint('他喜欢喝茉莉花茶。'),
        memoryFingerprint('对方喜欢喝茉莉花茶'),
      );
      expect(
        memoryFingerprint('他喜欢喝茉莉花茶'),
        isNot(memoryFingerprint('他养了一只猫')),
      );
    });
  });

  group('相似度去重', () {
    test('换个说法、换个人称算同一件事', () {
      expect(
        isDuplicateMemory(
          summary: '他喜欢喝茉莉花茶',
          otherSummary: '对方喜欢喝茉莉花茶。',
        ),
        isTrue,
      );
    });

    test('“喝茶”不会被并进“喝茉莉花茶”', () {
      expect(
        isDuplicateMemory(
          summary: '他喜欢喝茶',
          otherSummary: '他喜欢喝茉莉花茶',
        ),
        isFalse,
      );
    });

    test('完全相同的长句算重复', () {
      expect(
        isDuplicateMemory(
          summary: '他下周三要去金州参加比赛，早上七点出发',
          otherSummary: '他下周三要去金州参加比赛，早上七点出发。',
        ),
        isTrue,
      );
    });

    test('共同标签会放宽阈值', () {
      expect(
        isDuplicateMemory(
          summary: '他下周三要考试，最近很累',
          tags: const ['考试'],
          otherSummary: '他下周三要考试，最近真的很累',
          otherTags: const ['考试'],
        ),
        isTrue,
      );
    });
  });

  group('写入闸门', () {
    test('放行真实偏好', () {
      expect(memoryWriteGate(summary: '他喜欢喝茉莉花茶'), isEmpty);
    });

    test('挡住寒暄、图片占位、技术讨论和不确定的话', () {
      expect(memoryWriteGate(summary: '晚安'), isNotEmpty);
      expect(memoryWriteGate(summary: '他发来一张图片'), isNotEmpty);
      expect(memoryWriteGate(summary: '记忆系统的提示词要改'), isNotEmpty);
      expect(memoryWriteGate(summary: '他好像要考试'), isNotEmpty);
      expect(memoryWriteGate(summary: '好'), isNotEmpty);
    });
  });

  group('整理预扫', () {
    test('把重复条目聚成组，不碰无关条目', () {
      final clusters = duplicateClusters([
        _memory('a', '他喜欢喝茉莉花茶'),
        _memory('b', '对方喜欢喝茉莉花茶。'),
        _memory('c', '他养了一只猫'),
        _memory('d', '他养了一只猫。'),
        _memory('e', '他下周三去比赛'),
      ]);
      expect(clusters, hasLength(2));
      expect(clusters.first, hasLength(2));
    });

    test('整理间隔与重试间隔', () {
      final now = DateTime(2026, 11, 3, 12);
      expect(maintenanceDue(now: now), isTrue);
      expect(
        maintenanceDue(
          now: now,
          lastRunAt: now.subtract(const Duration(hours: 2)),
        ),
        isFalse,
      );
      expect(
        maintenanceDue(
          now: now,
          lastAttemptAt: now.subtract(const Duration(minutes: 20)),
        ),
        isFalse,
      );
      expect(
        maintenanceDue(
          now: now,
          lastRunAt: now.subtract(const Duration(days: 2)),
          lastAttemptAt: now.subtract(const Duration(hours: 2)),
        ),
        isTrue,
      );
    });
  });
}
