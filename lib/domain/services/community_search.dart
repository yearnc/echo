import '../models/custom_resident.dart';
import '../models/post.dart';

/// 社区里的搜索（B6 收尾）。**纯逻辑，不碰数据库**。
///
/// 搜的是你自己这个社区里的东西：固定住民和帖子。没有"全网搜索"这回事——
/// 数据全在本机，这也正是它的隐私承诺。
class CommunitySearch {
  const CommunitySearch._();

  /// 一次搜索的结果。
  static SearchResult run({
    required List<CustomResident> residents,
    required List<Post> posts,
    required String query,
    int limit = 30,
  }) {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return SearchResult.empty;

    return SearchResult(
      residents: [
        for (final resident in residents)
          if (_matchesResident(resident, keyword)) resident,
      ].take(limit).toList(growable: false),
      posts: [
        for (final post in posts)
          if (post.content.toLowerCase().contains(keyword) ||
              (post.topicName ?? '').toLowerCase().contains(keyword))
            post,
      ].take(limit).toList(growable: false),
    );
  }

  /// 名字、简介、设定、标签，都算"他是谁"的一部分。
  static bool _matchesResident(CustomResident resident, String keyword) {
    return resident.name.toLowerCase().contains(keyword) ||
        resident.bio.toLowerCase().contains(keyword) ||
        resident.description.toLowerCase().contains(keyword) ||
        resident.tags.any((tag) => tag.toLowerCase().contains(keyword));
  }
}

/// 搜索出来的东西。分成两堆，因为它们是两种去处（一个人、一条帖子）。
class SearchResult {
  const SearchResult({required this.residents, required this.posts});

  final List<CustomResident> residents;
  final List<Post> posts;

  static const SearchResult empty = SearchResult(
    residents: [],
    posts: [],
  );

  bool get isEmpty => residents.isEmpty && posts.isEmpty;
}
