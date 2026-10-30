import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/model_resource.dart';
import '../../domain/services/resource_center_controller.dart';

/// 「我的 → 下载资源」（v4.4）。
///
/// 精简版 APK 不带模型，需要哪项就点哪项下载。下载直接走应用内，
/// 不跳浏览器；可以切官方源 / 国内镜像，也可以删除不再需要的资源。
class ResourcePage extends ConsumerStatefulWidget {
  const ResourcePage({super.key});

  @override
  ConsumerState<ResourcePage> createState() => _ResourcePageState();
}

class _ResourcePageState extends ConsumerState<ResourcePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(resourceCenterControllerProvider).load();
    });
  }

  Future<void> _delete(ModelResource resource) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: EchoColors.surface,
        title: const Text('删除这个资源？'),
        content: Text(
          '会删掉手机里的「${resource.name}」，释放约 ${resource.sizeLabel}。'
          '以后想用可以再下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('留着'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(resourceCenterControllerProvider).remove(resource);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(resourceCenterControllerProvider);
    final installedBytes = controller.installed.values
        .whereType<InstalledResource>()
        .fold<int>(0, (sum, item) => sum + item.bytes);

    return Scaffold(
      backgroundColor: EchoColors.bg,
      appBar: AppBar(
        backgroundColor: EchoColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: EchoColors.text),
        title: Text(
          '下载资源',
          style: TextStyle(
            color: EchoColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '检查更新',
            onPressed: controller.loading
                ? null
                : () => controller.load(refreshManifest: true),
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          _IntroCard(
            source: controller.source,
            installedBytes: installedBytes,
            onSource: controller.changeSource,
          ),
          if (controller.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              controller.note,
              style: TextStyle(color: EchoColors.textMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          if (controller.loading && controller.resources.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(color: EchoColors.primary),
              ),
            ),
          for (final resource in controller.resources) ...[
            _ResourceCard(
              resource: resource,
              installed: controller.installed[resource.id],
              busy: controller.busy.contains(resource.id),
              progress: controller.progress[resource.id] ?? 0,
              error: controller.errors[resource.id] ?? '',
              onDownload: () => controller.download(resource),
              onDelete: () => _delete(resource),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          Text(
            '资源存在手机的应用目录里，升级 APP 不会把它们删掉。'
            '只有版本变了才需要重新下载，没变的继续用。',
            style: TextStyle(
              color: EchoColors.textFaint,
              fontSize: 11.5,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({
    required this.source,
    required this.installedBytes,
    required this.onSource,
  });

  final ResourceSource source;
  final int installedBytes;
  final ValueChanged<ResourceSource> onSource;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EchoColors.divider, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '这一版不带模型',
            style: TextStyle(
              color: EchoColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '语音合成、语音识别这些功能需要本机模型。'
            '没有下载时，文字聊天照常，相关按钮会提示先来下载。',
            style: TextStyle(
              color: EchoColors.textMuted,
              fontSize: 12,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.download_outlined,
                size: 15,
                color: EchoColors.textFaint,
              ),
              const SizedBox(width: 6),
              Text(
                installedBytes <= 0
                    ? '本机还没装模型'
                    : '已占用 ${(installedBytes / 1024 / 1024).round()} MB',
                style: TextStyle(color: EchoColors.textFaint, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '下载源',
                style: TextStyle(color: EchoColors.textMuted, fontSize: 12),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SegmentedButton<ResourceSource>(
                  segments: [
                    for (final item in ResourceSource.values)
                      ButtonSegment(
                        value: item,
                        label: Text(
                          item.label,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                  ],
                  selected: {source},
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(fontSize: 11.5, color: EchoColors.text),
                    ),
                  ),
                  onSelectionChanged: (value) {
                    if (value.isNotEmpty) onSource(value.first);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.resource,
    required this.installed,
    required this.busy,
    required this.progress,
    required this.error,
    required this.onDownload,
    required this.onDelete,
  });

  final ModelResource resource;
  final InstalledResource? installed;
  final bool busy;
  final double progress;
  final String error;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final version = installed?.version ?? 0;
    final hasIt = version > 0;
    final needsUpdate = hasIt && version < resource.version;
    final status = !hasIt
        ? '未下载'
        : needsUpdate
        ? '有新版本 v${resource.version}'
        : '已安装 v$version';
    final statusColor = !hasIt
        ? EchoColors.textFaint
        : needsUpdate
        ? EchoColors.primary
        : EchoColors.like;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: EchoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EchoColors.divider, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resource.name,
                      style: TextStyle(
                        color: EchoColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      resource.description,
                      style: TextStyle(
                        color: EchoColors.textMuted,
                        fontSize: 11.5,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                resource.sizeLabel,
                style: TextStyle(color: EchoColors.textFaint, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (hasIt)
                TextButton(
                  onPressed: busy ? null : onDelete,
                  child: const Text('删除'),
                ),
              if (!hasIt || needsUpdate)
                FilledButton(
                  onPressed: busy ? null : onDownload,
                  child: Text(needsUpdate ? '更新' : '下载'),
                ),
            ],
          ),
          if (busy) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress <= 0 ? null : progress,
                minHeight: 5,
                backgroundColor: EchoColors.surfaceHigh,
                color: EchoColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              progress <= 0
                  ? '准备下载…'
                  : '已下载 ${(progress * 100).round()}%（可以留在这一页看进度）',
              style: TextStyle(color: EchoColors.textFaint, fontSize: 10.5),
            ),
          ],
          if (error.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              error,
              style: TextStyle(color: EchoColors.like, fontSize: 11, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
