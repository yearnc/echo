import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 把本机的 `file:` / `asset:` 图片变成 OpenAI 兼容的 `image_url` 内容块。
///
/// 两个原则：
/// 1. **同一张图每次编码出完全相同的字节**——前缀缓存按字节比对，
///    同一张图重新压一遍就可能换一个哈希，缓存立刻失效。
/// 2. 尺寸有上限。Claude Code 用 2000px；私信和帖子解析这里取 1280px，
///    token 更省，也不会因为超大图触发 400。
class ImagePayload {
  const ImagePayload._();

  static const int maxSide = 1280;

  /// 单张图的 base64 上限（OpenAI 兼容端常见是 5MB，留一点余量）。
  static const int maxBase64Bytes = 4 * 1024 * 1024;

  /// 同一张图的编码结果。key 带上 mtime/length，文件被换掉会自动失效。
  static final Map<String, ({String mime, String base64})> _cache = {};

  /// 返回可直接放进 messages 的 image 内容块；读不了就返回 null。
  static Future<Map<String, dynamic>?> partFromRef(String ref) async {
    final ({String mime, String base64})? encoded;
    try {
      encoded = await _encode(ref);
    } catch (error) {
      debugPrint('[图片] 这张读不出来：$error');
      return null;
    }
    if (encoded == null) return null;
    return {
      'type': 'image_url',
      'image_url': {'url': 'data:${encoded.mime};base64,${encoded.base64}'},
    };
  }

  /// 批量：最多 [limit] 张，读不到的跳过。
  static Future<List<Map<String, dynamic>>> partsFromRefs(
    Iterable<String> refs, {
    int limit = 4,
  }) async {
    final parts = <Map<String, dynamic>>[];
    for (final ref in refs.take(limit)) {
      final part = await partFromRef(ref);
      if (part != null) parts.add(part);
    }
    return parts;
  }

  static Future<({String mime, String base64})?> _encode(String ref) async {
    final key = await _cacheKey(ref);
    if (key == null) return null;
    final cached = _cache[key];
    if (cached != null) return cached;

    final bytes = await _read(ref);
    if (bytes == null || bytes.isEmpty) return null;

    var encoded = await _encodeAt(bytes, maxSide);
    // PNG 在某些照片上会偏大；逐级缩小直到塞进限制。
    for (final side in const [960, 720, 512]) {
      if (encoded.base64.length <= maxBase64Bytes) break;
      encoded = await _encodeAt(bytes, side);
    }
    _cache[key] = encoded;
    return encoded;
  }

  static Future<String?> _cacheKey(String ref) async {
    if (ref.startsWith('file:')) {
      final file = File(ref.substring('file:'.length));
      if (!file.existsSync()) return null;
      final stat = await file.stat();
      return '$ref|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
    }
    if (ref.startsWith('asset:')) return ref;
    return null;
  }

  static Future<Uint8List?> _read(String ref) async {
    try {
      if (ref.startsWith('file:')) {
        final file = File(ref.substring('file:'.length));
        if (!file.existsSync()) return null;
        return await file.readAsBytes();
      }
      if (ref.startsWith('asset:')) {
        final data = await rootBundle.load(ref.substring('asset:'.length));
        return data.buffer.asUint8List();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Future<({String mime, String base64})> _encodeAt(
    Uint8List bytes,
    int side,
  ) async {
    final mime = detectMime(bytes);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final width = frame.image.width;
    final height = frame.image.height;

    if (width <= side && height <= side && bytes.length < 1.5 * 1024 * 1024) {
      return (mime: mime, base64: base64Encode(bytes));
    }

    final scale = side / (width > height ? width : height);
    final targetWidth = scale < 1 ? (width * scale).round() : width;
    final targetHeight = scale < 1 ? (height * scale).round() : height;

    final resizedCodec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final resizedFrame = await resizedCodec.getNextFrame();
    final data = await resizedFrame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (data == null) {
      return (mime: mime, base64: base64Encode(bytes));
    }
    return (mime: 'image/png', base64: base64Encode(data.buffer.asUint8List()));
  }

  static String detectMime(Uint8List bytes) {
    if (bytes.length > 3 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'image/jpeg';
    }
    if (bytes.length > 11 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/png';
  }
}
