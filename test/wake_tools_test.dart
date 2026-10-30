import 'package:echo/domain/models/custom_resident.dart';
import 'package:echo/domain/services/resident_tool_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// 桌宠轮和私信轮是同一个住民，工具不能两套：
/// 私信、语音、表情包在屏幕上也要能伸手。
void main() {
  CustomResident resident({bool voice = true}) => CustomResident(
    id: 'r1',
    name: '大肥鱼',
    voiceEnabled: voice,
    createdAt: DateTime(2026),
    modelConfigId: '',
  );

  test('桌宠轮也能用私信、语音、表情包和待发段', () {
    final names = ResidentToolSession.wakeToolNamesFor(resident());
    expect(names, contains('send_dm'));
    expect(names, contains('send_voice'));
    expect(names, contains('send_sticker'));
    expect(names, contains('cancel_pending_segment'));
    expect(names, contains('rewrite_pending_segment'));
    expect(names, contains('pet_say'));
    expect(names, contains('pet_capture'));
    expect(names, contains('browse_feed'));
  });

  test('住民没开语音时，不把 send_voice 亮出来', () {
    final names = ResidentToolSession.wakeToolNamesFor(resident(voice: false));
    expect(names, isNot(contains('send_voice')));
    expect(names, contains('send_dm'));
  });
}
