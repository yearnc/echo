import 'package:echo/domain/models/resident_voice.dart';
import 'package:echo/domain/models/voice_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('语音设置', () {
    test('默认开着，用本机', () {
      const settings = VoiceSettings();
      expect(settings.enabled, isTrue);
      expect(settings.source, VoiceSource.local);
    });

    test('来源读得回来，坏值回落到本机', () {
      expect(VoiceSource.fromKey('cloud'), VoiceSource.cloud);
      expect(VoiceSource.fromKey('local'), VoiceSource.local);
      expect(VoiceSource.fromKey('乱七八糟'), VoiceSource.local);
      expect(VoiceSource.fromKey(null), VoiceSource.local);
    });

    test('copyWith 只改传进来的那一项', () {
      const base = VoiceSettings();
      final changed = base.copyWith(enabled: false);
      expect(changed.enabled, isFalse);
      expect(changed.source, VoiceSource.local);
    });
  });

  group('云端音色', () {
    test('按住民性别挑名字，不把女声配成男声', () {
      // v3.8 起本机只有 5 个声线，性别要靠语气标签来判：
      // 默认落到女声池，标了 male 的走唯一的男声（sid 4）。
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
