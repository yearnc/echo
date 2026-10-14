/// 住民的声音（B8 真实语音）。
///
/// 音色由本机的离线 TTS 模型合成，模型是 AISHELL-3 多说话人 VITS：
/// 一套模型里带 174 个说话人，用 `sid`（说话人编号）挑嗓子。
///
/// 这里定的是「谁的声音是谁的」——**一个住民固定一个 sid**，
/// 不随机、不轮换。同一个人今天和下周听起来是同一个人，
/// 这是"社区里住着人"最基本的可信度。
library;

/// 住民 → 音色的固定对照表。
class ResidentVoice {
  const ResidentVoice._();

  /// 每位住民的专属说话人编号。
  ///
  /// 编号来自 `assets/personas/personas.json` 的 `voiceModel` 语气标签：
  /// 先按性别分池（男声只挑男声、女声只挑女声），再在池子里顺序取一个，
  /// 于是 32 个人各有各的嗓子，同语气标签的人也不会撞声。
  ///
  /// 表是**写死的**，不是运行时算的：住民 id 与 sid 的对应关系一旦变了，
  /// 老用户的评论区会集体换声，那比"某个人的声音不好听"糟糕得多。
  static const Map<String, int> _sidByPersona = {
    'persona_001': 0, // 听你说完
    'persona_002': 10, // 老陈的键盘
    'persona_003': 15, // 半夜不睡
    'persona_004': 1, // 楼道小剧场
    'persona_005': 21, // 沉默的赞
    'persona_006': 23, // 好好先生
    'persona_007': 25, // 追光的K
    'persona_008': 32, // 跑两步
    'persona_009': 2, // 凌晨的猫
    'persona_010': 3, // 一杯半拿铁
    'persona_011': 40, // 加班的小王
    'persona_012': 46, // 潜水员404
    'persona_013': 4, // 公司对面的猫
    'persona_014': 5, // 点赞狂魔+1
    'persona_015': 48, // 待处理清单
    'persona_016': 52, // 火锅一号
    'persona_017': 6, // 记不住书名
    'persona_018': 7, // 拼单省省
    'persona_019': 8, // i人观察员
    'persona_020': 58, // 起床失败
    'persona_021': 60, // 楼下吉他手
    'persona_022': 65, // 银幕背面
    'persona_023': 9, // 菜市场观察员
    'persona_024': 11, // 阳台上的猫
    'persona_025': 69, // 失物招领处
    'persona_026': 72, // 遛狗的两公里
    'persona_027': 12, // 墙墙本墙
    'persona_028': 13, // 活动广播站
    'persona_029': 14, // 深夜电台
    'persona_030': 74, // 一个人走走
    'persona_031': 75, // 耳机线打成结
    'persona_032': 76, // 掐点队队长
  };

  /// 女声可以用到的编号（模型里一百多个，这里取前 60 个）。
  ///
  /// 表外的住民（比如以后加了新住民、或者用户自己造的人格）落到这里：
  /// 按 id 稳定取一个，取到哪算哪，但同一个人永远是同一个。
  static const List<int> _femalePool = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 16, 17, 18, 19, 20, 22,
    24, 26, 27, 28, 29, 30, 31, 33, 34, 35, 36, 37, 38, 39, 41, 42, 43, 44,
    45, 47, 49, 50, 51, 53, 54, 55, 56, 57, 59, 61, 62, 63, 64, 66, 67, 68,
    70, 71, 73, 77,
  ];

  /// 男声可以用到的编号（模型里男声只有 36 个，这就是全部）。
  static const List<int> _malePool = [
    10, 15, 21, 23, 25, 32, 40, 46, 48, 52, 58, 60, 65, 69, 72, 74, 75, 76,
    83, 95, 98, 100, 102, 107, 110, 119, 124, 136, 140, 143, 151, 153, 156,
    163, 167, 171,
  ];

  /// 查一个住民的音色编号。
  ///
  /// [voiceModel] 是住民出厂设定里的语气标签（`voice_male_calm` 这类），
  /// 只在表里查不到时用来判断"这是男声还是女声"。
  static int sidFor(String personaId, {String voiceModel = ''}) {
    final fixed = _sidByPersona[personaId];
    if (fixed != null) return fixed;

    // 判性别时先看 female：`voice_soft_female` 里也含 "male" 四个字母，
    // 反过来的顺序会把一半女声判成男声。
    final pool = voiceModel.contains('female') || !voiceModel.contains('male')
        ? _femalePool
        : _malePool;

    // 用 id 的稳定散列取一位——不加随机因子，重启后还是同一个声音。
    var hash = 0;
    for (final code in personaId.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return pool[hash % pool.length];
  }

  /// 住民说话的语速。
  ///
  /// 语气标签里带 "lazy"、"quiet" 的人说得慢一点，"loud"、"bright" 的快一点；
  /// 幅度压得很小（±6%），听感上只是"这个人说话松一些"，不至于听起来像变速播放。
  static double speedFor(String voiceModel) {
    if (voiceModel.contains('lazy') || voiceModel.contains('quiet')) return 0.94;
    if (voiceModel.contains('loud') || voiceModel.contains('bright')) return 1.06;
    return 1.0;
  }
}
