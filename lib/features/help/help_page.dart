import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_info.dart';
import '../../core/constants/app_texts.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import 'help_faq.dart';

/// 帮助页一级页面（v50）。
///
/// 只显示问题分类和入口；点进去才是“分类 → 具体问题与答案”。
/// 问题多起来以后，一屏塞满 ExpansionTile 会很难找东西。
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  /// 开源仓库（思政课题要求公开）。
  static const String projectUrl = 'https://github.com/yearnc/echo';
  static const String projectLabel = 'github.com/yearnc/echo';

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
                  '先选一个分类，再找具体问题。没找到答案的话，可以到项目仓库提一个 issue。',
                  style: TextStyle(color: EchoColors.textFaint, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _TutorialCard(),
          const SizedBox(height: 14),
          for (final category in helpFaq)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _CategoryTile(category: category),
            ),
          const SizedBox(height: 10),
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

/// 二级页面：某个分类下的全部问题与答案。
class HelpCategoryPage extends StatelessWidget {
  const HelpCategoryPage({super.key, required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context) {
    final category = helpCategoryById(categoryId);
    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          category?.title ?? '帮助',
          style: TextStyle(
            color: EchoColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: category == null
          ? Center(
              child: Text(
                '这个分类不在了',
                style: TextStyle(color: EchoColors.textMuted, fontSize: 13),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                Text(
                  category.hint,
                  style: TextStyle(
                    color: EchoColors.textFaint,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                for (final item in category.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _QaCard(item: item),
                  ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '还有问题？到 ${HelpPage.projectLabel} 提 issue。',
                    style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});

  final HelpFaqCategory category;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push(RoutePaths.helpCategory(category.id)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        decoration: BoxDecoration(
          color: EchoColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EchoColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: EchoColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(category.icon, size: 19, color: EchoColors.primary),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.title,
                    style: TextStyle(
                      color: EchoColors.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${category.hint} · ${category.items.length} 个问题',
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

class _QaCard extends StatelessWidget {
  const _QaCard({required this.item});

  final HelpFaqItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.question,
            style: TextStyle(
              color: EchoColors.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            item.answer,
            style: TextStyle(
              color: EchoColors.textMuted,
              fontSize: 12.5,
              height: 1.7,
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
          border: Border.all(color: EchoColors.primary.withValues(alpha: 0.35)),
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
