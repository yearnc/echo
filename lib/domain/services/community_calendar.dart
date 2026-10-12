/// 大家身边正在发生的事（B6）。**纯逻辑，只看日期**。
///
/// 它存在的理由很实际：没有它，住民的话永远是"今天也是普通的一天"。
/// 有了它，降温那天半个社区都在喊冷、长假最后一天会有人叹气——
/// 那种"大家过的是同一段日子"的感觉，是社区像不像真的分水岭。
///
/// 日期**按公历粗略切**，不查农历、不接天气服务：这是作品里的社区，
/// 不是气象台。真接真数据是阶段 C 的事。
///
/// 这里刻意**不设"某个群体的日程"**（没有开学、没有考试周、没有工位上的
/// 月底冲刺）：住民的作息已经写在他自己的 routines 里了，社区这一层
/// 只该说"大家共同经历的那点事"。
class CommunityCalendar {
  const CommunityCalendar._();

  static const CommunityEvent coldSnap = CommunityEvent(
    title: '降温',
    hint: '这两天降温了，风很硬，路上的人都缩着脖子',
    samples: [
      '今天怎么这么冷，出门忘穿外套了。',
      '风硬得像刀子，走两步耳朵就没了。',
      '屋里开着暖气，一点不想出门。',
    ],
  );

  static const CommunityEvent hotSnap = CommunityEvent(
    title: '高温',
    hint: '这两天热得厉害，中午的太阳晒得人发晕',
    samples: [
      '中午的太阳太毒了，走一趟就是一身汗。',
      '屋里待着不动都出汗，什么都不想干。',
    ],
  );

  static const CommunityEvent weekend = CommunityEvent(
    title: '周末',
    hint: '今天是周末，大家都没什么正事',
    samples: [
      '周末的好处就是可以什么都不干。',
      '一觉睡到中午，起来发现天都快黑了。',
      '周末街上人比平时多，慢慢走挺好的。',
    ],
  );

  static const CommunityEvent nationalDay = CommunityEvent(
    title: '国庆',
    hint: '这几天是长假，路上人多，店也开着',
    samples: [
      '假期里街上空了一半，店都关着门。',
      '哪儿都没去，在家躺了两天。',
    ],
  );

  static const CommunityEvent newYear = CommunityEvent(
    title: '元旦',
    hint: '今天是元旦，新的一年的第一天',
    samples: ['新的一年了，随便写点什么吧。', '跨年那天楼下吵到两点。'],
  );

  static const CommunityEvent labourDay = CommunityEvent(
    title: '劳动节',
    hint: '这几天放五一假，天气刚好',
    samples: ['五一出去转了转，到处都是人。', '假期没出门，在家睡了两天。'],
  );

  static const CommunityEvent christmas = CommunityEvent(
    title: '圣诞',
    hint: '今天是圣诞，商场和街上都在过节',
    samples: ['商场里全是圣诞的歌，逛一圈还挺热闹。', '朋友送了盒巧克力，甜得发腻。'],
  );

  /// 这一天大家身边有什么可说的。可能不止一件（周末 + 降温）。
  ///
  /// **顺序就是轻重**：节日排在最前，那天大家说的都是这件事。
  static List<CommunityEvent> of(DateTime date) {
    final events = <CommunityEvent>[];

    final holiday = _holidayOf(date);
    if (holiday != null) events.add(holiday);

    // 周末排在天气前面：周末是"今天可以不上班"，比刮什么风更值得说
    if (date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday) {
      events.add(weekend);
    }

    if (_isColdSeason(date.month)) {
      events.add(coldSnap);
    } else if (date.month >= 6 && date.month <= 8) {
      events.add(hotSnap);
    }

    return events;
  }

  /// 最值得一提的那一件；没有就是 null。
  static CommunityEvent? strongestAt(DateTime date) {
    final events = of(date);
    return events.isEmpty ? null : events.first;
  }

  /// 给模型看的那几行背景。空列表表示"今天没什么特别的"。
  static List<String> hintsAt(DateTime date) =>
      [for (final event in of(date)) event.hint];

  /// 十一月到二月算冷。三月到五月、九月十月是最舒服的那两个月。
  static bool _isColdSeason(int month) =>
      month == 11 || month == 12 || month == 1 || month == 2;

  static CommunityEvent? _holidayOf(DateTime date) {
    if (date.month == 1) {
      // 元旦只算头三天，不然整个一月都在过年
      return date.day <= 3 ? newYear : null;
    }
    if (date.month == 5 && date.day <= 3) return labourDay;
    if (date.month == 10 && date.day <= 7) return nationalDay;
    if (date.month == 12 && date.day >= 23 && date.day <= 26) {
      return christmas;
    }
    return null;
  }
}

/// 一件"大家身边正在发生的事"。
class CommunityEvent {
  const CommunityEvent({
    required this.title,
    required this.hint,
    this.samples = const [],
  });

  /// 短名，界面上也用得着（"最近大家身边：降温"）。
  final String title;

  /// 给模型看的一句话背景。
  final String hint;

  /// 没配模型时，住民可以从这几句里挑一句。
  final List<String> samples;
}
