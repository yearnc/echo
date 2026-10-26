import 'package:echo/domain/models/custom_resident.dart';
import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/services/community_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final residents = [
    CustomResident(
      id: 'r1',
      name: '听你说完',
      bio: '便利店值夜班',
      description: '住在街角，喜欢听人说话',
      tags: const ['树洞'],
      createdAt: DateTime(2026, 10, 12),
    ),
    CustomResident(
      id: 'r2',
      name: '追光的K',
      bio: '下班后扫街拍照',
      description: '摄影爱好者',
      tags: const ['摄影'],
      createdAt: DateTime(2026, 10, 12),
    ),
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
    residents: residents,
    posts: posts,
    query: query,
  );

  test('名字、简介、设定、标签都算"他是谁"的一部分', () {
    expect(search('听').residents.single.id, 'r1');
    expect(search('拍照').residents.single.id, 'r2', reason: '简介里的话也算');
    expect(search('树洞').residents.single.id, 'r1', reason: '标签也算');
    expect(search('街角').residents.single.id, 'r1', reason: '详细设定也算');
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
      residents: const [],
      posts: many,
      query: '一样',
      limit: 10,
    );

    expect(result.posts.length, 10);
  });
}
