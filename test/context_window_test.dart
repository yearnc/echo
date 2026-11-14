import 'dart:convert';
import 'dart:io';

import 'package:echo/domain/models/private_message.dart';
import 'package:echo/domain/services/resident_context_window.dart';
import 'package:echo/domain/services/resident_tool_session.dart';
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
  test('窗口一个半小时滑动续期', () {
    final t0 = DateTime(2026, 10, 30, 11, 30);
    final window = ResidentContextWindow(
      residentId: 'a',
      promptHash: 'h',
      messages: [],
      syncedThroughMs: 0,
      dmIds: {},
      now: t0,
    );

    expect(window.expired(t0.add(const Duration(minutes: 89))), isFalse);
    expect(window.expired(t0.add(const Duration(minutes: 90))), isTrue);

    final t1 = t0.add(const Duration(minutes: 80));
    window.touch(t1);
    expect(window.expired(t1.add(const Duration(minutes: 89))), isFalse);
    expect(window.expired(t1.add(const Duration(minutes: 90))), isTrue);
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

  test('本轮情境只追加在窗口末尾，缓存前缀不被改写', () {
    final history = [
      {'role': 'system', 'content': '稳定的人设与规则'},
      {'role': 'user', 'content': '[2026年10月30日 周五 晚上 21:32] 对方：在吗'},
    ];
    final prefix = jsonEncode(history);

    final a = ResidentToolSession.historyWithTail(
      history,
      '现在：2026年10月30日 22:00\n你已经定了这些还没响的闹钟：\n- 明天 08:00',
    );
    final b = ResidentToolSession.historyWithTail(
      history,
      '现在：2026年10月31日 09:00\n对方的私信等你回应',
    );

    // 每轮变化的内容只在最后一条；前 history.length 条必须逐字相同，
    // 否则服务端的上下文缓存整段都命不中。
    expect(jsonEncode(a.take(history.length).toList()), prefix);
    expect(jsonEncode(b.take(history.length).toList()), prefix);
    expect(a.length, history.length + 1);
    expect(b.last['role'], 'user');
  });

  test('私信行带完整时间，媒体类型不会被吞', () {
    final line = ResidentContextWindow.dmLine(
      _dm('m1', fromMe: true, content: '猫猫无语', at: DateTime(2026, 10, 30, 21, 32)),
    );
    expect(line, startsWith('[2026年10月30日 周五 晚上 21:32] 对方：'));
  });
}
