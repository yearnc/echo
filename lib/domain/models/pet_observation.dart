/// 桌宠这一眼看到的东西（v4.0）。
///
/// 普通模式一般只有一张截图（或它的文字描述）；实时模式是最近几帧原图
/// 加上这段会话此前攒下的简短摘要。走的是同一条唤醒通道。
class PetObservation {
  const PetObservation({
    this.images = const [],
    this.note = '',
    this.realtime = false,
    this.selfImage,
  });

  /// `file:` 引用。只有对话模型能看图时才会真的附进消息。
  final List<String> images;

  /// 给住民的文字说明：普通模式的画面描述，或实时模式的“这是刚刚的几秒”。
  final String note;

  final bool realtime;

  /// 桌宠自己的样子（`asset:` 引用）。
  ///
  /// 屏幕截图会把它自己一起截进去；不给一张参照图，模型会把那个小家伙
  /// 当成屏幕上的另一个人。每轮附一张，代价很小。
  final String? selfImage;

  bool get isEmpty => images.isEmpty && note.trim().isEmpty;
}
