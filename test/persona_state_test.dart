import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/persona_repository.dart';
import 'package:echo/domain/models/ai_persona.dart';
import 'package:flutter_test/flutter_test.dart';

/// 出厂值用桩，不去读 assets——这一层要测的是"表里的值有没有盖上来"。
class _Factory implements PersonaRepository {
  _Factory(this.pool);

  final List<AiPersona> pool;

  @override
  Future<List<AiPersona>> loadAll() async => pool;
}

List<AiPersona> _pool() => const [
  AiPersona(id: 'persona_001', name: '温柔学姐', bio: '出厂签名，愿意听你说完。'),
  AiPersona(id: 'persona_002', name: '老陈的键盘', bio: '出厂签名，嘴硬心软。'),
];

void main() {
  late AppDatabase db;
  late PersonaStateRepository state;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    state = PersonaStateRepository(db, _Factory(_pool()));
  });

  tearDown(() async => db.close());

  Future<void> insertRow(String id, {String bio = ''}) async {
    await db
        .into(db.aiPersonas)
        .insert(
          AiPersonasCompanion.insert(
            id: id,
            name: '名字',
            bio: Value(bio),
          ),
        );
  }

  test('表里没有这个人，就用出厂值', () async {
    final personas = await state.loadAll();

    expect(personas.length, 2);
    expect(personas.first.bio, '出厂签名，愿意听你说完。');
  });

  test('表里的签名盖住出厂签名', () async {
    await insertRow('persona_001', bio: '今天想早点睡。');

    final personas = await state.loadAll();
    final byId = {for (final p in personas) p.id: p};

    expect(byId['persona_001']!.bio, '今天想早点睡。');
    expect(
      byId['persona_002']!.bio,
      '出厂签名，嘴硬心软。',
      reason: '没登过记的人不受影响',
    );
  });

  test('改完之后再读，就是新的那句', () async {
    await insertRow('persona_001', bio: '旧签名');

    await state.updateBio(personaId: 'persona_001', bio: '新签名');

    final personas = await state.loadAll();
    expect(personas.first.bio, '新签名');
  });

  test('名字与头像仍然取出厂值——住民改不到它们', () async {
    // 让它们以表为准会变成另一种坑：播种只补不覆盖，老库里那份是当初写进去的
    // 旧值，之后 assets 里给某个住民改了名，新装用户看得见、老用户永远看不见
    await db
        .into(db.aiPersonas)
        .insert(
          AiPersonasCompanion.insert(
            id: 'persona_002',
            name: '老库里的旧名字',
            avatar: const Value('asset:assets/avatars/x.png'),
          ),
        );

    final personas = await state.loadAll();
    final second = personas.firstWhere((p) => p.id == 'persona_002');

    expect(second.name, '老陈的键盘');
    expect(second.avatar, '');
    expect(second.bio, '出厂签名，嘴硬心软。', reason: '表里签名是空的，退回出厂值');
  });

  test('住民不在表里时，改签名不会假装成功', () async {
    // 报成 0 行，调用方才知道不该给他记冷却水位
    expect(await state.updateBio(personaId: 'persona_404', bio: '新签名'), 0);
  });

  test('表里一个住民都没有时，整份出厂值照常给', () async {
    final personas = await state.loadAll();

    expect(personas.map((p) => p.name), ['温柔学姐', '老陈的键盘']);
  });
}
