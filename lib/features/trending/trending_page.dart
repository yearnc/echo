import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../domain/models/post.dart';
import '../../domain/services/community_calendar.dart';
import '../../domain/services/trending.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';
import '../shared_widgets/user_avatar.dart';

/// 今天的热榜（B6）。
///
/// 排序算法在 [[Trending]] 里（纯逻辑、有单测），这里只负责摆。
/// 榜单顶上加了一条"最近大家身边"——降温、长假这类事，
/// 是让这个社区看起来像在**同一段日子里**的东西。
class TrendingPage extends ConsumerWidget {
  const TrendingPage({super.key});

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
          '今天的热榜',
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
            '读不到热榜：$error',
            style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
          ),
        ),
        data: (list) {
          final now = DateTime.now();
          final hot = Trending.rankPosts(list, now: now, limit: 5);
          final topics = Trending.rankTopics(list, now: now, limit: 6);
          final residents = Trending.rankResidents(list, now: now, limit: 6);
          final campus = CommunityCalendar.of(now);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              if (campus.isNotEmpty) ...[
                _CampusStrip(events: campus),
                const SizedBox(height: 18),
              ],
              _SectionTitle('今日热帖'),
              const SizedBox(height: 8),
              if (hot.isEmpty)
                const _Hint('还没什么上榜的东西。')
              else
                for (var i = 0; i < hot.length; i++)
                  _HotPostTile(rank: i + 1, post: hot[i]),
              if (topics.isNotEmpty) ...[
                const SizedBox(height: 22),
                _SectionTitle('热门话题'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final topic in topics)
                      _TopicChip(topic: topic),
                  ],
                ),
              ],
              if (residents.isNotEmpty) ...[
                const SizedBox(height: 22),
                _SectionTitle('这两天话最多的人'),
                const SizedBox(height: 10),
                for (final resident in residents)
                  _ResidentRow(resident: resident),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 最近大家身边正发生的事。榜首那一条，大家都在这件事里。
class _CampusStrip extends StatelessWidget {
  const _CampusStrip({required this.events});

  final List<CommunityEvent> events;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: EchoColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.wb_twilight, size: 15, color: EchoColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '最近大家身边：${events.map((event) => event.title).join(' · ')}',
              style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _HotPostTile extends StatelessWidget {
  const _HotPostTile({required this.rank, required this.post});

  final int rank;
  final Post post;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(RoutePaths.post(post.id)),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                style: TextStyle(
                  color: rank <= 3 ? EchoColors.hot : EchoColors.textFaint,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: EchoColors.text,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '♡ ${post.likeCount}　回复 ${post.commentCount}　'
                    '${RelativeTime.format(post.createdAt)}',
                    style: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({required this.topic});

  final TopicHeat topic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: EchoColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '#${topic.name}　${topic.postCount}',
        style: TextStyle(color: EchoColors.primary, fontSize: 12.5),
      ),
    );
  }
}

class _ResidentRow extends ConsumerWidget {
  const _ResidentRow({required this.resident});

  final ActiveResident resident;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = ref.watch(
      customResidentAnyByIdProvider(resident.personaId),
    );
    final name = stored?.name ?? '已离开的住民';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          UserAvatar(name: name, avatarRef: stored?.avatarAsset, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(color: EchoColors.text, fontSize: 13.5),
            ),
          ),
          Text(
            '${resident.postCount} 条动态',
            style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: EchoColors.textFaint,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(
        text,
        style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5),
      ),
    );
  }
}
