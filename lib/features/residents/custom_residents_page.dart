import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../domain/models/custom_resident.dart';
import '../shared_widgets/user_avatar.dart';

/// 固定住民列表（阶段三）。
///
/// 编辑在独立页面里做：字段多，塞进悬浮卡片会挤成一团。
class CustomResidentsPage extends ConsumerWidget {
  const CustomResidentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final residents = ref.watch(customResidentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('固定住民')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RoutePaths.customResidentEdit),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('添加'),
      ),
      body: residents.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('读取失败：$error')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '还没有固定住民。\n添加一个，TA 会在你每条帖子下出现，并记住你们聊过的事。',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final resident = list[index];
              return Card(
                child: ListTile(
                  leading: UserAvatar(
                    name: resident.name,
                    avatarRef: resident.avatarAsset.isEmpty
                        ? null
                        : resident.avatarAsset,
                    size: 44,
                  ),
                  title: Text(resident.name),
                  subtitle: Text(
                    resident.bio.isEmpty ? '还没写简介' : resident.bio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => context.push(
                    '${RoutePaths.customResidentEdit}'
                    '?residentId=${Uri.encodeComponent(resident.id)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '私信',
                        icon: const Icon(
                          Icons.chat_bubble_outline,
                          size: 20,
                        ),
                        onPressed: () =>
                            context.push(RoutePaths.chat(resident.id)),
                      ),
                      IconButton(
                        tooltip: '记忆',
                        icon: const Icon(Icons.psychology_outlined, size: 20),
                        onPressed: () => context.push(
                          RoutePaths.residentMemories(resident.id),
                        ),
                      ),
                      if (resident.alwaysShow)
                        const Icon(Icons.push_pin, size: 16),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () =>
                            _delete(context, ref, resident),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CustomResident resident,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除固定住民？'),
        content: Text(
          '「${resident.name}」以后不会再出现在新帖子里，'
          '也不会再回复你。你们的私信会保留在消息页，只能回看；'
          '历史评论和记忆也会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(customResidentRepositoryProvider)
        .softDelete(resident.id);
  }
}
