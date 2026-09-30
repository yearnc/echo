import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/ai_persona.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

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

final personaRepositoryProvider = Provider<PersonaRepository>(
  (ref) => const PersonaRepository(),
);

/// 住民**当前的样子**：出厂值叠上他自己改过的那些（B3.5）。
///
/// 这两个来源分工很清楚：`assets/personas/personas.json` 是出厂值，回答
/// "他本来是谁"；`ai_personas` 表是当前值，回答"他现在是什么样"。住民换过
/// 签名之后，读的一律走这里，页面才跟着变。
///
/// 为什么出厂值不跟着改：新装用户永远该有一份完整的初始社区；而且住民把自己
/// 改得离出厂设定很远之后，我们还需要一个地方对得上"他本来是那样的"。
class PersonaStateRepository {
  const PersonaStateRepository(this._db, this._assets);

  final AppDatabase _db;
  final PersonaRepository _assets;

  Future<List<AiPersona>> loadAll() async {
    final factory = await _assets.loadAll();
    final rows = await _db.select(_db.aiPersonas).get();
    if (rows.isEmpty) return factory;

    final byId = {for (final row in rows) row.id: row};
    return [for (final persona in factory) _overlay(persona, byId[persona.id])];
  }

  /// 表里的签名盖在出厂签名上。
  ///
  /// 眼下**只覆盖签名**，因为住民能改的只有它。名字和头像要是也以表为准，
  /// 会变成另一种坑：播种只补不覆盖，老库里那份是当初写进去的旧值，之后
  /// assets 里给某个住民改了名，新装用户看得见、老用户永远看不见。
  /// 等住民真能换头像、改昵称了（那要配一个"这一项被他改过没有"的标记，
  /// 不然分不清"改过"和"还没登记"），再把它加进来。
  ///
  /// 空签名退回出厂值：住民把签名清成空串是合法的（"什么都不想说"），
  /// 但没改过的住民在表里也是空，两者分不开。眼下播种会把出厂签名一起
  /// 写进表，两种值天然一致，只有住民真改过才会不一样。
  AiPersona _overlay(AiPersona persona, AiPersonaRow? row) {
    final bio = row?.bio.trim() ?? '';
    if (bio.isEmpty) return persona;
    return persona.copyWith(bio: bio);
  }

  /// 住民换了一句签名。**只写表**——出厂值那一份不动。
  ///
  /// 返回受影响的行数。住民不在表里时是 0，调用方据此**不记冷却水位**——
  /// 白记一笔的话，这个人会莫名其妙地等上一整轮冷却，而且从界面上查不出原因。
  Future<int> updateBio({required String personaId, required String bio}) {
    return (_db.update(_db.aiPersonas)..where((t) => t.id.equals(personaId)))
        .write(AiPersonasCompanion(bio: Value(bio)));
  }
}

final personaStateRepositoryProvider = Provider<PersonaStateRepository>(
  (ref) => PersonaStateRepository(
    ref.watch(databaseProvider),
    ref.watch(personaRepositoryProvider),
  ),
);

/// 全部住民（出厂值 + 各自当前的样子）。
final personasProvider = FutureProvider<List<AiPersona>>(
  (ref) => ref.watch(personaStateRepositoryProvider).loadAll(),
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
