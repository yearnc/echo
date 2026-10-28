import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';

/// 新手教程（2026-10-24）。
///
/// 目的不是把功能表念一遍，而是让第一次打开的人知道：
/// 这里是 AI 生成的社区、两种模式各在做什么、固定住民为什么会“过一会儿才回”。
/// 六页，能扫完；右上角随时跳过。
class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key});

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<_GuideStep> _steps = [
    _GuideStep(
      icon: Icons.auto_awesome,
      title: '这里住着一群 AI',
      body: '回响广场里的点赞、评论、私信和住民动态，都是由 AI 生成的。'
          '每页底部那行「内容由 AI 生成，仅供参考」不是装饰，它一直在提醒这件事。',
      points: ['这是一个可以观察“被回应”的地方', '不是真人社区，也不会上传你的内容'],
    ),
    _GuideStep(
      icon: Icons.nights_stay_outlined,
      title: '两种模式，看同一条帖子',
      body: '回响模式会为你聚起一群网友，让你体验“发出去就等着被回应”的状态；'
          '清醒模式关掉所有虚拟反馈，只留下你自己的记录、分析和真实行动。',
      points: ['随时可以在「我的 / 设置」里切换', '切到清醒模式后，虚拟排期会停止'],
    ),
    _GuideStep(
      icon: Icons.edit_note,
      title: '发帖和评论区',
      body: '在「发布」写下此刻想说的话，可以带图、选话题。发出去之后，'
          '评论区会陆续出现不同的人——他们只在这条帖子里出现，像路过的人。',
      points: ['评论按说话顺序排列，最早的在上', '点某条评论可以直接回复，楼中楼不会乱'],
    ),
    _GuideStep(
      icon: Icons.favorite_outline,
      title: '固定住民，是你请来的邻居',
      body: '在「设置 → 固定住民」添加一个角色，TA 会有自己的说话方式、长期记忆，'
          '也会主动给你发私信。醒来后先看有没有人找 TA，再决定回不回。',
      points: [
        'TA 不会秒回：真人也不会一直盯着手机',
        '记忆只记你明确说过的事，可随时查看、修改、删除',
        '每位住民可以单独指定一个对话模型',
      ],
    ),
    _GuideStep(
      icon: Icons.tune,
      title: '模型和联网搜索',
      body: '在「设置 → 模型配置」里填一个 OpenAI 兼容接口。对话、文生图、'
          '图片理解、语音合成是分开的，可以只配其中几项。',
      points: [
        '没配模型时，社区不会硬凑固定台词',
        '联网搜索要单独选服务商；DeepSeek 只要配置里有 Key 就能用',
      ],
    ),
    _GuideStep(
      icon: Icons.theater_comedy_outlined,
      title: '还有几件小事',
      body: '「策划模式」在发布页右上角，可以让一条帖子按脚本的秒数收到回应，'
          '适合演示和拍摄。表情包在「设置 → 头像与表情包」导入，打完标签 AI 才会用。',
      points: [
        '所有数据都存在这台设备上',
        '遇到问题看「我的 → 帮助」，也可以到项目仓库提 issue',
      ],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page >= _steps.length - 1) {
      context.go(RoutePaths.feed);
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _steps.length - 1;
    return Scaffold(
      backgroundColor: EchoColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Text(
                    '新手教程',
                    style: TextStyle(color: EchoColors.textMuted, fontSize: 12.5),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.go(RoutePaths.feed),
                    child: Text(
                      '跳过',
                      style: TextStyle(
                        color: EchoColors.textFaint,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _steps.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) =>
                    _StepView(step: _steps[index], index: index),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _steps.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? EchoColors.primary
                                : EchoColors.divider,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(last ? '开始探索' : '下一步'),
                    ),
                  ),
                  if (last) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: () => context.push(RoutePaths.models),
                      icon: const Icon(Icons.settings_outlined, size: 16),
                      label: const Text('先去配置模型'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({required this.step, required this.index});

  final _GuideStep step;
  final int index;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: EchoColors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(step.icon, color: EchoColors.primary, size: 26),
          ),
          const SizedBox(height: 20),
          Text(
            '${index + 1} / 6',
            style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
          ),
          const SizedBox(height: 6),
          Text(
            step.title,
            style: TextStyle(
              color: EchoColors.text,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            step.body,
            style: TextStyle(
              color: EchoColors.textMuted,
              fontSize: 14,
              height: 1.85,
            ),
          ),
          const SizedBox(height: 20),
          for (final point in step.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: EchoColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      point,
                      style: TextStyle(
                        color: EchoColors.textMuted,
                        fontSize: 13,
                        height: 1.65,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GuideStep {
  const _GuideStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.points,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<String> points;
}
