/// 一个可下载的本地模型资源（v4.4）。
///
/// 精简版 APK 不内置语音合成 / 识别模型；用户需要哪一项就下哪一项。
/// 资源按版本管理：版本没变就不重复下载，APK 升级也不会把资源带走。
class ModelResource {
  const ModelResource({
    required this.id,
    required this.name,
    required this.description,
    required this.storageDir,
    required this.requiredFiles,
    required this.version,
    required this.bytes,
    this.sha256 = '',
    this.url = '',
    this.mirrorUrl = '',
  });

  /// 稳定的资源标识（asr / tts / zipvoice / asr-stream）。
  final String id;
  final String name;
  final String description;

  /// 释放到 `applicationSupport/speech_models/<storageDir>`。
  final String storageDir;

  /// 少了任何一个文件都算没装好。
  final List<String> requiredFiles;

  final int version;
  final int bytes;
  final String sha256;
  final String url;
  final String mirrorUrl;

  String get sizeLabel {
    if (bytes <= 0) return '大小未知';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    }
    return '${(bytes / 1024 / 1024).round()} MB';
  }

  String urlFor(ResourceSource source) {
    if (source == ResourceSource.mirror) {
      if (mirrorUrl.isNotEmpty) return mirrorUrl;
      if (url.isNotEmpty) return 'https://gh-proxy.com/$url';
      return '';
    }
    return url.isNotEmpty ? url : mirrorUrl.replaceFirst('https://gh-proxy.com/', '');
  }

  ModelResource mergeManifest(Map<String, dynamic> json) {
    int intOf(String key, int fallback) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? fallback;
    }

    String stringOf(String key, String fallback) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value : fallback;
    }

    final required = json['required_files'] ?? json['required'];
    final nextUrl = stringOf('url', url);
    return ModelResource(
      id: id,
      name: stringOf('name', name),
      description: stringOf('description', description),
      storageDir: stringOf('storage_dir', storageDir),
      requiredFiles: required is List
          ? [for (final item in required) if (item is String) item]
          : requiredFiles,
      version: intOf('version', version),
      bytes: intOf('bytes', bytes),
      sha256: stringOf('sha256', sha256),
      url: nextUrl,
      // 远程换了地址却没写镜像时，按新地址重新拼一个，别沿用到旧文件。
      mirrorUrl: stringOf(
        'mirror_url',
        nextUrl == url ? mirrorUrl : 'https://gh-proxy.com/$nextUrl',
      ),
    );
  }
}

/// 下载源。
enum ResourceSource {
  github('github', '官方源'),
  mirror('mirror', '国内镜像');

  const ResourceSource(this.key, this.label);

  final String key;
  final String label;

  static ResourceSource parse(String? raw) =>
      raw == mirror.key ? mirror : github;
}

/// 已安装资源的信息。
class InstalledResource {
  const InstalledResource({
    required this.version,
    required this.bytes,
    required this.installedAt,
  });

  final int version;
  final int bytes;
  final DateTime? installedAt;

  bool get isInstalled => version > 0;
}
