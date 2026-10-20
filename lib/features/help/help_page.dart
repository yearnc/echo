import 'package:flutter/material.dart';

import '../../core/constants/app_texts.dart';
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
          '切过去之后，原来的数据不会丢。',
    ),
    (
      '怎么添加固定住民？',
      '设置 → 固定住民 → 添加。TA 会在你每条帖子下出现，有自己的头像、'
          '说话方式和长期记忆；关闭后就不再出现了。',
    ),
    (
      '固定住民会记住什么？',
      '只记你明确说过的事实、偏好和事件，比如"最近在学做菜"。'
          '每条记忆都能查看、修改、删除；关闭记忆后不再写入，'
          '已有记忆仍然由你处置。删除记忆不会删除私信和评论原文。',
    ),
    (
      '私信怎么用？',
      '在消息页列表里点一位固定住民就能开始聊，也可以等他先来敲门。'
          '第一次开口会用你在设定里写的「开场白」。回得不会很快——'
          '这是故意的，真人也不会秒回。',
    ),
    (
      '为什么没有收到系统通知？',
      '系统通知需要在手机设置里允许「回响」发送通知。'
          'APP 打开时不会弹系统通知，提醒只留在通知页；'
          '切到后台后，到点的互动才会交给系统来提醒。',
    ),
    (
      '我的数据存在哪里？',
      '全部存在这台设备上（应用私有目录里的本地数据库），不上传服务器。'
          '只有配置了模型之后，生成内容所需的那段文字才会发送给你选择的模型服务商。',
    ),
    (
      '怎么接入模型？',
      '设置 → 模型配置，填一个 OpenAI 兼容接口的地址、模型名和密钥。'
          '对话和文生图分开配置，配好后可以点「测试连接」验证。'
          '没有模型时，评论和动态不会硬凑固定台词。',
    ),
    (
      '为什么互动有时候不来？',
      '互动排期会摊开在很长一段时间里，也可能因为模型超时、断网而少几次。'
          '少来的互动不会用假台词补上——这是有意的取舍。',
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
          for (final (question, answer) in _faq)
            _FaqTile(question: question, answer: answer),
          const SizedBox(height: 8),
          const _ProjectCard(),
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
