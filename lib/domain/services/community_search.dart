import '../models/ai_persona.dart';
import '../models/post.dart';

/// 社区里的搜索（B6 收尾）。**纯逻辑，不碰数据库**。
///
/// 搜的是你自己这个社区里的东西：住民和帖子。没有"全网搜索"这回事——
/// 数据全在本机，这也正是它的隐私承诺。
class CommunitySearch {
  const CommunitySearch._();

  /// 一次搜索的结果。
  static SearchResult run({
    required List<AiPersona> personas,
    required List<Post> posts,
    required String query,
    int limit = 30,
  }) {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return SearchResult.empty;

    return SearchResult(
      personas: [
        for (final persona in personas)
          if (_matchesPersona(persona, keyword)) persona,
      ].take(limit).toList(growable: false),
      posts: [
        for (final post in posts)
          if (post.content.toLowerCase().contains(keyword) ||
              (post.topicName ?? '').toLowerCase().contains(keyword))
            post,
      ].take(limit).toList(growable: false),
    );
  }

  /// 名字、简介、圈子、以及他说话的样子，都算"他是谁"的一部分。
  static bool _matchesPersona(AiPersona persona, String keyword) {
    return persona.name.toLowerCase().contains(keyword) ||
        persona.bio.toLowerCase().contains(keyword) ||
        persona.circle.toLowerCase().contains(keyword) ||
        persona.personalityType.toLowerCase().contains(keyword);
  }
}

/// 搜索出来的东西。分成两堆，因为它们是两种去处（一个人、一条帖子）。
class SearchResult {
  const SearchResult({required this.personas, required this.posts});

  final List<AiPersona> personas;
  final List<Post> posts;

  static const SearchResult empty = SearchResult(
    personas: [],
    posts: [],
  );

  bool get isEmpty => personas.isEmpty && posts.isEmpty;
}
