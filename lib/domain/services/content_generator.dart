import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_persona.dart';
import '../models/model_config.dart';
import '../models/post.dart';
import '../models/resident_post.dart';
import 'community_calendar.dart';
import 'content_moderator.dart';
import 'model_content_generator.dart';
import 'model_gateway.dart';
import 'relationship_rules.dart';

/// 住民说的话，全都从这里出（阶段 B 计划书决策 1）。
///
/// 分成接口，是为了让"没有模型"不是一条特殊路径，而是另一种正常走法：
/// 没配模型的用户照样有一个完整的社区，只是住民说的话来自预置台词。
/// 有了它，B3 的住民动态、B5 的私信都只要多一个方法，不用再各自接一次模型。
abstract interface class ContentGenerator {
  /// 给一批住民生成对某条帖子的评论。返回 住民 id → 评论内容。
  ///
  /// **一个住民一条**。同一住民在同一条帖子下留两条语气不同的评论会立刻暴露
  /// AI 身份——这条规矩从阶段 A 就在，B7 的楼中楼之前一直有效，
  /// 所以这里按批生成，也守着它。
  /// [relations] 是这批人和你的关系（B4）：说话的分寸、记不记得你以前发过
  /// 什么，都从这里来。没打过交道的人不在里面，那就是陌生。
  Future<Map<String, String>> comments({
    required List<AiPersona> personas,
    required Post post,
    Map<String, RelationshipState> relations = const {},
  });

  /// 给一批「住民 + 时刻」生成他们**自己发的动态**（B3）。
  ///
  /// 与评论分开，是因为口吻完全不同：评论是接别人的话，动态是自己起头。
  /// 拿"评论语气"去发动态，信息流会立刻变得像一堆机器人在自言自语。
  Future<List<ResidentPostDraft>> residentPosts({
    required List<ResidentMoment> moments,
  });

  /// 私信里各自该说下一句什么（B5）。
  ///
  /// 又是另一种口吻：评论是当着一屋子人说的，私信是关起门来跟一个人说。
  /// 所以这三件事各自一个方法，谁也不借谁的词。
  Future<Map<String, String>> directMessages({
    required List<DirectThread> threads,
    Map<String, RelationshipState> relations = const {},
  });

  /// 追问（B7）：他刚才说的那句话被你接了，现在他接着说什么。
  ///
  /// 又是另一种口吻：不是评论（当着一屋子人）、不是动态（自己起头）、
  /// 也不是私信（关起门来）。它是**楼中楼里的一句**——上文只有短短两条，
  /// 而且对方就站在那儿等着。
  Future<Map<String, String>> replies({
    required List<ReplyThread> threads,
    Map<String, RelationshipState> relations = const {},
  });
}

/// 一段追问的上下文：他原本说了什么，以及你接的那一句。
class ReplyThread {
  const ReplyThread({
    required this.persona,
    required this.mine,
    required this.yours,
  });

  final AiPersona persona;

  /// 他自己原来那条评论。
  final String mine;

  /// 你回他的那句。
  final String yours;
}

/// 一段私信的上下文：这个人，加上你们最近说的那几句。
class DirectThread {
  const DirectThread({required this.persona, this.recent = const []});

  final AiPersona persona;

  /// 最近的往来，按时间正序。**空表示他先开口**——那是另一套口吻。
  final List<DirectTurn> recent;

  bool get isOpening => recent.isEmpty;
}

/// 私信里的那一句是谁说的。
class DirectTurn {
  const DirectTurn({required this.fromMe, required this.text});

  /// true = 我（住民）说的，false = 他（用户）说的。
  final bool fromMe;
  final String text;
}

