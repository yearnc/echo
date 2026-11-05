import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/knowledge_repository.dart';
import 'package:echo/domain/models/knowledge.dart';
import 'package:echo/domain/services/knowledge_service.dart';
import 'package:echo/domain/services/post_voice_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// 知识库的归属与注入（v4.11）。
///
/// 这里不测模型说什么，只测"谁能看到哪本、看到的是不是稳定的那一段"：
/// 权限和缓存一旦错了，提示词写得再好都是白搭。
void main() {
  late AppDatabase db;
  late KnowledgeRepository repository;
  late KnowledgeService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = KnowledgeRepository(db);
    service = KnowledgeService(repository);
  });

  tearDown(() async {
    await db.close();
  });

  KnowledgeEntry entry({
    required String baseId,
    String title = '梗',
    String summary = '一句话',
    int expiresAt = 0,
  }) => KnowledgeEntry(
    id: '',
    baseId: baseId,
    title: title,
    summary: summary,
    content: '来源：某处；用处：接话',
    examples: const ['例一', '例二'],
    expiresAt: expiresAt,
  );

  test('内置热门梗库创建时是空的，且给全体网民和全体住民看', () async {
    final base = await repository.ensureTrendBase();
    expect(base.builtin, isTrue);
    expect(base.autoUpdate, isTrue);
    expect(await repository.listEntries(base.id), isEmpty);

    final targets = await repository.listTargets(base.id);
    expect(
      targets.map((item) => item.kind),
      containsAll([
        KnowledgeTargetKind.transientAll,
        KnowledgeTargetKind.residentAll,
      ]),
    );
  });

  test('独立库只服务它点名的人', () async {
    final transient = await repository.createBase(
      name: '玩梗的网民',
      scope: KnowledgeScope.independent,
      ownerKind: KnowledgeOwnerKind.transient,
    );
    final owned = await repository.createBase(
      name: '小林的知识',
      scope: KnowledgeScope.independent,
      ownerKind: KnowledgeOwnerKind.resident,
      ownerResidentId: 'r1',
    );

    final transientIds = (await repository.transientBases()).map((b) => b.id);
    expect(transientIds, contains(transient));
    expect(transientIds, isNot(contains(owned)));

    final r1 = (await repository.residentBases('r1')).map((b) => b.id);
    expect(r1, contains(owned));
    expect(r1, isNot(contains(transient)));

    final r2 = (await repository.residentBases('r2')).map((b) => b.id);
    expect(r2, isNot(contains(owned)));
  });

  test('共享库按服务对象分发', () async {
    final shared = await repository.createBase(
      name: '公开资料',
      scope: KnowledgeScope.shared,
    );
    await repository.setTargets(shared, [
      KnowledgeTarget(
        baseId: shared,
        kind: KnowledgeTargetKind.resident,
        targetId: 'r1',
      ),
    ]);

    expect(
      (await repository.transientBases()).map((b) => b.id),
      isNot(contains(shared)),
    );
    expect(
      (await repository.residentBases('r1')).map((b) => b.id),
      contains(shared),
    );
    expect(
      (await repository.residentBases('r2')).map((b) => b.id),
      isNot(contains(shared)),
    );
  });

  test('过期条目不注入，但还留在库里', () async {
    final baseId = await repository.createBase(
      name: '会过期的梗',
      scope: KnowledgeScope.independent,
    );
    await repository.upsertEntry(entry(baseId: baseId, title: '新鲜梗'));
    await repository.upsertEntry(
      entry(
        baseId: baseId,
        title: '过气梗',
        expiresAt: DateTime.now()
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch,
      ),
    );

    final fresh = await repository.findBase(baseId);
    final block = await service.transientBlock(fresh!);
    expect(block, contains('新鲜梗'));
    expect(block, isNot(contains('过气梗')));
    expect(
      (await repository.listEntries(baseId, includeExpired: true)).length,
      2,
    );
  });

  test('同一版本重复取块是同一段；条目变了才重建', () async {
    final baseId = await repository.createBase(
      name: '稳定前缀',
      scope: KnowledgeScope.independent,
    );
    await repository.upsertEntry(entry(baseId: baseId, title: '第一条'));

    var current = await repository.findBase(baseId);
    final first = await service.transientBlock(current!);
    final second = await service.transientBlock(current);
    expect(second, first);

    await repository.upsertEntry(entry(baseId: baseId, title: '第二条'));
    current = await repository.findBase(baseId);
    final third = await service.transientBlock(current!);
    expect(third, contains('第二条'));
    expect(third, isNot(first));
  });

  test('知识库放在 system 前缀里，不跟着帖子走', () {
    const knowledge = '【册子】\n- 梗：接一句就够';
    final withKnowledge = ModelPostVoiceGenerator.systemPrompt(
      allowLurk: true,
      knowledge: knowledge,
    );
    expect(withKnowledge, contains(knowledge));

    // 同一本册子换一条帖子，system 逐字节相同：缓存靠的就是这一点。
    final again = ModelPostVoiceGenerator.systemPrompt(
      allowLurk: true,
      knowledge: knowledge,
    );
    expect(again, withKnowledge);
  });

  test('住民只能写到看得见的库', () async {
    final visible = await repository.createBase(
      name: '能看见的',
      scope: KnowledgeScope.independent,
      ownerKind: KnowledgeOwnerKind.resident,
      ownerResidentId: 'r1',
    );
    final hidden = await repository.createBase(
      name: '看不见的',
      scope: KnowledgeScope.independent,
      ownerKind: KnowledgeOwnerKind.resident,
      ownerResidentId: 'r2',
    );

    final saved = await service.write(
      residentId: 'r1',
      baseId: visible,
      title: '新梗',
      summary: '一句话',
    );
    expect(saved.baseId, visible);
    expect((await repository.listEntries(visible)).length, 1);

    expect(
      () => service.write(
        residentId: 'r1',
        baseId: hidden,
        title: '偷写',
      ),
      throwsArgumentError,
    );
  });

  test('检索只找能看到的库', () async {
    final visible = await repository.createBase(
      name: '能看见的',
      scope: KnowledgeScope.independent,
      ownerKind: KnowledgeOwnerKind.resident,
      ownerResidentId: 'r1',
    );
    final hidden = await repository.createBase(
      name: '看不见的',
      scope: KnowledgeScope.independent,
      ownerKind: KnowledgeOwnerKind.resident,
      ownerResidentId: 'r2',
    );
    await repository.upsertEntry(entry(baseId: visible, title: '苹果梗'));
    await repository.upsertEntry(entry(baseId: hidden, title: '苹果旧梗'));

    final results = await service.search(residentId: 'r1', query: '苹果');
    expect(results.map((item) => item.title), contains('苹果梗'));
    expect(results.map((item) => item.title), isNot(contains('苹果旧梗')));
  });
}
