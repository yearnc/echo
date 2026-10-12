import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/relative_time.dart';
import '../../data/repositories/persona_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../data/repositories/relationship_repository.dart';
import '../../domain/models/ai_persona.dart';
import '../../domain/models/post.dart';
import '../../domain/services/relationship_rules.dart';
import '../shared_widgets/ai_disclaimer_bar.dart';
import '../shared_widgets/user_avatar.dart';

/// AI 住民的个人主页（规划书 §3.3）。
///
/// 点开评论区里的一个人，能看到他是谁、平常几点在哪儿、发过什么。
/// 这一步看着只是个资料页，其实是整个沉浸感的支点——只有住民看起来
/// 有自己的生活，评论区那些回应才不只是一行文字。
class ResidentPage extends ConsumerWidget {
  const ResidentPage({super.key, required this.personaId});

  final String personaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personas = ref.watch(personasProvider);

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          _find(personas.value)?.name ?? '个人主页',
          style: TextStyle(color: EchoColors.text, fontSize: 16),
        ),
      ),
      bottomNavigationBar: const SafeArea(child: AiDisclaimerBar()),
      body: personas.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: EchoColors.primary),
        ),
        error: (error, _) => _Message('读不到住民资料：$error'),
        data: (list) {
          final persona = _find(list);
          if (persona == null) return const _Message('没有找到这位住民。');
          return _Profile(persona: persona);
        },
      ),
    );
  }

  AiPersona? _find(List<AiPersona>? list) {
    for (final persona in list ?? const <AiPersona>[]) {
      if (persona.id == personaId) return persona;
    }
    return null;
  }
}

class _Profile extends ConsumerWidget {
  const _Profile({required this.persona});

  final AiPersona persona;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(residentPostsProvider(persona.id));
    final list = posts.value ?? const <Post>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _ProfileCard(persona: persona),
        const SizedBox(height: 16),
        _RelationshipCard(personaId: persona.id),
        if (persona.routines.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionTitle('他平常这个点'),
          const SizedBox(height: 8),
          _RoutineCard(routines: persona.routines),
        ],
        const SizedBox(height: 18),
        _SectionTitle('他发过的'),
        const SizedBox(height: 10),
        if (posts.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (list.isEmpty)
          const _Hint('他还没发过什么。')
        else
          for (final post in list) ...[
            _ResidentPostTile(post: post),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.persona});

  final AiPersona persona;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                name: persona.name,
                avatarRef: persona.avatar,
                size: 56,
                showRing: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      persona.name,
                      style: TextStyle(
                        color: EchoColors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (persona.circle.isNotEmpty) ...[
                          _Tag(text: persona.circle),
                          const SizedBox(width: 6),
                        ],
                        _Tag(text: persona.personalityType, muted: true),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            persona.bio,
            style: TextStyle(
              color: EchoColors.textMuted,
              fontSize: 13,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Stat(label: '等级', value: '${persona.level}'),
              _Stat(label: '粉丝', value: '${persona.followers}'),
              _Stat(label: '关注', value: '${persona.following}'),
            ],
          ),
          if (persona.badges.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final badge in persona.badges) _Tag(text: badge, muted: true),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 「你和他到哪一步了」（B4）。
///
/// 关系推进和记忆摘要本来都发生在后台，这一块是它们唯一看得见的地方——
/// 没有它，用户只会觉得"他说话好像熟了一点"，却说不清为什么。
class _RelationshipCard extends ConsumerWidget {
  const _RelationshipCard({required this.personaId});

  final String personaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relation =
        ref.watch(relationshipProvider(personaId)).value ??
        RelationshipState.stranger(personaId);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '你和他的关系',
                style: TextStyle(
                  color: EchoColors.textFaint,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _Tag(text: relation.tierLabel),
            ],
          ),
          const SizedBox(height: 8),
          if (relation.interactionCount == 0)
            Text(
              '还没打过照面。',
              style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5),
            )
          else ...[
            Text(
              '互动过 ${relation.interactionCount} 次',
              style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5),
            ),
            if (relation.memorySummary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '他记得：${relation.memorySummary}',
                style: TextStyle(
                  color: EchoColors.text,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          // 关注与私信（B5）：聊得下去的人，从这里往前走一步
          Row(
            children: [
              Expanded(
                child: _FollowButton(
                  personaId: personaId,
                  followState: relation.followState,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push(RoutePaths.chat(personaId)),
                  icon: const Icon(Icons.chat_bubble_outline, size: 15),
                  label: const Text('发消息', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: EchoColors.primary,
                    side: BorderSide(color: EchoColors.primaryDim),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 关注按钮（B5）。
///
/// 四个状态各有各的说法：还没关注是「关注」，他先关注了你就是「回关」，
/// 两边都关注了才是「互相关注」——这一格文字本身就在讲你们的关系走到哪了。
class _FollowButton extends ConsumerWidget {
  const _FollowButton({required this.personaId, required this.followState});

  final String personaId;
  final String followState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (label, following) = switch (followState) {
      'following' => ('已关注', true),
      'followed' => ('回关', false),
      'mutual' => ('互相关注', true),
      _ => ('关注', false),
    };

    void toggle() async {
      await ref.read(relationshipRepositoryProvider).toggleFollow(personaId);
    }

    if (following) {
      return OutlinedButton.icon(
        onPressed: toggle,
        icon: const Icon(Icons.check, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: EchoColors.textMuted,
          side: BorderSide(color: EchoColors.divider),
          padding: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }

    return FilledButton.icon(
      onPressed: toggle,
      icon: const Icon(Icons.person_add_alt, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: FilledButton.styleFrom(
        backgroundColor: EchoColors.primary,
        padding: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// 作息：几点、在哪、干什么。
///
/// 这是最能把"一个账号"变成"一个人"的东西——粉丝数谁都能编，
/// 但"晚上七点在阳台弹琴"这种细节编不出来。
class _RoutineCard extends StatelessWidget {
  const _RoutineCard({required this.routines});

  final List<PersonaRoutine> routines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Column(
        children: [
          for (final routine in routines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 46,
                    child: Text(
                      '${routine.hour.toString().padLeft(2, '0')}:00',
                      style: TextStyle(
                        color: EchoColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      routine.place.isEmpty
                          ? routine.activity
                          : '${routine.place} · ${routine.activity}',
                      style: TextStyle(
                        color: EchoColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ResidentPostTile extends StatelessWidget {
  const _ResidentPostTile({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            style: TextStyle(color: EchoColors.text, fontSize: 13.5, height: 1.6),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Text(
                '${post.topicName ?? '日常'} · ${RelativeTime.short(post.createdAt)}',
                style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
              ),
              const Spacer(),
              Icon(Icons.favorite_border, size: 13, color: EchoColors.like),
              const SizedBox(width: 3),
              Text(
                '${post.likeCount}',
                style: TextStyle(color: EchoColors.like, fontSize: 11.5),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.mode_comment_outlined,
                size: 13,
                color: EchoColors.textFaint,
              ),
              const SizedBox(width: 3),
              Text(
                '${post.commentCount}',
                style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
              ),
            ],
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

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? EchoColors.textMuted : EchoColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: EchoColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(
        text,
        style: TextStyle(color: EchoColors.textFaint, fontSize: 12.5),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
        ),
      ),
    );
  }
}
