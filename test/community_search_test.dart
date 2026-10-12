import 'package:echo/domain/models/ai_persona.dart';
import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/services/community_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final personas = [
    const AiPersona(id: 'p1', name: '听你说完', bio: '便利店值夜班', circle: '树洞'),
    const AiPersona(id: 'p2', name: '追光的K', bio: '下班后扫街拍照', circle: '摄影'),
  ];
  final posts = [
    Post(
      id: 'a',
      content: '今天的光很好',
      topicName: '摄影',
      createdAt: DateTime(2026, 10, 12),
    ),
    Post(id: 'b', content: '楼下新开了家面馆', createdAt: DateTime(2026, 10, 12)),
  ];

  SearchResult search(String query) => CommunitySearch.run(
    personas: personas,
    posts: posts,
    query: query,
  );

  test('名字、简介、圈子都算"他是谁"的一部分', () {
    expect(search('听').personas.single.id, 'p1');
    expect(search('拍照').personas.single.id, 'p2', reason: '简介里的话也算');
    expect(search('树洞').personas.single.id, 'p1', reason: '圈子也算');
  });

  test('帖子搜正文，也搜话题', () {
    expect(search('面馆').posts.single.id, 'b');
    expect(search('摄影').posts.single.id, 'a', reason: '话题是帖子的一部分');
  });

  test('两头都空的关键词不返回任何东西——不是"返回全部"', () {
    expect(search('   ').isEmpty, isTrue);
    expect(search('').isEmpty, isTrue);
  });

  test('搜不到就是空的，不硬凑', () {
    expect(search('这个词肯定没有').isEmpty, isTrue);
  });

  test('结果有上限', () {
    final many = [
      for (var i = 0; i < 50; i++)
        Post(
          id: 'p$i',
          content: '一样的句子',
          createdAt: DateTime(2026, 10, 12),
        ),
    ];

    final result = CommunitySearch.run(
      personas: const [],
      posts: many,
      query: '一样',
      limit: 10,
    );

    expect(result.posts.length, 10);
  });
}
