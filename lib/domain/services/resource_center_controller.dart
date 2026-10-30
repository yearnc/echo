import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/model_resource.dart';
import 'resource_catalog.dart';
import 'resource_manager.dart';

/// 「下载资源」页的状态（v4.4）。
///
/// 下载进度、失败原因都放在这里；页面只负责画，不直接碰文件系统。
class ResourceCenterController extends ChangeNotifier {
  ResourceCenterController(this._manager, this._catalog);

  final ResourceManager _manager;
  final ResourceCatalog _catalog;

  List<ModelResource> resources = const [];
  final Map<String, InstalledResource?> installed = {};
  final Map<String, double> progress = {};
  final Map<String, String> errors = {};
  final Set<String> busy = {};
  ResourceSource source = ResourceSource.github;
  bool loading = false;
  String note = '';

  Future<void> load({bool refreshManifest = false}) async {
    loading = true;
    notifyListeners();
    try {
      source = await _manager.source();
      resources = await _catalog.load(refresh: refreshManifest);
      installed.clear();
      for (final resource in resources) {
        installed[resource.id] = await _manager.installed(resource);
      }
      errors.clear();
      note = refreshManifest && resources.isNotEmpty ? '已检查完资源版本' : '';
    } catch (error) {
      note = '资源列表没读出来：$error';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> changeSource(ResourceSource value) async {
    if (source == value) return;
    source = value;
    notifyListeners();
    await _manager.setSource(value);
  }

  Future<void> download(ModelResource resource) async {
    if (busy.contains(resource.id)) return;
    busy.add(resource.id);
    progress[resource.id] = 0;
    errors.remove(resource.id);
    notifyListeners();
    try {
      await _manager.download(
        resource,
        source: source,
        onProgress: (value) {
          progress[resource.id] = value;
          notifyListeners();
        },
      );
      installed[resource.id] = await _manager.installed(resource);
      progress.remove(resource.id);
      note = '${resource.name} 装好了';
    } catch (error) {
      errors[resource.id] = '$error';
      progress.remove(resource.id);
    } finally {
      busy.remove(resource.id);
      notifyListeners();
    }
  }

  Future<void> remove(ModelResource resource) async {
    if (busy.contains(resource.id)) return;
    busy.add(resource.id);
    notifyListeners();
    try {
      await _manager.delete(resource);
      installed[resource.id] = null;
      note = '${resource.name} 已删除';
    } catch (error) {
      errors[resource.id] = '删除失败：$error';
    } finally {
      busy.remove(resource.id);
      notifyListeners();
    }
  }
}

final resourceCenterControllerProvider =
    ChangeNotifierProvider<ResourceCenterController>((ref) {
      return ResourceCenterController(
        ref.watch(resourceManagerProvider),
        ResourceCatalog(),
      );
    });
