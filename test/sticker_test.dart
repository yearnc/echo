import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/media/media_service.dart';
import 'package:echo/data/repositories/sticker_repository.dart';
import 'package:echo/domain/models/sticker.dart';
import 'package:flutter_test/flutter_test.dart';

/// 素材仓储的测试。导入流程依赖相册选择器（需要真机/模拟环境），
/// 所以这里只覆盖"已经入库之后"的读写与软删除。
void main() {
  late AppDatabase db;
  late StickerRepository stickers;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    stickers = StickerRepository(db, const MediaService());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seed({
    required String id,
    required String name,
    bool isUser = true,
    String path = 'file:/tmp/x.png',
    String category = StickerCategory.customId,
  }) async {
    await db
        .into(db.stickers)
        .insert(
          StickersCompanion.insert(
            id: id,
            name: name,
            category: category,
            path: path,
            isUser: drift.Value(isUser),
            isBuiltin: drift.Value(!isUser),
            createdAt: drift.Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  group('素材读取', () {
    test('用户导入的素材能列出来', () async {
      await seed(id: 's1', name: '摸鱼猫猫');

      final list = await stickers.watchUserStickers().first;

      expect(list, hasLength(1));
      expect(list.single.name, '摸鱼猫猫');
      expect(list.single.isUser, isTrue);
    });

    test('内置素材不进"我的素材"列表', () async {
      await seed(id: 'builtin_1', name: '开心·拍手', isUser: false);
      await seed(id: 'mine_1', name: '我导入的');

      final list = await stickers.watchUserStickers().first;

      expect(list.map((item) => item.name), ['我导入的']);
    });

    test('软删除后不再出现在列表里，也不计数', () async {
      await seed(id: 's1', name: '要删的');
      expect(await stickers.countUserStickers(), 1);

      await stickers.deleteUserSticker('s1');

      expect(await stickers.watchUserStickers().first, isEmpty);
      expect(await stickers.countUserStickers(), 0);
    });

    test('删除不存在的 id 不抛异常', () async {
      await expectLater(
        stickers.deleteUserSticker('not_there'),
        completes,
      );
    });
  });

  group('素材条目', () {
    test('文字兜底只取破折号后面那截', () {
      const item = StickerItem(
        id: 'x',
        name: '安慰·摸摸头',
        category: 'comfort',
        path: 'asset:assets/stickers/comfort/01.png',
      );

      expect(item.fallbackText, '摸摸头');
      expect(item.isAsset, isTrue);
      expect(item.rawPath, 'assets/stickers/comfort/01.png');
    });

    test('没有分隔符时直接用整个名字', () {
      const item = StickerItem(
        id: 'x',
        name: '猫猫',
        category: 'custom',
        path: 'file:/tmp/a.png',
      );

      expect(item.fallbackText, '猫猫');
      expect(item.isAsset, isFalse);
      expect(item.rawPath, '/tmp/a.png');
    });

    test('路径为空时不算有图，UI 会走文字贴片', () {
      const item = StickerItem(
        id: 'x',
        name: '空的',
        category: 'custom',
        path: '',
      );

      expect(item.hasImage, isFalse);
    });
  });
}
