import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_info.dart';

/// 一次检查更新的结果。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    this.latestVersion = '',
    this.notes = '',
    this.url = '',
    this.publishedAt = '',
    this.error = '',
  });

  final String currentVersion;
  final String latestVersion;
  final String notes;
  final String url;
  final String publishedAt;
  final String error;

  bool get failed => error.isNotEmpty;
  bool get hasUpdate =>
      !failed && compareVersions(latestVersion, currentVersion) > 0;

  /// 版本号比较：只比数字段，`v3.7.0+15` / `3.7.0` / `3.7.0-rc1` 都能吃。
  static int compareVersions(String a, String b) {
    List<int> parts(String raw) {
      final cleaned = raw.trim().replaceFirst(RegExp(r'^v'), '');
      final core = cleaned.split(RegExp(r'[+\-]')).first;
      return [
        for (final piece in core.split('.'))
          int.tryParse(piece.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
      ];
    }

    final left = parts(a);
    final right = parts(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final x = i < left.length ? left[i] : 0;
      final y = i < right.length ? right[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}

/// 查 GitHub 上最新一次 Release（v41）。
///
/// 这是唯一会主动访问本项目仓库的地方：只读一个公开接口，
/// 不发任何本机数据（连设备号都不带）。检查失败不该打扰使用，
/// 调用方只需要显示一行原因。
class UpdateService {
  UpdateService({Dio? dio, this.currentVersion = appVersion})
    : _dio = dio ?? Dio();

  final Dio _dio;
  final String currentVersion;

  static const String releasesApi =
      'https://api.github.com/repos/yearnc/echo/releases/latest';
  static const String releasesPage = 'https://github.com/yearnc/echo/releases/latest';

  Future<UpdateCheckResult> check() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        releasesApi,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'echo-app',
          },
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
      final data = response.data ?? const <String, dynamic>{};
      final tag = (data['tag_name'] as String?)?.trim() ?? '';
      if (tag.isEmpty) {
        return UpdateCheckResult(
          currentVersion: currentVersion,
          error: '仓库还没有发布过版本',
        );
      }
      final url = (data['html_url'] as String?)?.trim() ?? '';
      return UpdateCheckResult(
        currentVersion: currentVersion,
        latestVersion: tag,
        notes: (data['body'] as String?)?.trim() ?? '',
        url: url.isEmpty ? releasesPage : url,
        publishedAt: (data['published_at'] as String?)?.trim() ?? '',
      );
    } on DioException catch (error) {
      debugPrint('[更新] 检查失败：$error');
      return UpdateCheckResult(
        currentVersion: currentVersion,
        error: switch (error.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.sendTimeout => '连接超时，稍后再试',
          DioExceptionType.connectionError => '连不上 GitHub，检查一下网络',
          DioExceptionType.badResponse =>
            'GitHub 返回 ${error.response?.statusCode ?? '错误状态'}'
                '${error.response?.statusCode == 403 ? '（请求太频繁，过一会儿再试）' : ''}',
          _ => '检查失败：${error.message ?? error.type.name}',
        },
      );
    } catch (error) {
      debugPrint('[更新] 检查失败：$error');
      return UpdateCheckResult(
        currentVersion: currentVersion,
        error: '检查失败：$error',
      );
    }
  }
}

final updateServiceProvider = Provider<UpdateService>(
  (ref) => UpdateService(),
);
