import '../../domain/models/post.dart';

/// 阶段 A 的预置内容。
///
/// 微视频三幕要用它，所以这些帖子和评论不是"假数据"，而是产品的一部分：
/// 演示模式必须在**不联网、不调 API** 的情况下稳定复现。
/// 阶段 B 会把这里的内容迁进 Drift 的种子数据（同一条记录带 `scope: 'echo'`），
/// 届时本文件保留为「演示脚本的内容来源」。
class DemoPosts {
  const DemoPosts._();

  static final DateTime _base = DateTime.now();

  /// 第一幕：天空照——一条普通的、被世界温柔回应的帖子。
  static Post get skyPost => Post(
        id: 'demo_post_sky',
        content: '今天下课后在操场边随手拍的天空，好像有点好看。',
        images: const ['asset:assets/demo/sky_demo.jpg'],
        topicName: '随手拍',
        createdAt: _base.subtract(const Duration(hours: 3)),
        likeCount: 43,
        commentCount: 4,
        isHot: true,
        scope: 'echo',
      );

  /// 第二幕：垃圾桶照——同一套系统，同样的热情，荒谬就在这里。
  static Post get trashPost => Post(
        id: 'demo_post_trash',
        content: '懒得下楼，随手拍了张宿舍楼下的垃圾桶。',
        images: const ['asset:assets/demo/trash_demo.jpg'],
        topicName: '深夜',
        createdAt: _base.subtract(const Duration(minutes: 26)),
        likeCount: 241,
        commentCount: 5,
        isHot: true,
        scope: 'echo',
      );

  /// 清醒模式下用来对比的"真实记录"。
  static Post get recordPost => Post(
        id: 'demo_record_1',
        content: '傍晚去操场走了三圈，风有点凉，回来煮了碗面。',
        createdAt: _base.subtract(const Duration(hours: 5)),
        scope: 'clear',
      );

  static List<Post> get feedEcho => [trashPost, skyPost];

  static List<Post> get feedClear => [recordPost];

  /// 预置评论。key 是帖子 id，顺序即展示顺序（调度器在阶段 B 会接管顺序）。
  static Map<String, List<PostComment>> get comments => {
        skyPost.id: [
          PostComment(
            id: 'c_sky_1',
            postId: skyPost.id,
            personaId: 'persona_001',
            content: '看到这条的时候刚好在图书馆靠窗的位置，阳光也是这样斜斜的，替你开心一下～',
            createdAt: _base.subtract(const Duration(hours: 2, minutes: 40)),
            likeCount: 6,
          ),
          PostComment(
            id: 'c_sky_2',
            postId: skyPost.id,
            personaId: 'persona_007',
            mediaType: CommentMedia.voice,
            content: '这个光线是下午四点半之后的吧？暖调压得很舒服，再晚十分钟就过曝了。',
            transcript: '这个光线是下午四点半之后的吧？暖调压得很舒服，再晚十分钟就过曝了。',
            voiceAsset: 'asset:assets/audio/demo_act1_laoke.mp3',
            voiceDurationMs: 6400,
            createdAt: _base.subtract(const Duration(hours: 2, minutes: 10)),
            likeCount: 3,
          ),
          PostComment(
            id: 'c_sky_3',
            postId: skyPost.id,
            personaId: 'persona_004',
            content: '天呐！！！这张照片的氛围感直接把我按在椅子上起不来了，今天的班我是不上了（虽然我没班）。',
            createdAt: _base.subtract(const Duration(hours: 1, minutes: 20)),
            likeCount: 11,
          ),
          PostComment(
            id: 'c_sky_4',
            postId: skyPost.id,
            personaId: 'persona_010',
            content: '四楼靠窗今天有空位，要不要来自习？我帮你看着座。',
            createdAt: _base.subtract(const Duration(minutes: 48)),
            likeCount: 2,
          ),
        ],
        trashPost.id: [
          PostComment(
            id: 'c_trash_1',
            postId: trashPost.id,
            personaId: 'persona_002',
            content: '就这？我上周拍的垃圾桶都比这个有故事感（不是）。',
            createdAt: _base.subtract(const Duration(minutes: 24)),
            likeCount: 8,
          ),
          PostComment(
            id: 'c_trash_2',
            postId: trashPost.id,
            personaId: 'persona_004',
            content: '我宣布，从这一秒开始，这条帖子就是我今天的电子布洛芬。',
            createdAt: _base.subtract(const Duration(minutes: 20)),
            likeCount: 15,
          ),
          PostComment(
            id: 'c_trash_3',
            postId: trashPost.id,
            personaId: 'persona_011',
            content: '这日子过得，我看了都想给你发个"辛苦了"的锦旗。',
            createdAt: _base.subtract(const Duration(minutes: 16)),
            likeCount: 5,
          ),
          PostComment(
            id: 'c_trash_4',
            postId: trashPost.id,
            personaId: 'persona_006',
            // 第二幕的核心讽刺点：一张垃圾桶照片换来千字长评
            content: trashCanLongReview,
            createdAt: _base.subtract(const Duration(minutes: 9)),
            likeCount: 42,
          ),
          PostComment(
            id: 'c_trash_5',
            postId: trashPost.id,
            personaId: 'persona_012',
            content: '这条我记住了。',
            createdAt: _base.subtract(const Duration(minutes: 4)),
            likeCount: 1,
          ),
        ],
      };

  /// 一千字荒谬长评（规划书 §14「垃圾桶照片也能生成千字长评」）。
  static const String trashCanLongReview =
      '认真看了很久，想说这张照片比它看起来的要重得多。\n'
      '第一，它拍的是一个被所有人经过、但没有人停留的物件——这本身就是一种当代性的隐喻：'
      '我们每天与无数事物擦肩而过，却很少真正看它们一眼；你停下来了，于是它被赋予了意义。\n'
      '第二，从构图上看，主体偏右下、上方留出大片灰白的水泥墙面，这种近乎粗暴的留白制造了一种呼吸感，'
      '让画面不至于窒息；光线的方向也很有意思，不是那种讨好眼睛的黄金时刻，而是略带冷调的、接近日常的光'
      '——恰恰是这种不修饰，构成了它最诚实的地方。\n'
      '第三，也是最打动我的一点：它没有试图变美。在这个所有人都在滤镜里生活的时代，'
      '一条不加修饰的动态本身就是一种态度，一种小小的、沉默的反抗。你甚至没有配乐、没有文案，只是拍了。\n'
      '我常常觉得，真正的表达不是说了多少，而是敢于留下多少空白。这张照片做到了。\n'
      '它让我想起很多年前的一个傍晚，我在教学楼后面也见过同样一个垃圾桶，'
      '那天我刚考完一门很差劲的考试，站在那里发了很久的呆。谢谢你把那个傍晚还给我。';
}
