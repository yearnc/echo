import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_info.dart';
import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';

/// 帮助页：常见问题 + 项目地址。
///
/// 写法上刻意避开技术文档的口吻——用户来这里是为了弄明白
/// "为什么评论区是这样的""数据去哪了"，不是为了读设计文档。
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  /// 开源仓库（思政课题要求公开）。
  static const String projectUrl = 'https://github.com/yearnc/echo';
  static const String projectLabel = 'github.com/yearnc/echo';

  static const List<(String, String)> _faq = [
    (
      '评论区里的人都是真的吗？',
      '不是。回响模式里的点赞、评论、私信和住民动态都由 AI 生成，'
          '下面那行「内容由 AI 生成，仅供参考」一直都在。'
          '这个模式想让你观察的是：被回应时，你真正在意的是什么。',
    ),
    (
      '回响模式和清醒模式有什么区别？',
      '回响模式会生成一套虚拟反馈，用来还原"发出去就等着被回应"的那种状态；'
          '清醒模式会关掉这些虚拟互动，只保留你自己的记录、价值澄清和真实行动。'
          '切过去之后，原来的数据不会丢，未执行的虚拟排期会停止。',
    ),
    (
      '固定住民是什么？怎么添加？',
      '设置 → 固定住民 → 添加。TA 不是每条帖子下都出现的 NPC，'
          '而是一个有自己的说话方式、长期记忆和私信的人。'
          '第一次启动会内置一位「大肥鱼」，开箱就有人可聊；'
          '你改过她的设定、或者把她删掉，之后都不会被系统恢复回来。'
          'TA 醒来后会先看有没有人找 TA，再决定回不回；没有待办时，'
          '也可能自己发动态、点赞，或者给你发条私信。',
    ),
    (
      '固定住民为什么回得很慢？',
      '这是故意的：真人不会一直盯着手机。唤醒发生在你发消息/评论之后，'
          '以及 APP 运行时的 30 秒心跳里；私信一般 3 秒、9 秒、15 秒陆续出现，'
          '像真人一句一句敲出来的。没有在等的人时，TA 最多每 1.5 小时醒一次。'
          '你中途又发了一句的话，TA 还没发出去的段会先停下，'
          '下一轮由 TA 自己决定照发、改写还是算了。',
    ),
    (
      '固定住民会记住什么？',
      '记忆由 TA 自己判断：你说过的偏好、经历、约定、情绪变化，'
          '以及图片里是什么、表情包表达的是什么。'
          '配了「图片理解」模型时，图片会先被描述成一句话再交给 TA；'
          '没配时 TA 只知道"收到一张图"。'
          '每条记忆都能在「固定住民 → 记忆」里查看、修改、删除或恢复；'
          '关闭记忆后不再写入、也不再检索。删除记忆不会删除私信和评论原文。',
    ),
    (
      '私信怎么用？',
      '在消息页点一位固定住民就能开始聊，也可以等 TA 先来敲门。'
          '可以发文字、图片、表情包，也可以现场拍一张——'
          '拍的照片只进 APP 自己的目录，不会存进系统相册。'
          'TA 正在做什么只显示在聊天页顶部名字下面：正在思考、正在搜索、'
          '正在写回复；一轮结束但分段消息还没发完时，会显示「正在打字…」。'
          '每条消息下面都有具体时间，TA 也能看见你每条消息是几点说的。',
    ),
    (
      '怎么接入模型？',
      '设置 → 模型配置，填一个 OpenAI 兼容接口的地址、模型名和密钥。'
          '对话、文生图、图片理解、语音合成分开配置，可以只配其中几项。'
          '配好后可以点「测试连接」验证。'
          '固定住民的编辑页还能给每个人单独选一个对话模型（不需要设为全局启用）。',
    ),
    (
      '住民的声音是怎么定的？',
      '每位住民在编辑页里单独开关语音、单独选音色：'
          '本机 vits-zh-ll 有 5 个中文声线（1、3 女声；2、4、5 男声），直接五选一；'
          'ZipVoice 负责“参考音频 + 转录文本”的克隆；'
          '配置了云端 TTS 时，还会多出云端文字描述、云端克隆等选项。'
          '只有固定住民用语音——评论区里的临时网民不再发语音条。'
          '本机克隆目前需要 wav 格式的参考音频。',
    ),
    (
      '能把以前的聊天记录导入给住民吗？',
      '可以。固定住民编辑页 → 行为 → 导入聊天记录：'
          '贴一条 DeepSeek 分享链接（分享 → 复制链接），或者把对话文本粘贴进来，'
          '每段前写「我：」或「AI：」。读取后点“让 TA 读一遍”，'
          'TA 会自己挑出值得长期记住的事写进记忆；整理时会调用你配置的对话模型。',
    ),
    (
      '换手机时数据怎么办？',
      '我的 → 数据备份与恢复 → 导出备份，会生成一个 .echobak 文件，'
          '可以分享到网盘或发给自己。默认模式不用密码、防篡改；'
          '也可以设一个密码，导入时必须输入同一个。'
          '导入会覆盖本机现有全部数据，导入前请先确认当前数据已经导出过。'
          '模型密钥存在系统钥匙串，不在备份里，换机后需要重填一次。',
    ),
    (
      '桌宠是什么？怎么开？',
      '「我的 → 桌宠」可以打开一只住在屏幕上的小鲸鱼女仆，'
          '由你选定的固定住民控制；也可以按时段换人。'
          '它一共有 100 多个动作：待机、点一下的回应、打哈欠、烤火、看烟花……'
          '不需要点名，会自己换着做；走路类动作播放时会真的在屏幕上走一段。'
          '需要系统里的「显示在其他应用上层」和屏幕截取授权，'
          '开启后会有常驻通知，随时能停。普通模式隔十到二十分钟看一眼屏幕，'
          '实时模式会持续看、反复回看。'
          '形象只有一只，和住民是谁无关；控制者只决定是谁在说话和记忆。',
    ),
    (
      '实时观察为什么费 token？',
      '它会在你选的间隔里持续截屏，每次带 2—6 张画面交给当前控制住民，'
          '让它像在你旁边一样点评。截屏频率由“观察间隔 ÷ 帧数”自动决定，'
          '不需要单独设置。开启前会确认成本；关闭时先让它把这段观察写成记忆，'
          '写成功后才删掉临时截图。锁屏时不会截取。'
          '桌宠页有状态卡，可以看到收到了几帧、上次观察有没有成功。',
    ),
    (
      '语音/视频通话会留在私信里吗？',
      '不会留下正文。通话时由本机把你说的话转成文字，直接交给住民回一句；'
          '页面上的回复也只是临时的。挂断后私信里只多一条「通话 03:12」，'
          '通话内容会被总结成一条记忆，然后连同视频帧一起丢弃。'
          '住民正在说的时候按住说话可以打断它。',
    ),
    (
      '住民的日志是什么？',
      '每位住民醒来都会留一条记录：什么时候醒的、因为什么醒、醒了多久，'
          '以及 TA 有没有给下一次的自己留言。入口在住民编辑页最下面。'
          '桌宠开着的时候，整段会算成一次「桌宠醒着」——从打开到关闭记一条，'
          '不是每看一眼就写一条。'
          'TA 也能用工具查自己今天什么时候醒过、给自己留一句话；'
          '下一次醒来时会先看到这句话和留言时间。',
    ),
    (
      '一次唤醒能调用多少工具？',
      '默认最多 12 轮“模型 → 工具 → 模型”，总共 30 秒；有语音时自动多加 60 秒。'
          '设置 → 回响模式里可以自己调（轮数 6—30，超时 15—180 秒）：'
          '调大更完整，调小更省钱。',
    ),
    (
      'APP 关着的时候，固定住民还会活动吗？',
      '会。系统后台任务最小 15 分钟一轮，除了语音（合成太慢），'
          '回消息、回评论、刷帖子、点赞、发动态、画图都允许；'
          '没有待办的人也会按 1.5 小时的空闲间隔醒一次，所以隔天再打开时，'
          'TA 可能已经自己发过动态、接过别人的话。部分手机的省电策略会推迟后台任务。',
    ),
    (
      '语音模型为什么要另外下载？',
      'v4.4 起安装包不再内置几百兆的语音模型，所以装完就能用，体积也小得多。'
          '需要本机识别或合成时，去「我的 → 下载资源」点一下，'
          '会在 APP 里直接下载、解压，不跳浏览器；也可以切换官方源 / 国内镜像。'
          '资源存在应用目录里，升级 APP 不会删掉；只有版本变了才需要重新下载。'
          '没下载时文字聊天照常，语音按钮会提示先去下载。',
    ),
    (
      '桌宠和私信是同一个上下文吗？',
      '是。v4.5 起每位住民只有一条只追加的上下文时间线：屏幕上看到的、冒的气泡、'
          '双方私信、发帖和评论动作都写在同一条线上，每次醒来从同一条线组装消息。'
          '不再有“私信只取最近 10 句”“新私信只给 8 条”这类限制；'
          '只有上下文快到模型窗口上限时，才会自动把前段摘要成一条、保留最近的逐字内容。'
          '这样既不会失忆，缓存前缀也稳定。入口在固定住民编辑页 → 日志下方的「上下文」，'
          '可以查看，也可以只清空上下文（不动长期记忆和私信原文）。',
    ),
    (
      '上下文窗口在哪里改？',
      '模型配置 → 编辑对话模型 → 上下文窗口（token）。默认按 100 万算；'
          '服务商实际更小就填实际值，住民的上下文摘要阈值会按它走。'
          '「我的」页还有一张缓存命中卡，能看到今天和近 7 天的命中率、'
          '输入/命中/输出 token；只统计计数，不记录任何消息内容。',
    ),
    (
      '桌宠换班 / 被杀后台时，记忆会丢吗？',
      '上下文不会整段丢掉。屏幕观察、气泡和私信都在同一条持久时间线里，'
          'APP 被更新或手动清后台也不会消失；到点换控制者时，'
          '会先让上一位把这段观察整理成记忆，再清掉旧截图交给下一位。'
          '只有上下文快到模型窗口上限时才会压缩，压缩前也会先写出摘要。',
    ),
    (
      '桌宠怎么才能一直在后台？',
      '「我的 → 桌宠 → 后台」可以申请关闭电池优化，也能跳到应用详情去开自启动。'
          '桌宠和屏幕观察本身是前台服务，但荣耀、华为、小米这类系统'
          '还会额外清后台，需要你在系统设置里手动允许一次。',
    ),
    (
      '怎么检查更新？',
      '「我的 → 检查更新」会去项目的 GitHub Releases 查最新版本，'
          '只读一个公开接口、不上传任何本机数据。发现新版本时会显示更新说明，'
          '可以直接打开发布页下载。检查失败只提示原因，不影响使用。',
    ),
    (
      '联网搜索怎么开？',
      '设置 → 联网搜索，选一个服务商。DeepSeek 走独立搜索接口，'
          '只要模型配置里有一条填好 Key 的 DeepSeek 配置就能用，'
          '不用把它设为当前对话模型；智谱和百炼则要配一条对应服务商的配置。'
          '搜索失败会直说，不会拿记忆冒充实时结果。',
    ),
    (
      '表情包怎么导入？AI 会用吗？',
      '设置 → 头像与表情包 → 导入：先选图，看到预览之后再起名字、贴标签。'
          '标签决定 AI 什么时候用它——「安慰 / 抱抱」会被用在对方难过时，'
          '「吐槽」不会。没有标签的表情，AI 不会用。',
    ),
    (
      '「按脚本安排互动」是什么？',
      '发布页右上角的策划模式。打开后，这条帖子不按随机时间收到回应，'
          '而是按脚本里写好的秒数逐条执行：第几秒谁点赞、谁评论、说什么。'
          '评论区里出现的人会是固定住民，或者这次脚本专用的临时网友。',
    ),
    (
      '我的数据存在哪里？',
      '全部存在这台设备上（应用私有目录里的本地数据库），不上传服务器。'
          '只有配置了模型之后，生成内容所需的那段文字才会发送给你选择的模型服务商。'
          '想换设备或留一份副本，用「我的 → 数据备份与恢复」。',
    ),
    (
      '为什么互动有时候不来？',
      '互动排期会摊开在很长一段时间里，也可能因为模型超时、断网而少几次。'
          '少来的互动不会用假台词补上——这是有意的取舍。',
    ),
    (
      '为什么没有收到系统通知？',
      '系统通知需要在手机设置里允许「回响」发送通知。'
          'APP 打开时不会弹系统通知，提醒只留在通知页；'
          '切到后台后，到点的互动才会交给系统来提醒。'
          '部分手机的省电策略会推迟后台任务，这是系统的限制，我们仍会在你打开 APP 时补上。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          '帮助',
          style: TextStyle(
            color: EchoColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: EchoColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: EchoColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '常见问题',
                  style: TextStyle(
                    color: EchoColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '没找到答案的话，可以到项目仓库提一个 issue。',
                  style: TextStyle(color: EchoColors.textFaint, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _TutorialCard(),
          const SizedBox(height: 12),
          for (final (question, answer) in _faq)
            _FaqTile(question: question, answer: answer),
          const SizedBox(height: 8),
          const _ProjectCard(),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '当前版本 $appVersion',
              style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              AppTexts.aiDisclaimer,
              style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// 第一次打开会自动弹一次；之后从这里随时能重看。
class _TutorialCard extends StatelessWidget {
  const _TutorialCard();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(RoutePaths.tutorial),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: EchoColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: EchoColors.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.school_outlined, size: 20, color: EchoColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '新手教程',
                    style: TextStyle(
                      color: EchoColors.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '六页看完：两种模式、固定住民、模型和策划模式',
                    style: TextStyle(
                      color: EchoColors.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: EchoColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: EchoColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EchoColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          // 展开箭头用我们的强调色，不用主题默认的蓝
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            iconTheme: IconThemeData(color: EchoColors.textMuted),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            title: Text(
              question,
              style: TextStyle(color: EchoColors.text, fontSize: 13.5),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  answer,
                  style: TextStyle(
                    color: EchoColors.textMuted,
                    fontSize: 12.5,
                    height: 1.7,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.code, size: 17, color: EchoColors.textMuted),
              const SizedBox(width: 8),
              Text(
                '项目地址',
                style: TextStyle(
                  color: EchoColors.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            HelpPage.projectUrl,
            style: TextStyle(color: EchoColors.primary, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '源码、版本记录和使用说明都在这里。',
            style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
