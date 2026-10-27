import 'package:echo/domain/models/resident_voice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('本机五声线', () {
    test('标签按实际听感标男女（1、3 女；2、4、5 男）', () {
      expect(ResidentVoice.labelForSid(0), '声线 1 · 女');
      expect(ResidentVoice.labelForSid(1), '声线 2 · 男');
      expect(ResidentVoice.labelForSid(2), '声线 3 · 女');
      expect(ResidentVoice.labelForSid(3), '声线 4 · 男');
      expect(ResidentVoice.labelForSid(4), '声线 5 · 男');
    });

    test('按性别分池时不再把男声当女声', () {
      expect(ResidentVoice.isFemale('r', voiceModel: 'local:0'), isTrue);
      expect(ResidentVoice.isFemale('r', voiceModel: 'local:2'), isTrue);
      expect(ResidentVoice.isFemale('r', voiceModel: 'local:1'), isFalse);
      expect(ResidentVoice.isFemale('r', voiceModel: 'local:3'), isFalse);
      expect(ResidentVoice.isFemale('r', voiceModel: 'local:4'), isFalse);
    });
  });

  group('云端音色', () {
    test('按住民性别挑名字，不把女声配成男声', () {
      final female = ResidentVoice.cloudVoiceFor(
        'persona_001',
        voiceModel: 'voice_female_warm',
        baseUrl: 'https://api.openai.com/v1',
      );
      final male = ResidentVoice.cloudVoiceFor(
        'persona_002',
        voiceModel: 'voice_male_calm',
        baseUrl: 'https://api.openai.com/v1',
      );

      expect(['nova', 'shimmer'], contains(female));
      expect(['onyx', 'echo'], contains(male));
    });

    test('硅基流动用 CosyVoice 的音色名', () {
      final voice = ResidentVoice.cloudVoiceFor(
        'persona_001',
        baseUrl: 'https://api.siliconflow.cn/v1',
      );
      expect(['anna', 'bella'], contains(voice));
    });
  });
}
