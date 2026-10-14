import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/clear_journal_repository.dart';
import 'package:echo/domain/models/clear_journal.dart';
import 'package:flutter_test/flutter_test.dart';

/// 清醒模式价值重建闭环的仓储层测试（内存库，不碰真实文件）。
void main() {
  late AppDatabase db;
  late ClearJournalRepository journal;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    journal = ClearJournalRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('心情（B11 的周报情绪维度）', () {
    test('记了心情就读得回来，没记就是没记', () async {
      await journal.addAction(title: '跑了 3 公里', mood: RealActionMood.steady);
      await journal.addAction(title: '看完了半本书');

      final actions = await journal.watchActions().first;
      final byTitle = {for (final a in actions) a.title: a};

      expect(byTitle['跑了 3 公里']!.mood, RealActionMood.steady);
      // 没选心情**不是**"心情为空"：它就是一个可以空着的东西。
      expect(byTitle['看完了半本书']!.mood, isNull);
    });

    test('数心情：多的在前，一样多的按固定顺序', () {
      final tally = tallyMoods([
        RealActionMood.calm,
        RealActionMood.steady,
        RealActionMood.steady,
        RealActionMood.happy,
        RealActionMood.calm,
      ]);

      expect(tally.first.$1, RealActionMood.steady);
      expect(tally.first.$2, 2);
      expect(tally.map((e) => e.$1), [
        RealActionMood.steady,
        RealActionMood.calm,
        RealActionMood.happy,
      ]);
      // 一条都没有时不该凭空冒出一个"没有心情"
      expect(tallyMoods(const []), isEmpty);
    });

    test('老库里的行读出来是"没记"，不是某个默认心情', () async {
      // 直接写库模拟迁移后的老行（mood 为空字符串）
      await db
          .into(db.realActions)
          .insert(
            RealActionsCompanion.insert(
              id: 'a_old',
              title: '很多年前的一件事',
              category: 'other',
              createdAt: 1,
            ),
          );

      final action = (await journal.watchActions().first).single;
      expect(action.mood, isNull);
    });
  });

  group('价值澄清', () {
    test('新增的条目按写入顺序读出', () async {
      await journal.addValue('家人的健康');
      await journal.addValue('把事情做扎实');

      final items = await journal.listValues();

      expect(items.map((item) => item.content), ['家人的健康', '把事情做扎实']);
      expect(items.map((item) => item.sortOrder), [0, 1]);
    });

    test('内容两端空白会被去掉', () async {
      await journal.addValue('  独处的时间  ');

      expect((await journal.listValues()).single.content, '独处的时间');
    });

    test('重排按给定顺序落库', () async {
      final first = await journal.addValue('第一条');
      final second = await journal.addValue('第二条');
      final third = await journal.addValue('第三条');

      await journal.reorderValues([third, first, second]);

      expect((await journal.listValues()).map((item) => item.content), [
        '第三条',
        '第一条',
        '第二条',
      ]);
    });

    test('修改内容不会打乱顺序', () async {
      final first = await journal.addValue('旧内容');
      await journal.addValue('第二条');

      await journal.updateValueContent(first, '新内容');

      final items = await journal.listValues();
      expect(items.first.content, '新内容');
      expect(items.first.sortOrder, 0);
      expect(items, hasLength(2));
    });

    test('删除一条后剩下的顺序被压紧，不留空洞', () async {
      await journal.addValue('A');
      final middle = await journal.addValue('B');
      await journal.addValue('C');

      await journal.deleteValue(middle);

      final items = await journal.listValues();
      expect(items.map((item) => item.content), ['A', 'C']);
      expect(items.map((item) => item.sortOrder), [
        0,
        1,
      ], reason: '空洞会让上移/下移的下标计算出错');
    });

    test('软删除的条目不会出现在订阅流里', () async {
      final id = await journal.addValue('要删的');
      await journal.deleteValue(id);

      expect(await journal.watchValues().first, isEmpty);
    });
  });

  group('真实行动', () {
    test('新增的记录带分类与描述', () async {
      await journal.addAction(
        title: '跑了 3 公里',
        description: '操场',
        category: RealActionCategory.sport,
      );

      final actions = await journal.watchActions().first;
      expect(actions, hasLength(1));
      expect(actions.single.title, '跑了 3 公里');
      expect(actions.single.category, RealActionCategory.sport);
    });

    test('列出时新的排在前面', () async {
      await journal.addAction(title: '较早的');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await journal.addAction(title: '较晚的');

      final actions = await journal.watchActions().first;
      expect(actions.first.title, '较晚的');
    });

    test('未知分类回落到"其他"，不会抛异常', () async {
      await db
          .into(db.realActions)
          .insert(
            RealActionsCompanion.insert(
              id: 'action_legacy',
              title: '旧数据',
              category: 'ancient_category',
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );

      final actions = await journal.watchActions().first;
      expect(actions.single.category, RealActionCategory.other);
    });

    test('软删除后不再出现，但行还留在库里', () async {
      final id = await journal.addAction(title: '要被删的');
      await journal.deleteAction(id);

      expect(await journal.watchActions().first, isEmpty);

      // 软删除是刻意的：周报要统计"这周记了几件"，硬删除会让已经算过的数
      // 在下次打开时变小——那比数字本身更可疑。
      final row = await (db.select(
        db.realActions,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.deletedAt, isNotNull);
    });
  });
}