/// 离线样本：从住民自己的预置台词里挑一条。
///
/// 它同时是两件事：没配模型时的内容来源，以及模型失败时的兜底。
/// 所以除了接口要求的异步方法，这里另给一套**同步**方法——
/// 兜底这件事不该还有自己的失败可能（它要是也会失败，那就不叫兜底了）。
class SampleContentGenerator implements ContentGenerator {
  SampleContentGenerator({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// 住民没写台词时用的公版句子。
  ///
  /// 编得不走心，但总比评论区里冒出一条空白好——那是"这个 APP 坏了"的样子。
  /// 眼下 32 个住民人人有台词，走不到这儿；等 B 阶段放开用户自定义住民，
  /// 这里就是第一条路。
  static const List<String> fallbackLines = [
    '看到这条了。',
    '嗯，这个我懂。',
    '路过，点个赞。',
  ];

  /// 给一个住民挑一条台词。**永远有话说**——返回空字符串会在评论区
  /// 渲染成一条空评论，而缺一条评论比出现一条空白要好得多。
  ///
  /// [relation] 是这个人跟你熟到什么程度（B4）。样本层没法像模型那样自然地
  /// "提起你上次那张天空照"，能做的是另一件事：**熟人话多一点**。同一个人
  /// 写了好几句台词时，关系近的从长的那些里挑。
  String forPersona(AiPersona persona, {RelationshipState? relation}) {
    final samples = persona.commentSamples;
    if (samples.isEmpty) {
      return fallbackLines[_random.nextInt(fallbackLines.length)];
    }
    if ((relation?.level ?? 0) >= 2 && samples.length > 1) {
      final byLength = [...samples]..sort((a, b) => b.length.compareTo(a.length));
      final longer = byLength.take((byLength.length / 2).ceil()).toList();
      return longer[_random.nextInt(longer.length)];
    }
    return samples[_random.nextInt(samples.length)];
  }

  Map<String, String> commentsFor({
    required List<AiPersona> personas,
    Map<String, RelationshipState> relations = const {},
  }) {
    return {
      for (final persona in personas)
        persona.id: forPersona(persona, relation: relations[persona.id]),
    };
  }

  @override
  Future<Map<String, String>> comments({
    required List<AiPersona> personas,
    required Post post,
    Map<String, RelationshipState> relations = const {},
  }) async => commentsFor(personas: personas, relations: relations);

  /// 分圈层的动态模板。
  ///
  /// 没配模型的用户看到的信息流就是这些句子拼的，所以它们得像人随手发的，
  /// 而不像"欢迎使用本社区"。有 routines 的住民会先走"几点、在哪、干什么"
  /// 那条路，落到具体场景里；模板是它没覆盖到的时候用的。
  static const Map<String, List<String>> circleTemplates = {
    '日常': [
      '今天出门忘了带伞，回来的时候雨停了。',
      '楼下那家店换了招牌，看着有点陌生。',
      '收拾了一下午屋子，扔了三袋没用的东西，心情挺好。',
      '下午的阳光刚好照到桌上，坐着发了会儿呆。',
      '一天没出门，晚上才发现冰箱空了。',
    ],
    '吐槽': [
      '排了二十分钟队，前面那位结账结了十分钟。',
      '说好六点到的，现在八点半了，还没影。',
      '快递显示已签收，可我没收到，谁替我签的。',
      '楼下装修，从早上八点开始，一刻没停。',
    ],
    '职场': [
      '今天开了三个会，一件事都没推进。',
      '需求改到第五版，跟第一版几乎一样。',
      '下班前十分钟收到一句「明早要」。',
      '周报写到一半，发现这周好像什么都没干。',
    ],
    '深夜': [
      '凌晨一点，楼下还有人在遛狗。',
      '起来喝了杯水，屋里安静得能听见冰箱的声音。',
      '这个点的风是凉的，站在阳台上吹了一会儿。',
    ],
    '树洞': [
      '有些话说出来就轻了，哪怕只是写在这里。',
      '今天没什么特别的，只是想记一下。',
      '想找个地方说一句，说完就走。',
    ],
    '运动': [
      '跑了五公里，风有点大，但很痛快。',
      '骑车绕了一大圈，回来腿都不是自己的了。',
      '今天终于把俯卧撑练到第二十组。',
    ],
    '摄影': [
      '今天光线特别好，随手拍了几张。',
      '傍晚的云像被谁抹了一笔。',
    ],
    '美食': [
      '今天这锅汤炖了两个小时，值。',
      '路过菜场看到新鲜的，就买多了。',
      '早上第一杯咖啡，喝下去才算醒。',
    ],
    '读书': [
      '读到一半被打断，回来忘了刚才看到哪。',
      '书里有一句很好，抄下来贴在了冰箱上。',
    ],
    '音乐': [
      '循环了一整天同一首歌，还是不腻。',
      '在阳台弹了会儿琴，手指又起茧了。',
      '戴上耳机，世界立刻安静了。',
    ],
    '宠物': [
      '猫今天把我的笔从桌上推下去三次。',
      '遛狗的时候，它认识的人比我还多。',
    ],
    '出行': [
      '周末一个人出门，走到哪儿算哪儿。',
      '在河边坐了半小时，什么都没想。',
    ],
  };

  /// 连圈层模板都没覆盖到的时候用（每个住民都应该有 circle，
  /// 这一档是防"以后加了新圈层但忘了配模板"）。
  static const List<String> genericLines = [
    '今天也是普通的一天。',
    '随手记一笔。',
    '路上看到点小事，记一下。',
  ];

  /// 换签名的样本，也按圈层分（B3.5）。
  ///
  /// 跟动态模板的分工：动态是"我今天干了什么"，签名是"我现在是个什么状态"。
  /// 所以这里不写事情，只写状态——写成"今天去了超市"就不像签名了。
  static const Map<String, List<String>> signatureTemplates = {
    '日常': ['今天也是普通的一天。', '慢慢来，不急。'],
    '吐槽': ['今日怨气已售罄。', '别问，问就是很好。'],
    '职场': ['下班勿扰。', '周报还没写完。'],
    '深夜': ['还没睡的人，都是同一种人。', '凌晨的脑子最诚实。'],
    '树洞': ['有些话咽下去也不亏。', '想安静一阵子。'],
    '运动': ['跑起来就不用想事。', '明天继续。'],
    '摄影': ['等一个好天气。', '按快门那一下最舒服。'],
    '美食': ['今天的饭很好吃。', '先吃饭，别的晚点说。'],
    '读书': ['看到一半，别吵。', '书比人好相处。'],
    '音乐': ['耳机里在放歌。', '单曲循环第八遍。'],
    '宠物': ['猫在家等我。', '狗子今天很开心。'],
    '出行': ['人已经在路上了。', '去哪儿都行，先出门。'],
  };

  static const List<String> genericSignatures = [
    '最近还行，就是有点困。',
    '没什么大事，记一下。',
    '换个签名，换换心情。',
  ];

  /// 这个住民会换成一句什么签名。
  ///
  /// 只负责给下一句——"他现在的签名是什么"由调用方落库，
  /// 下一轮读的时候从库里拿。
  String signatureFor(AiPersona persona) {
    final templates =
        signatureTemplates[persona.circle] ?? genericSignatures;
    return templates[_random.nextInt(templates.length)];
  }

  /// 住民这个点大概会发什么。
  ///
  /// 公开出来是为了可测：**"他们有没有话说"这件事不该只能靠在信息流里刷**。
  String residentLine(AiPersona persona, DateTime at) {
    final routine = persona.routineAt(at.hour);
    if (routine != null && routine.activity.isNotEmpty) {
      return routine.place.isEmpty
          ? '${routine.activity}。'
          : '在${routine.place}，${routine.activity}。';
    }

    // 大家身边正发生的事是最省事的共同话题：降温那天，半个社区都在喊冷。
    // 只给四成机会——一屏全是"今天真冷"，那也不像活人。
    final event = CommunityCalendar.strongestAt(at);
    if (event != null &&
        event.samples.isNotEmpty &&
        _random.nextDouble() < 0.4) {
      return event.samples[_random.nextInt(event.samples.length)];
    }

    final templates = circleTemplates[persona.circle] ?? genericLines;
    return templates[_random.nextInt(templates.length)];
  }

  /// 私信的开场白（B5）。
  ///
  /// 刻意不复用评论台词：评论是"路过看一眼你发的"，私信是"专门来找你说句话"，
  /// 语气差得远。而住民自己的 commentSamples 全是前者。
  static const List<String> directOpeners = [
    '在吗？上次你那事儿后来怎么样了。',
    '刚下班回来，忽然想起你说的那句。',
    '看你又发了条动态，最近是不是挺忙的。',
    '今天路过你说的那家店，居然真的在排队。',
    '我是上次在你帖子底下留言的那个，聊聊？',
    '有件事想问问你，方便的时候回我一下。',
  ];

  /// 接着往下聊时的样本。真正的上下文靠模型，这里只保证"有话说"。
  static const List<String> directReplies = [
    '嗯，我大概懂你的意思。',
    '这样啊……那你自己是怎么想的？',
    '哈哈，那就好。',
    '我记下了，回头再聊这个。',
    '有道理，我倒是没这么想过。',
  ];

  /// 私信样本：先开口的和接话的，是两套词。
  @override
  Future<Map<String, String>> directMessages({
    required List<DirectThread> threads,
    Map<String, RelationshipState> relations = const {},
  }) async {
    return {
      for (final thread in threads)
        thread.persona.id: _directLine(thread.isOpening),
    };
  }

  String _directLine(bool isOpening) {
    final pool = isOpening ? directOpeners : directReplies;
    return pool[_random.nextInt(pool.length)];
  }

  /// 楼中楼里的接话（B7）。上文越具体越难照抄，所以这里只求"像在接着聊"。
  static const List<String> followUps = [
    '我就随口一说，你倒是认真了。',
    '嗯，你这么说也对。',
    '那倒没有，就是有点感慨。',
    '哈哈，行，听你的。',
    '确实，不过我还是觉得有点难。',
    '下次碰到再跟你说说。',
  ];

  @override
  Future<Map<String, String>> replies({
    required List<ReplyThread> threads,
    Map<String, RelationshipState> relations = const {},
  }) async {
    return {
      for (final thread in threads)
        thread.persona.id: followUps[_random.nextInt(followUps.length)],
    };
  }

  /// 离线样本照样给一句签名（B3.5）。
  ///
  /// 给了不等于换——"今天想不想换签名"由 [[ResidentSignature.pick]] 按冷却与
  /// 概率定。样本层负责"写成什么"，规则层负责"轮到谁"，两边不掺和。
  @override
  Future<List<ResidentPostDraft>> residentPosts({
    required List<ResidentMoment> moments,
  }) async => [
    for (final moment in moments)
      ResidentPostDraft(
        personaId: moment.persona.id,
        content: residentLine(moment.persona, moment.at),
        topicName: moment.persona.circle.isEmpty ? null : moment.persona.circle,
        newBio: signatureFor(moment.persona),
      ),
  ];
}

/// 内容来源：优先用用户自己的模型，不行就退回样本。
///
/// 降级发生在这一层，而不是调用方。调度器要的只是"一句话"，
/// 不该关心这句话是谁写的、中间失败过几次。
class ContentSource implements ContentGenerator {
  ContentSource({
    required this.model,
    required this.sample,
    required this.activeConfig,
  });

  final ModelContentGenerator model;
  final SampleContentGenerator sample;

  /// 当前能用的模型配置；没有就是 null（那就只有样本这一条路）。
  final Future<ModelConfig?> Function() activeConfig;

  @override
  Future<Map<String, String>> comments({
    required List<AiPersona> personas,
    required Post post,
    Map<String, RelationshipState> relations = const {},
  }) async {
    if (personas.isEmpty) return const {};

    // 整个走法都包在 try 里，包括"去查有没有模型"这一步：密钥读不出来、
    // 配置表读不了，都不该让说话这件事失败。
    try {
      final config = await activeConfig();
      if (config == null) {
        return sample.commentsFor(personas: personas, relations: relations);
      }

      final generated = await model.comments(
        config: config,
        personas: personas,
        post: post,
        relations: relations,
      );
      if (generated.isEmpty) {
        return sample.commentsFor(personas: personas, relations: relations);
      }

      return _merge(generated, personas, relations: relations);
    } catch (error) {
      // 超时、限额、密钥失效——都不该让社区停下来。
      // 留个痕：失败连着发生的时候，从界面上是看不出来的（住民照样在说话）。
      debugPrint('[内容生成] 模型失败，退回样本：$error');
      return sample.commentsFor(personas: personas, relations: relations);
    }
  }

  @override
  Future<List<ResidentPostDraft>> residentPosts({
    required List<ResidentMoment> moments,
  }) async {
    if (moments.isEmpty) return const [];

    try {
      final config = await activeConfig();
      if (config == null) return await sample.residentPosts(moments: moments);

      final generated = await model.residentPosts(
        config: config,
        moments: moments,
      );
      if (generated.isEmpty) {
        return await sample.residentPosts(moments: moments);
      }

      return _fillMissingDrafts(generated, moments);
    } catch (error) {
      debugPrint('[内容生成] 模型失败，退回样本：$error');
      return sample.residentPosts(moments: moments);
    }
  }

  @override
  Future<Map<String, String>> directMessages({
    required List<DirectThread> threads,
    Map<String, RelationshipState> relations = const {},
  }) async {
    if (threads.isEmpty) return const {};

    try {
      final config = await activeConfig();
      if (config == null) {
        return await sample.directMessages(
          threads: threads,
          relations: relations,
        );
      }

      final generated = await model.directMessages(
        config: config,
        threads: threads,
        relations: relations,
      );
      if (generated.isEmpty) {
        return await sample.directMessages(
          threads: threads,
          relations: relations,
        );
      }

      return await _mergeDirect(generated, threads, relations: relations);
    } catch (error) {
      debugPrint('[内容生成] 模型失败，退回样本：$error');
      return await sample.directMessages(threads: threads, relations: relations);
    }
  }

  @override
  Future<Map<String, String>> replies({
    required List<ReplyThread> threads,
    Map<String, RelationshipState> relations = const {},
  }) async {
    if (threads.isEmpty) return const {};

    try {
      final config = await activeConfig();
      if (config == null) {
        return await sample.replies(threads: threads, relations: relations);
      }

      final generated = await model.replies(
        config: config,
        threads: threads,
        relations: relations,
      );
      if (generated.isEmpty) {
        return await sample.replies(threads: threads, relations: relations);
      }

      return await _mergeReplies(generated, threads, relations: relations);
    } catch (error) {
      debugPrint('[内容生成] 模型失败，退回样本：$error');
      return await sample.replies(threads: threads, relations: relations);
    }
  }

  /// 模型写的追问：没过本地词表的丢掉，换成样本台词。
  Future<Map<String, String>> _mergeReplies(
    Map<String, String> generated,
    List<ReplyThread> threads, {
    Map<String, RelationshipState> relations = const {},
  }) async {
    final result = await sample.replies(threads: threads, relations: relations);
    for (final entry in generated.entries) {
      if (ContentModerator.checkLocally(entry.value) != null) {
        debugPrint('[内容生成] 这条追问没过本地词表，换成预置台词：${entry.key}');
        continue;
      }
      result[entry.key] = entry.value;
    }
    return result;
  }

  /// 模型写的私信：没过本地词表的丢掉，换成样本台词。
  Future<Map<String, String>> _mergeDirect(
    Map<String, String> generated,
    List<DirectThread> threads, {
    Map<String, RelationshipState> relations = const {},
  }) async {
    final result = await sample.directMessages(
      threads: threads,
      relations: relations,
    );
    for (final entry in generated.entries) {
      if (ContentModerator.checkLocally(entry.value) != null) {
        debugPrint('[内容生成] 这条私信没过本地词表，换成预置台词：${entry.key}');
        continue;
      }
      result[entry.key] = entry.value;
    }
    return result;
  }

  /// 模型写的动态：没过本地词表的丢掉，没写到的用样本补上。
  ///
  /// 动态比评论更要紧——它是信息流里的主角，"这条没人发"会直接变成
  /// 信息流上一个空缺的时刻。所以这里保证每个人都有着落。
  List<ResidentPostDraft> _fillMissingDrafts(
    List<ResidentPostDraft> generated,
    List<ResidentMoment> moments,
  ) {
    final byPersona = {for (final draft in generated) draft.personaId: draft};

    final result = <ResidentPostDraft>[];
    for (final moment in moments) {
      final draft = byPersona[moment.persona.id];
      if (draft != null &&
          ContentModerator.checkLocally(draft.content) == null) {
        result.add(draft);
        continue;
      }
      result.add(_sampleDraft(moment));
    }
    return result;
  }

  ResidentPostDraft _sampleDraft(ResidentMoment moment) => ResidentPostDraft(
    personaId: moment.persona.id,
    content: sample.residentLine(moment.persona, moment.at),
    topicName: moment.persona.circle.isEmpty ? null : moment.persona.circle,
    newBio: sample.signatureFor(moment.persona),
  );

  /// 模型写的那几条盖在样本上，并且在盖之前过一遍本地词表。
  ///
  /// 住民里有"毒舌调侃型"，让它自由发挥是有风险的；命中的那条丢给预置台词。
  /// 这里**不调模型审核**——那等于每条评论花两次钱，而且审核服务本身也可能失败。
  Map<String, String> _merge(
    Map<String, String> generated,
    List<AiPersona> personas, {
    Map<String, RelationshipState> relations = const {},
  }) {
    final result = sample.commentsFor(personas: personas, relations: relations);
    for (final entry in generated.entries) {
      if (ContentModerator.checkLocally(entry.value) != null) {
        debugPrint('[内容生成] 这条没通过本地词表，换成预置台词：${entry.key}');
        continue;
      }
      result[entry.key] = entry.value;
    }
    return result;
  }
}

final sampleContentGeneratorProvider = Provider<SampleContentGenerator>(
  (ref) => SampleContentGenerator(),
);

final modelContentGeneratorProvider = Provider<ModelContentGenerator>(
  (ref) => ModelContentGenerator(ref.watch(modelGatewayProvider)),
);

final contentSourceProvider = Provider<ContentGenerator>((ref) {
  final gateway = ref.watch(modelGatewayProvider);
  return ContentSource(
    model: ref.watch(modelContentGeneratorProvider),
    sample: ref.watch(sampleContentGeneratorProvider),
    activeConfig: gateway.activeConfig,
  );
});
