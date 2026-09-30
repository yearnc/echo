import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_persona.dart';
import '../models/model_config.dart';
import '../models/post.dart';
import '../models/resident_post.dart';
import 'content_moderator.dart';
import 'model_content_generator.dart';
import 'model_gateway.dart';

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
  Future<Map<String, String>> comments({
    required List<AiPersona> personas,
    required Post post,
  });

  /// 给一批「住民 + 时刻」生成他们**自己发的动态**（B3）。
  ///
  /// 与评论分开，是因为口吻完全不同：评论是接别人的话，动态是自己起头。
  /// 拿"评论语气"去发动态，信息流会立刻变得像一堆机器人在自言自语。
  Future<List<ResidentPostDraft>> residentPosts({
    required List<ResidentMoment> moments,
  });
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
  String forPersona(AiPersona persona) {
    final samples = persona.commentSamples;
    if (samples.isEmpty) {
      return fallbackLines[_random.nextInt(fallbackLines.length)];
    }
    return samples[_random.nextInt(samples.length)];
  }

  Map<String, String> commentsFor({required List<AiPersona> personas}) {
    return {for (final persona in personas) persona.id: forPersona(persona)};
  }

  @override
  Future<Map<String, String>> comments({
    required List<AiPersona> personas,
    required Post post,
  }) async => commentsFor(personas: personas);

  /// 分圈层的动态模板。
  ///
  /// 没配模型的用户看到的信息流就是这些句子拼的，所以它们得像人随手发的，
  /// 而不像"欢迎使用本社区"。有 routines 的住民会先走"几点、在哪、干什么"
  /// 那条路，落到具体场景里；模板是它没覆盖到的时候用的。
  static const Map<String, List<String>> circleTemplates = {
    '学习': [
      '图书馆四楼靠窗的位置今天居然空着，运气不错。',
      '背了一上午单词，脑子被掏空又灌满。',
      '这门课的老师今天讲得意外地清楚，记了三页笔记。',
      '自习室里安静得能听见翻页声，挺好。',
    ],
    '吐槽': [
      '早八的教室空调开得像冰窖，穿了外套还冷。',
      '食堂的番茄炒蛋里，番茄和蛋好像在闹别扭。',
      '选课系统又崩了，所有人都在和时间赛跑。',
      '打印店的机器又坏了，我的论文还在它肚子里。',
    ],
    '同校圈': [
      '路过操场的时候晚霞是橘红色的，站着看了一会儿。',
      '快递站队伍排到门口了，双十一还没到呢。',
      '校门口那家便利店换招牌了，有点不习惯。',
      '今天校园里好多人，大概又是什么活动。',
    ],
    '树洞': [
      '有些话说出来就轻了，哪怕只是写在这里。',
      '今天没什么特别的，只是想记一下。',
      '睡不着的时候，总想写点什么。',
    ],
    '深夜': [
      '凌晨一点，宿舍楼还有几盏灯亮着。',
      '起来喝了杯水，窗外特别安静。',
      '这个点的风是凉的，站着吹了一会儿。',
    ],
    '运动': [
      '操场上跑了五圈，风有点大，但很痛快。',
      '篮球场打到天黑，出了一身汗。',
      '今天终于把体测的引体向上练到及格线了。',
    ],
    '摄影': [
      '今天光线特别好，随手拍了几张，改天挑一张发出来。',
      '傍晚的云像被人抹了一笔。',
    ],
    '二手': [
      '清书架，出了几本专业课的书，需要的同学可以看看。',
      '整理出一堆用不上的东西，改天拍照上架。',
    ],
    '失物招领': [
      '今天又收到三张校园卡，失主记得来后勤楼认领。',
      '有人交上来一把雨伞，蓝色格子的，来我这儿看看。',
    ],
    '表白墙': [
      '今天的投稿有点多，慢慢发，别急。',
      '匿名是底线，大家放心投。',
    ],
    '社团招新': [
      '招新摊位布置完了，明天下午见。',
      '今天拉到了二十多个想来的同学，比预想的多。',
    ],
    '兴趣小组': [
      '在宿舍弹了会儿琴，手指又起茧了。',
      '追的剧更新了，今天早点回去。',
      '把攒了半个月的番补完了，眼睛有点酸。',
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
  /// 所以这里不写事情，只写状态——写成"今天去了图书馆"就不像签名了。
  static const Map<String, List<String>> signatureTemplates = {
    '学习': ['在图书馆，勿扰。', '先把这一章看完再说。', '今天也背了单词。'],
    '吐槽': ['今日怨气已售罄。', '别问，问就是很好。'],
    '同校圈': ['风挺大的，但还行。', '最近在学着早睡。'],
    '树洞': ['有些话咽下去也不亏。', '想安静一阵子。'],
    '深夜': ['还没睡的人，都是同一种人。', '凌晨的脑子最诚实。'],
    '运动': ['跑起来就不用想事。', '明天继续。'],
    '摄影': ['等一个好天气。', '按快门那一下最舒服。'],
    '二手': ['清仓中，带价来。', '书架空了一半，挺好。'],
    '失物招领': ['捡到的东西都在后勤楼。', '认领请留言。'],
    '表白墙': ['匿名是底线。', '今天的投稿有点多。'],
    '社团招新': ['招新中，来摊位看看。', '今年想多招点人。'],
    '兴趣小组': ['追剧中，勿扰。', '手指又起茧了。'],
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

    final templates = circleTemplates[persona.circle] ?? genericLines;
    return templates[_random.nextInt(templates.length)];
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
  }) async {
    if (personas.isEmpty) return const {};

    // 整个走法都包在 try 里，包括"去查有没有模型"这一步：密钥读不出来、
    // 配置表读不了，都不该让说话这件事失败。
    try {
      final config = await activeConfig();
      if (config == null) return sample.commentsFor(personas: personas);

      final generated = await model.comments(
        config: config,
        personas: personas,
        post: post,
      );
      if (generated.isEmpty) return sample.commentsFor(personas: personas);

      return _merge(generated, personas);
    } catch (error) {
      // 超时、限额、密钥失效——都不该让社区停下来。
      // 留个痕：失败连着发生的时候，从界面上是看不出来的（住民照样在说话）。
      debugPrint('[内容生成] 模型失败，退回样本：$error');
      return sample.commentsFor(personas: personas);
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
    List<AiPersona> personas,
  ) {
    final result = sample.commentsFor(personas: personas);
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
