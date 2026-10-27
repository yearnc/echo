/// 住民的声音（B8 / v3.8）。
///
/// 音色由本机的离线 TTS 模型合成：
/// - 默认是 vits-zh-ll，一套模型 5 个中文说话人（0—4）；
/// - 上传了参考音频 + 逐字稿的住民走 ZipVoice 克隆，不落在这些 sid 上。
///
/// 这里定的是「谁的声音是谁的」——**一个住民固定一个 sid**，
/// 不随机、不轮换。同一个人今天和下周听起来是同一个人，
/// 这是"社区里住着人"最基本的可信度。
library;

/// 住民 → 音色的固定对照表。
class ResidentVoice {
  const ResidentVoice._();

  /// vits-zh-ll 里的说话人数量（模型 JSON 里的 `n_speakers`）。
  static const int localSpeakerCount = 5;

  /// 五选一时给用户看的名字。模型里的原始 speaker 名是角色名，
  /// 对用户没有意义；这里只如实标男女，不编“清亮/温柔”这类没验证过的音色。
  static const List<String> speakerLabels = [
    '声线 1 · 女',
    '声线 2 · 女',
    '声线 3 · 女',
    '声线 4 · 女',
    '声线 5 · 男',
  ];

  static String labelForSid(int sid) {
    if (sid < 0 || sid >= speakerLabels.length) return '未选择';
    return speakerLabels[sid];
  }

  /// 女声可用的编号：前四位是女声，最后一位是“霸总”男声。
  ///
  /// 这是模型自带的分组，不是我们按名字猜的——旧 AISHELL-3 的 174 人表
  /// 已经不适用了，`local:42` 这类老引用会被下面的 `_localSid` 挡掉，
  /// 重新落到稳定散列上，不会把引擎喂一个越界的 sid。
  static const List<int> _femalePool = [0, 1, 2, 3];
  static const List<int> _malePool = [4];

  /// 查一个住民的音色编号。
  ///
  /// [voiceModel] 可能是 `local:<sid>`（已经定下来的音色），也可能只是
  /// 旧住民资产里的语气标签（用来判断男女）。
  static int sidFor(String personaId, {String voiceModel = ''}) {
    final fixed = _localSid(voiceModel);
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

  /// 公开给编辑页/音色解析用：`local:3` 且编号在当前模型范围内才算数。
  static int? localSidOf(String voiceModel) => _localSid(voiceModel);

  /// `local:3` 且编号在当前模型范围内才算数。
  static int? _localSid(String voiceModel) {
    if (!voiceModel.startsWith('local:')) return null;
    final sid = int.tryParse(voiceModel.substring('local:'.length));
    if (sid == null || sid < 0 || sid >= localSpeakerCount) return null;
    return sid;
  }

  /// 这个住民用的是不是女声。云端 TTS 服务商的音色名分男女，
  /// 靠它挑一个不别扭的。
  static bool isFemale(String personaId, {String voiceModel = ''}) {
    final sid = sidFor(personaId, voiceModel: voiceModel);
    return _femalePool.contains(sid);
  }

  /// 云端 TTS 的音色名。
  ///
  /// 各家音色表不一样，这里只认两家确认过的：
  /// 硅基流动（CosyVoice）和 OpenAI。自定义端点按 OpenAI 的名字试，
  /// 不对就让用户自己换服务商——总比随机猜一个不存在的音色强。
  static String cloudVoiceFor(
    String personaId, {
    String voiceModel = '',
    required String baseUrl,
  }) {
    final female = isFemale(personaId, voiceModel: voiceModel);
    final even = personaId.codeUnits.fold<int>(0, (a, b) => a + b).isEven;

    if (baseUrl.contains('siliconflow')) {
      if (female) return even ? 'anna' : 'bella';
      return even ? 'alex' : 'benjamin';
    }
    if (baseUrl.contains('openai')) {
      if (female) return even ? 'nova' : 'shimmer';
      return even ? 'onyx' : 'echo';
    }
    return female ? 'nova' : 'onyx';
  }

  /// 用一段文字描述挑一个本机音色。
  ///
  /// vits-zh-ll 只有固定说话人，不能真的“按描述生成声音”；这里做的是
  /// **稳定映射**：同一段描述永远落到同一个 sid，用户改描述才会换声。
  /// 男/女先粗分，再按描述散列到对应池子里。
  static int sidForDescription(String description) {
    final text = description.trim();
    final male = RegExp(r'男|大叔|磁性|低沉|醇厚|浑厚|青年音|少年音').hasMatch(text);
    final female = RegExp(
      r'女|少女|御姐|萝莉|甜|软糯|清亮|细腻|温柔',
    ).hasMatch(text);
    final pool = male && !female ? _malePool : _femalePool;

    var hash = 0;
    for (final code in text.codeUnits) {
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
