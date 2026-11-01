import 'dart:convert';
import 'dart:io';

import 'package:echo/domain/models/private_message.dart';
import 'package:echo/domain/services/resident_context_window.dart';
import 'package:flutter_test/flutter_test.dart';

PrivateMessage _dm(
  String id, {
  required bool fromMe,
  String content = '一句话',
  String mediaType = 'text',
  String caption = '',
  DateTime? at,
}) {
  return PrivateMessage(
    id: id,
    personaId: 'a',
    fromMe: fromMe,
    content: content,
    mediaType: mediaType,
    caption: caption,
    createdAt: at ?? DateTime(2026, 10, 30, 21, 32),
  );
}

void main() {
  test('窗口半小时滑动续期', () {
    final t0 = DateTime(2026, 10, 30, 11, 30);
    final window = ResidentContextWindow(
      residentId: 'a',
      promptHash: 'h',
      messages: [],
      syncedThroughMs: 0,
      dmIds: {},
      now: t0,
    );

    expect(window.expired(t0.add(const Duration(minutes: 29))), isFalse);
    expect(window.expired(t0.add(const Duration(minutes: 30))), isTrue);

    final t1 = t0.add(const Duration(minutes: 25));
    window.touch(t1);
    expect(window.expired(t1.add(const Duration(minutes: 29))), isFalse);
    expect(window.expired(t1.add(const Duration(minutes: 30))), isTrue);
  });

  test('新私信只追加，同一 id 不会重复进窗口', () async {
    final window = ResidentContextWindow(
      residentId: 'a',
      promptHash: 'h',
      messages: [],
      syncedThroughMs: 0,
      dmIds: {},
      now: DateTime(2026, 10, 30, 11, 30),
    );

    final mine = _dm('m1', fromMe: true, content: '在吗');
    final theirs = _dm('m2', fromMe: false, content: '在的');

    await window.appendDm(mine);
    await window.appendDm(theirs);
    await window.appendDm(mine);

    expect(window.messages.length, 2);
    expect(window.messages[0]['role'], 'user');
    expect(window.messages[0]['content'], contains('对方：在吗'));
    expect(window.messages[1]['role'], 'assistant');
    expect(window.messages[1]['content'], contains('在的'));
    expect(window.messages[1]['content'], isNot(contains('你：')));
    expect(window.syncedThroughMs, theirs.createdAt.millisecondsSinceEpoch);
  });

  test('能看图时图片私信以原图内容块进窗口，文字模型只读描述', () async {
    final dir = await Directory.systemTemp.createTemp('echo_img_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/dot.png');
    // 1×1 透明 PNG
    await file.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4'
        'z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
      ),
    );
    final image = _dm(
      'img',
      fromMe: true,
      content: 'file:${file.path}',
      mediaType: 'image',
      caption: '桌上的咖啡',
    );

    final vision = ResidentContextWindow(
      residentId: 'a',
      promptHash: 'h',
      messages: [],
      syncedThroughMs: 0,
      dmIds: {},
      includeImages: true,
      now: DateTime(2026, 10, 30, 11, 30),
    );
    await vision.appendDm(image);
    final content = vision.messages.single['content'];
    expect(content, isA<List<dynamic>>());
    expect((content as List).last['type'], 'image_url');
    expect(
      (content.first as Map)['text'],
      isNot(contains('桌上的咖啡')),
      reason: '有原图时不再把描述当成正文',
    );

    final textOnly = ResidentContextWindow(
      residentId: 'a',
      promptHash: 'h',
      messages: [],
      syncedThroughMs: 0,
      dmIds: {},
      includeImages: false,
      now: DateTime(2026, 10, 30, 11, 30),
    );
    await textOnly.appendDm(image);
    expect(textOnly.messages.single['content'], contains('桌上的咖啡'));
  });

  test('私信行带完整时间，媒体类型不会被吞', () {
    final line = ResidentContextWindow.dmLine(
      _dm('m1', fromMe: true, content: '猫猫无语', at: DateTime(2026, 10, 30, 21, 32)),
    );
    expect(line, startsWith('[2026年10月30日 周五 晚上 21:32] 对方：'));
  });
}
