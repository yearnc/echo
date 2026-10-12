import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/relationship_repository.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';
import '../shared_widgets/user_avatar.dart';

/// 关注与粉丝（B5 的收尾）。
///
/// 两个方向分开放，因为它们是两件事：**我关注的人**是我自己挑的，
/// **关注我的人**是他挑的。混成一个"关系列表"，两边都会看不懂。
class FollowsPage extends ConsumerWidget {
  const FollowsPage({super.key, this.initialTab = 0});

  /// 0 = 我关注的，1 = 关注我的。
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(followingProvider);
    final followers = ref.watch(followersProvider);

    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: Scaffold(
        backgroundColor: EchoColors.bg,
        appBar: AppBar(
          backgroundColor: EchoColors.surface,
          elevation: 0,
          iconTheme: IconThemeData(color: EchoColors.text),
          title: Text(
            '关注',
            style: TextStyle(
              color: EchoColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          bottom: TabBar(
            labelColor: EchoColors.primary,
            unselectedLabelColor: EchoColors.textMuted,
            indicatorColor: EchoColors.primary,
            tabs: [
              Tab(text: '我关注的 ${following.length}'),
              Tab(text: '关注我的 ${followers.length}'),
            ],
          ),
        ),
        bottomNavigationBar: const SafeArea(child: AiDisclaimerBar()),
        body: TabBarView(
          children: [
            _PeopleList(
              ids: following,
              empty: '还没关注谁。去别人的主页点那个「关注」试试。',
            ),
            _PeopleList(
              ids: followers,
              empty: '还没有人关注你。聊得多了，会有的。',
            ),
          ],
        ),
      ),
    );
  }
}

class _PeopleList extends StatelessWidget {
  const _PeopleList({required this.ids, required this.empty});

  final List<String> ids;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Text(
            empty,
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

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: ids.length,
      itemBuilder: (context, index) => _PersonTile(personaId: ids[index]),
    );
  }
}

class _PersonTile extends ConsumerWidget {
  const _PersonTile({required this.personaId});

  final String personaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persona = ref.watch(personaByIdProvider(personaId));
    final name = persona?.name ?? '社区住民';

    return InkWell(
      onTap: () => context.push(RoutePaths.resident(personaId)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            UserAvatar(
              name: name,
              avatarRef: persona?.avatar,
              size: 42,
              showRing: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: EchoColors.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if ((persona?.bio ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      persona!.bio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: EchoColors.textMuted,
                        fontSize: 12.5,
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
