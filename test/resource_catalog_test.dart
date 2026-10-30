import 'package:echo/domain/models/model_resource.dart';
import 'package:echo/domain/services/resource_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('内置四套模型都有下载地址和镜像地址', () {
    final list = ResourceCatalog.builtIn;
    expect(list.map((item) => item.id), containsAll([
      'asr',
      'tts',
      'zipvoice',
      'asr-stream',
    ]));
    for (final resource in list) {
      expect(resource.url, isNotEmpty, reason: resource.id);
      expect(resource.mirrorUrl, startsWith('https://gh-proxy.com/'));
      expect(resource.requiredFiles, isNotEmpty, reason: resource.id);
      expect(resource.storageDir, isNotEmpty, reason: resource.id);
    }
  });

  test('切换下载源只换入口，不改资源 id', () {
    final tts = ResourceCatalog.builtIn.firstWhere((item) => item.id == 'tts');
    expect(tts.urlFor(ResourceSource.github), tts.url);
    expect(tts.urlFor(ResourceSource.mirror), tts.mirrorUrl);
    expect(ResourceSource.parse('mirror'), ResourceSource.mirror);
    expect(ResourceSource.parse('unknown'), ResourceSource.github);
  });

  test('远程清单能覆盖版本、体积和校验值', () {
    final tts = ResourceCatalog.builtIn.firstWhere((item) => item.id == 'tts');
    final merged = tts.mergeManifest({
      'version': 2,
      'bytes': 123456,
      'sha256': 'abcd',
      'required_files': ['model.onnx', 'tokens.txt'],
      'url': 'https://example.com/tts-v2.zip',
    });
    expect(merged.version, 2);
    expect(merged.bytes, 123456);
    expect(merged.sha256, 'abcd');
    expect(merged.requiredFiles, ['model.onnx', 'tokens.txt']);
    expect(merged.url, 'https://example.com/tts-v2.zip');
    // 没写的字段保留内置值；地址变了而镜像没写时，按新地址重新拼。
    expect(merged.name, tts.name);
    expect(
      merged.mirrorUrl,
      'https://gh-proxy.com/https://example.com/tts-v2.zip',
    );
  });

  test('体积按 MB / GB 显示', () {
    const resource = ModelResource(
      id: 'x',
      name: 'x',
      description: '',
      storageDir: 'x',
      requiredFiles: [],
      version: 1,
      bytes: 150 * 1024 * 1024,
    );
    expect(resource.sizeLabel, '150 MB');
  });
}
