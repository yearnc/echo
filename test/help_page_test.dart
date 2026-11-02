import 'package:echo/features/help/help_faq.dart';
import 'package:echo/features/help/help_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('帮助一级页只显示分类', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpPage()));
    expect(find.text('常见问题'), findsOneWidget);
    expect(find.text('固定住民'), findsOneWidget);
    expect(find.text('小游戏'), findsOneWidget);
    expect(find.text('私信怎么用？'), findsNothing);
  });

  testWidgets('帮助二级页显示具体问题与答案', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HelpCategoryPage(categoryId: 'games')),
    );
    expect(find.text('小游戏'), findsOneWidget);
    expect(find.text('能同时邀请好几个人吗？'), findsOneWidget);
    expect(find.textContaining('「上传游戏」是什么？'), findsOneWidget);
  });

  test('分类 id 不重复，问题都有答案', () {
    final ids = <String>{};
    for (final category in helpFaq) {
      expect(ids.add(category.id), isTrue, reason: '分类 id 重复：${category.id}');
      expect(category.items, isNotEmpty);
      for (final item in category.items) {
        expect(item.question.trim(), isNotEmpty);
        expect(item.answer.trim(), isNotEmpty);
      }
    }
    expect(helpCategoryById('games')?.title, '小游戏');
    expect(helpCategoryById('missing'), isNull);
  });
}
