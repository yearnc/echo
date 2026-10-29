import 'package:flutter_test/flutter_test.dart';

import 'package:echo/domain/models/post.dart';
import 'package:echo/domain/models/post_understanding.dart';
import 'package:echo/domain/models/sticker.dart';
import 'package:echo/domain/services/post_voice_generator.dart';

void main() {
  group('临时网民的解析与校验', () {
    test('合法的都留下，名字、状态、动作、评论都在', () {
      final drafts = ModelPostVoiceGenerator.parseDrafts(
        '''
        [
          {"name":"大肥鱼","status":"刚下班","action":"comment","comment":"这颗钻石也太大了"},
          {"name":"楼下吉他手","status":"在等车","action":"like","comment":""}
        ]
        ''',
        max: 5,
        allowLurk: true,
      );

      expect(drafts, hasLength(2));
      expect(drafts[0].name, '大肥鱼');
      expect(drafts[0].action, VoiceAction.likeComment);
      expect(drafts[0].comment, '这颗钻石也太大了');
      expect(drafts[1].action, VoiceAction.like);
      expect(drafts[1].comment, isEmpty);
    });

    test('名字只是占位：太短或重复都不会丢人', () {
      final drafts = ModelPostVoiceGenerator.parseDrafts(
        '''
        [
          {"name":"鱼","action":"like"},
          {"name":"一个长到不行的网名","action":"like"},
          {"name":"大肥鱼","action":"like"},
          {"name":"大肥鱼","action":"comment","comment":"又来一条"}
        ]
        ''',
        max: 5,
        allowLurk: true,
      );

      // 真正的网名由 AudienceService 统一分配，这里只看条目有没有被留下。
      expect(drafts, hasLength(4));
      expect(drafts[0].name, '网友1');
      expect(drafts[2].name, '大肥鱼');
      expect(drafts[3].name, '大肥鱼');
    });

    test('不允许只读时，view 直接丢掉', () {
      final drafts = ModelPostVoiceGenerator.parseDrafts(
        '''
        [
          {"name":"只看不说话","action":"view"},
          {"name":"点个赞","action":"like"}
        ]
        ''',
        max: 5,
        allowLurk: false,
      );

      expect(drafts.map((d) => d.name), ['点个赞']);
    });

    test('评论为空或超长时降级成只点赞，不拿别的句子顶', () {
      final drafts = ModelPostVoiceGenerator.parseDrafts(
        '''
        [
          {"name":"空评论","action":"comment","comment":""},
          {"name":"太长","action":"like_comment","comment":"${List.filled(61, '很').join()}"}
        ]
        ''',
        max: 5,
        allowLurk: true,
      );

      expect(drafts, hasLength(2));
      expect(drafts[0].action, VoiceAction.like);
      expect(drafts[0].comment, isEmpty);
      expect(drafts[1].action, VoiceAction.like);
      expect(drafts[1].comment, isEmpty);
    });

    test('解析失败返回空，不抛异常', () {
      expect(
        ModelPostVoiceGenerator.parseDrafts(
          '不是 JSON',
          max: 5,
          allowLurk: true,
        ),
        isEmpty,
      );
    });
  });

  group('提示词', () {
    test('要求接住帖子的具体东西，并给了动作形状', () {
      final prompt = ModelPostVoiceGenerator.systemPrompt(allowLurk: true);
      expect(prompt, contains('必须接住帖子里的具体东西'));
      expect(prompt, contains('view'));
      expect(prompt, contains('like_comment'));
      expect(prompt, contains('JSON'));
    });

    test('关闭只读时明确要求至少点赞或评论', () {
      final prompt = ModelPostVoiceGenerator.systemPrompt(allowLurk: false);
      expect(prompt, contains('不能只看不说话'));
    });

    test('同一批人角度要错开', () {
      final prompt = ModelPostVoiceGenerator.systemPrompt(allowLurk: true);
      expect(prompt, contains('角度要错开'));
    });

    test('逐帖稳定的内容排在“现在”之前，每次会变的压在最后', () {
      final prompt = ModelPostVoiceGenerator.userPrompt(
        post: Post(
          id: 'p1',
          content: '今天加班到十点',
          createdAt: DateTime(2026, 10, 28, 12),
        ),
        count: 1,
        at: DateTime(2026, 10, 28, 21),
        avoidNames: const {'大肥鱼'},
        recentComments: const ['我也刚下班'],
        knowledge: '【网民的说话方式（参考，别照抄）】',
        stickers: const [
          StickerItem(
            id: 's1',
            name: '安慰·摸摸头',
            category: '安慰',
            path: 'asset:s1.png',
            tags: ['安慰'],
          ),
        ],
        understanding: PostUnderstanding(
          postId: 'p1',
          tone: '吐槽',
          domain: '生活',
          point: '加班到十点',
          angles: const ['吐槽加班'],
          confidence: 0.8,
          updatedAt: DateTime(2026, 10, 28),
        ),
      );

      final now = prompt.indexOf('现在：');
      expect(now, greaterThan(prompt.indexOf('这条帖子已经看懂了')));
      expect(now, greaterThan(prompt.indexOf('网民的说话方式')));
      expect(now, greaterThan(prompt.indexOf('可用表情包')));
      // 相对时长跟着“现在”走，不能留在发帖时间那一行破坏前缀
      expect(prompt.indexOf('距发帖约'), greaterThan(now));
      // 每批/每次都会变的两段只能出现在最后
      expect(prompt.indexOf('已经有人说'), greaterThan(now));
      expect(prompt.indexOf('已经出现过的人'), greaterThan(now));
    });

    test('知识库内容放进 user 段，不污染 system', () {
      final prompt = ModelPostVoiceGenerator.userPrompt(
        post: Post(
          id: 'p1',
          content: '今天加班到十点',
          createdAt: DateTime(2026, 10, 28, 12),
        ),
        count: 3,
        knowledge: '【网民的说话方式（参考，别照抄）】\n- 共鸣：抓细节',
      );
      expect(prompt, contains('网民的说话方式'));
      expect(
        ModelPostVoiceGenerator.systemPrompt(allowLurk: true),
        isNot(contains('网民的说话方式')),
      );
    });
  });
}
