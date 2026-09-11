import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/ai_persona.dart';

/// 人格仓库：从 `assets/personas/personas.json` 读内容资产。
///
/// 阶段 A 人格是只读的固定集合；阶段 B 会叠加"用户自定义人格"，
/// 那时这里改成一个 Drift + assets 的合并读取，UI 侧不用动。
class PersonaRepository {
  const PersonaRepository();

  static const String assetPath = 'assets/personas/personas.json';

  Future<List<AiPersona>> loadAll() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = decoded['personas'] as List<dynamic>? ?? const [];
    return list
        .map((item) => AiPersona.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }
}

final personaRepositoryProvider =
    Provider<PersonaRepository>((ref) => const PersonaRepository());

/// 全部人格（首次读取后缓存）。
final personasProvider = FutureProvider<List<AiPersona>>(
  (ref) => ref.watch(personaRepositoryProvider).loadAll(),
);

/// 按 id 取人格，找不到返回 null（UI 侧用兜底名显示，不崩）。
final personaByIdProvider = Provider.family<AiPersona?, String>((ref, id) {
  final personas = ref.watch(personasProvider).value;
  if (personas == null) return null;
  for (final persona in personas) {
    if (persona.id == id) return persona;
  }
  return null;
});

/// 按 id 取展示名，供评论、通知等只需要名字的地方使用。
final personaNameProvider = Provider.family<String, String>((ref, id) {
  return ref.watch(personaByIdProvider(id))?.name ?? '社区住民';
});
