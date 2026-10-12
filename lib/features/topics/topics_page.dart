import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/post_repository.dart';
import '../../domain/models/post.dart';
import '../../domain/services/trending.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';

/// 话题页（B6 的收尾）：社区里正在聊的那些话题。
///
/// 排序用的是热榜那套算法（[[Trending.rankTopics]]，纯函数、有单测），
/// 所以"热门话题"和热榜页上那一块永远是同一个答案。
class TopicsPage extends ConsumerWidget {
  const TopicsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(feedPostsProvider('echo'));

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          '话题',
          style: TextStyle(
            color: EchoColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      bottomNavigationBar: const SafeArea(child: AiDisclaimerBar()),
      body: posts.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: EchoColors.primary)),
        error: (error, _) => Center(
          child: Text(
            '读不到话题：$error',
            style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
          ),
        ),
        data: (list) {
          final topics = Trending.rankTopics(list, now: DateTime.now(), limit: 40);
          if (topics.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 44),
                child: Text(
                  '还没有人给帖子加过话题。发帖的时候带上一个，这里就有了。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: EchoColors.textFaint,
                    fontSize: 13,
                    height: 1.8,
                  ),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: topics.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: EchoColors.divider),
            itemBuilder: (context, index) => _TopicTile(
              rank: index + 1,
              topic: topics[index],
            ),
          );
        },
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.rank, required this.topic});

  final int rank;
  final TopicHeat topic;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(RoutePaths.topic(topic.name)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$rank',
                style: TextStyle(
                  color: rank <= 3 ? EchoColors.hot : EchoColors.textFaint,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${topic.name}',
                    style: TextStyle(
                      color: EchoColors.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${topic.postCount} 条帖子',
                    style: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: EchoColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}

/// 某个话题下的帖子。
class TopicDetailPage extends ConsumerWidget {
  const TopicDetailPage({super.key, required this.topic});

  final String topic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(feedPostsProvider('echo'));

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          '#$topic',
          style: TextStyle(
            color: EchoColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      bottomNavigationBar: const SafeArea(child: AiDisclaimerBar()),
      body: posts.when(
        loading: () =>
            Center(child: CircularProgressIndicator(color: EchoColors.primary)),
        error: (error, _) => Center(
          child: Text(
            '读不到这个话题：$error',
            style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
          ),
        ),
        data: (list) {
          final mine = [
            for (final post in list)
              if ((post.topicName ?? '').trim() == topic) post,
          ];
          if (mine.isEmpty) {
            return Center(
              child: Text(
                '这个话题下还没有帖子。',
                style: TextStyle(color: EchoColors.textFaint, fontSize: 13),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: mine.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _TopicPostTile(post: mine[index]),
          );
        },
      ),
    );
  }
}

class _TopicPostTile extends StatelessWidget {
  const _TopicPostTile({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(RoutePaths.post(post.id)),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: EchoColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EchoColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              post.content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: EchoColors.text,
                fontSize: 13.5,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '♡ ${post.likeCount}　回复 ${post.commentCount}　'
              '${RelativeTime.format(post.createdAt)}',
              style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}
