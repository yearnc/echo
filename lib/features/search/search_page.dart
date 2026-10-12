import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../domain/models/ai_persona.dart';
import '../../domain/models/post.dart';
import '../../domain/services/community_search.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';
import '../shared_widgets/user_avatar.dart';

/// 搜索（B6 的收尾）。
///
/// 搜的只有本机这些东西：住民和帖子。没有"全网搜索"——数据全在这台设备上，
/// 那本来就是它的隐私承诺。过滤逻辑在 [[CommunitySearch]] 里（纯函数、有单测）。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _input = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final personas = ref.watch(personasProvider).value ?? const <AiPersona>[];
    final posts = ref.watch(feedPostsProvider('echo')).value ?? const <Post>[];
    final result = CommunitySearch.run(
      personas: personas,
      posts: posts,
      query: _query,
    );

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        titleSpacing: 0,
        title: TextField(
          controller: _input,
          autofocus: true,
          onChanged: (value) => setState(() => _query = value),
          style: TextStyle(color: EchoColors.text, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: '搜住民、帖子、话题…',
            hintStyle: TextStyle(color: EchoColors.textFaint, fontSize: 14),
            filled: true,
            fillColor: EchoColors.bg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 9,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: const [SizedBox(width: 12)],
      ),
      bottomNavigationBar: const SafeArea(child: AiDisclaimerBar()),
      body: switch (result.isEmpty) {
        true when _query.trim().isEmpty => const _Hint(
          text: '搜点什么吧——住民的名字、他说过的话、帖子里的一句话。',
        ),
        true => const _Hint(text: '没找到。换个词试试？'),
        false => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (result.personas.isNotEmpty) ...[
              const _SectionTitle('住民'),
              const SizedBox(height: 6),
              for (final persona in result.personas)
                _PersonaTile(persona: persona),
              const SizedBox(height: 14),
            ],
            if (result.posts.isNotEmpty) ...[
              const _SectionTitle('帖子'),
              const SizedBox(height: 8),
              for (final post in result.posts) ...[
                _PostTile(post: post),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      },
    );
  }
}

class _PersonaTile extends StatelessWidget {
  const _PersonaTile({required this.persona});

  final AiPersona persona;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(RoutePaths.resident(persona.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            UserAvatar(
              name: persona.name,
              avatarRef: persona.avatar,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    persona.name,
                    style: TextStyle(color: EchoColors.text, fontSize: 13.5),
                  ),
                  if (persona.bio.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      persona.bio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: EchoColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post});

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
            if ((post.topicName ?? '').isNotEmpty) ...[
              Text(
                '#${post.topicName}',
                style: TextStyle(color: EchoColors.primary, fontSize: 11.5),
              ),
              const SizedBox(height: 4),
            ],
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
            const SizedBox(height: 7),
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
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        child: Text(
          text,
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
}
