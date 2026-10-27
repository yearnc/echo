import 'dart:convert';

import 'package:echo/domain/services/chat_transcript_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final importer = ChatTranscriptImporter();

  group('DeepSeek 分享 JSON', () {
    final sample = jsonEncode({
      'code': 0,
      'data': {
        'biz_code': 0,
        'biz_data': {
          'title': 'Shared Conversation',
          'messages': [
            {
              'message_id': 1,
              'role': 'USER',
              'fragments': [
                {'id': 1, 'type': 'REQUEST', 'content': '你好'},
              ],
            },
            {
              'message_id': 2,
              'role': 'ASSISTANT',
              'fragments': [
                {'id': 2, 'type': 'THINK', 'content': '用户只是打了个招呼……'},
                {
                  'id': 3,
                  'type': 'RESPONSE',
                  'content': '你好！很高兴见到你。有什么我可以为你做的吗？',
                },
              ],
            },
            {
              'message_id': 3,
              'role': 'USER',
              'fragments': [
                {'id': 4, 'type': 'REQUEST', 'content': '没事'},
              ],
            },
          ],
        },
      },
    });

    test('只取 REQUEST / RESPONSE，思考过程不进记忆', () {
      final turns = importer.turnsFromShareJson(sample);
      expect(turns.length, 3);
      expect(turns[0].fromUser, isTrue);
      expect(turns[0].text, '你好');
      expect(turns[1].fromUser, isFalse);
      expect(turns[1].text, contains('很高兴见到你'));
      expect(turns[1].text, isNot(contains('用户只是打了个招呼')));
      expect(turns[2].fromUser, isTrue);
      expect(turns[2].text, '没事');
    });

    test('不是分享 JSON 时返回空，交给 HTML/粘贴兜底', () {
      expect(importer.turnsFromShareJson('{"hello":1}'), isEmpty);
      expect(importer.turnsFromShareJson('<html>'), isEmpty);
    });
  });

  group('粘贴文本', () {
    test('认出「我：/ AI：」并合并连续行', () {
      final turns = importer.fromPlainText('''
我：你好
AI：你好！很高兴见到你。
有什么我可以帮你的？
我：没事
AI：好的，那就不打扰啦～
''');
      expect(turns.length, 4);
      expect(turns[0].fromUser, isTrue);
      expect(turns[2].fromUser, isTrue);
      expect(turns[1].text, contains('有什么我可以帮你的'));
    });

    test('没有角色前缀时明确报错', () {
      expect(
        () => importer.fromPlainText('随便写的一段话\n没有任何格式'),
        throwsA(isA<ChatImportException>()),
      );
    });
  });
}
