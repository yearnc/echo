import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 桌宠素材清单的护栏：106 个动作、每个动作 48 帧、语义动作和素材一一对应。
/// 换素材以后这里最先红，比等真机上“某几个动作播不出来”便宜。
void main() {
  late Map<String, dynamic> manifest;
  late List<Map<String, dynamic>> actions;

  setUpAll(() {
    final file = File('assets/pet_frames/manifest.json');
    manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    actions = (manifest['actions'] as List).cast<Map<String, dynamic>>();
  });

  test('动作清单完整', () {
    expect(actions.length, 106);
    final keys = actions.map((a) => a['key'] as String).toSet();
    expect(keys.length, actions.length, reason: '动作 key 不能重复');
    expect(
      actions.every((a) => (a['key'] as String).startsWith('act_')),
      isTrue,
    );
    expect(actions.every((a) => a['frames'] == 48), isTrue);

    final kinds = <String, int>{};
    for (final action in actions) {
      final kind = action['kind'] as String;
      kinds[kind] = (kinds[kind] ?? 0) + 1;
    }
    expect(kinds['idle'], 1);
    expect(kinds['drag'], 1);
    expect(kinds['click'], 5);
    expect(kinds['move'], 3);
    expect(kinds['category'], 80);
  });

  test('每个动作的首尾帧都在', () {
    for (final action in actions) {
      final key = action['key'] as String;
      expect(
        File('assets/pet_frames/${key}_00.webp').existsSync(),
        isTrue,
        reason: '$key 缺第 0 帧',
      );
      expect(
        File('assets/pet_frames/${key}_47.webp').existsSync(),
        isTrue,
        reason: '$key 缺第 47 帧',
      );
    }
  });

  test('住民的语义动作和素材一一对应', () {
    const exposed = {
      'happy',
      'shy',
      'angry',
      'tickle',
      'wave',
      'thinking',
      'busy',
      'cheer',
      'sigh',
      'sleep',
      'yawn',
      'stretch',
      'dance',
      'look',
      'walk',
      'wander',
    };
    final actual = actions
        .map((a) => a['expose'])
        .whereType<String>()
        .toSet();
    expect(actual, exposed);
  });

  test('命中区域只包住本体，不是整帧', () {
    final rect = manifest['hitRect'] as Map<String, dynamic>;
    final width = (rect['right'] as int) - (rect['left'] as int);
    final height = (rect['bottom'] as int) - (rect['top'] as int);
    expect(rect['left'], greaterThanOrEqualTo(0));
    expect(rect['top'], greaterThanOrEqualTo(0));
    expect(rect['right'], lessThanOrEqualTo(320));
    expect(rect['bottom'], lessThanOrEqualTo(180));
    expect(width, lessThanOrEqualTo(160));
    expect(height, lessThanOrEqualTo(170));
  });
}
