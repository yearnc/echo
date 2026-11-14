import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/model_config_repository.dart';
import 'model_call_common.dart';

/// 文档 / 图片识字（v4.12）。
///
/// 走 DeepSeek 的 `POST /v1/tools/ocr`：multipart 上传一个文件，
/// 返回按页的文本。用于没有配视觉模型时，把图片里的字读出来。
///
/// **会把这一个文件发给 DeepSeek**，所以必须由用户自己打开开关；
/// 默认关闭，调用方先问 [enabled]。
class OcrService {
  OcrService({
    this.configs,
    this.db,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  final ModelConfigRepository? configs;
  final AppDatabase? db;
  final Dio _dio;

  static const String enabledKey = 'ocr.cloud.enabled';

  /// 文档本身最大 100 MiB；超过就不上传，免得白等 180 秒。
  static const int maxBytes = 100 * 1024 * 1024;

  Future<bool> enabled() async {
    final database = db;
    if (database == null) return false;
    final row =
        await (database.select(database.appSettings)
              ..where((t) => t.key.equals(enabledKey)))
            .getSingleOrNull();
    return row?.value == 'true';
  }

  Future<void> setEnabled(bool value) async {
    final database = db;
    if (database == null) return;
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: enabledKey,
            value: value ? 'true' : 'false',
          ),
        );
  }

  /// 识别一个本地文件，返回合并后的文本。
  ///
  /// [purpose] 用 `text_recognition`（纯文字）就够了；
  /// 需要带坐标的富版面时再传 `rich_layout_recognition`。
  Future<OcrResult> recognize(
    String filePath, {
    String purpose = 'text_recognition',
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw StateError('找不到这个文件');
    }
    final size = await file.length();
    if (size > maxBytes) {
      throw StateError('文件超过 100MB，OCR 不收；先压缩或拆页');
    }
    final repo = configs;
    if (repo == null) {
      throw StateError('OCR 要用 DeepSeek 的 Key，但模型配置里没有可用的 DeepSeek 配置');
    }
    final config = await repo.firstUsableDeepSeek();
    if (config == null) {
      throw StateError('OCR 要用 DeepSeek 的 Key，但模型配置里没有可用的 DeepSeek 配置');
    }
    final key = (await repo.readKey(config.id))?.trim() ?? '';
    if (key.isEmpty) throw StateError('DeepSeek 的密钥是空的');

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        deepSeekToolsEndpoint(config.baseUrl, 'ocr'),
        data: FormData.fromMap({
          'file': await MultipartFile.fromFile(
            filePath,
            filename: _basename(filePath),
          ),
          'purpose': purpose,
        }),
        options: Options(
          headers: {'Authorization': 'Bearer $key'},
          // 官方总时限 180 秒，这里给足；不要因为网络慢就提前放弃。
          sendTimeout: const Duration(seconds: 180),
          receiveTimeout: const Duration(seconds: 180),
        ),
      );

      final payload = response.data ?? const <String, dynamic>{};
      final pages = payload['pages'];
      final texts = <String>[];
      if (pages is List) {
        for (final page in pages) {
          if (page is! Map) continue;
          final text = page['text'];
          if (text is String && text.trim().isNotEmpty) texts.add(text.trim());
        }
      }
      final text = texts.join('\n\n').trim();
      if (text.isEmpty) {
        throw StateError('这个文件里没读到文字');
      }
      final count = payload['page_count'];
      return OcrResult(
        text: text,
        pageCount: count is num
            ? count.toInt()
            : (pages is List ? pages.length : texts.length),
      );
    } on DioException catch (error) {
      throw StateError(_describe(error, config.baseUrl));
    }
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index >= 0 ? normalized.substring(index + 1) : normalized;
  }

  static String _describe(DioException error, String baseUrl) {
    final status = error.response?.statusCode;
    return switch (status) {
      400 => '文件或用途不对，OCR 处理不了（检查格式、密码或是否损坏）',
      402 => 'DeepSeek 余额不足，OCR 跑不了',
      408 => '文件上传太慢，OCR 超时了',
      413 => '文件超过 100MB',
      429 => 'OCR 并发数超限，稍后再试',
      503 => 'OCR 服务繁忙，稍后再试',
      504 => 'OCR 总时限到了，换个小一点的文件',
      _ => describeModelError(error, baseUrl: baseUrl),
    };
  }
}

class OcrResult {
  const OcrResult({required this.text, required this.pageCount});

  final String text;
  final int pageCount;
}

final ocrServiceProvider = Provider<OcrService>(
  (ref) => OcrService(
    db: ref.watch(databaseProvider),
    configs: ref.watch(modelConfigRepositoryProvider),
  ),
);
