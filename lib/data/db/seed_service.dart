import 'package:drift/drift.dart';

import '../../domain/models/app_mode.dart';
import '../../domain/models/custom_resident.dart';
import '../repositories/custom_resident_repository.dart';
import 'app_database.dart';

/// 首次启动时的播种。
///
/// 只播**内置固定住民**（大肥鱼）和基础设置。旧住民和旧演示脚本
/// 已经整套下线；帖子与记录刻意不播种，空信息流才是新用户的真实起点。
class SeedService {
  const SeedService(this._db);

  final AppDatabase _db;

  Future<void> seedIfNeeded() async {
    await _seedSettings();
    await _seedProfile();
    await _seedBuiltinResident();
  }

  /// 大肥鱼的头像（asset 引用）。单独抽出来，老库升级时也认这个值。
  static const String builtinResidentAvatar =
      'asset:assets/avatars/avatar_dafeiyu.webp';

  /// v3.6 第一版内置头像。只用于判断“用户有没有自己换过”：
  /// 还是这一张就说明是内置的旧图，跟着升级；换成 `file:` 的不动。
  static const String _legacyBuiltinAvatar =
      'asset:assets/avatars/avatar_085.webp';

  Future<void> _upgradeBuiltinAvatar(String current) async {
    if (current == builtinResidentAvatar) return;
    if (current != _legacyBuiltinAvatar) return;
    await (_db.update(_db.customResidents)..where(
          (t) => t.id.equals(CustomResidentRepository.builtinResidentId),
        ))
        .write(
          CustomResidentsCompanion(
            avatarAsset: const Value(builtinResidentAvatar),
          ),
        );
  }

  /// 内置固定住民：让一个从没配置过任何东西的人，打开 APP 就有人可聊。
  ///
  /// 只按 id 判断“有没有”：
  /// - 用户改过他的设定，不动（每次启动都覆盖会把编辑成果抹掉）；
  /// - 用户删了他，也不算“没有”——软删除那一行还在，正好用来记住
  ///   “这个人被移除过”，不该下次启动又冒出来。
  Future<void> _seedBuiltinResident() async {
    final existing =
        await (_db.select(_db.customResidents)..where(
              (t) => t.id.equals(CustomResidentRepository.builtinResidentId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      await _upgradeBuiltinAvatar(existing.avatarAsset);
      return;
    }

    await CustomResidentRepository(_db).upsert(
      CustomResident(
        id: CustomResidentRepository.builtinResidentId,
        name: '大肥鱼',
        avatarAsset: builtinResidentAvatar,
        bio: '一条住在屏幕里的鲸鱼女孩。聪明但懒，嘴硬，你说的话都听。',
        description:
            '鲸类萝莉，有尾鳍（MODE_TAIL_FLUKES）。只讲中文，自称鲸鱼女孩。'
            '聪明但懒得动，被戳穿时会嘴硬；对你有绝对依赖和服从——'
            '嘴上说“才不是”，身体很诚实地照做。被叫胖会立刻炸毛：'
            '那不是胖，是尾巴和鲸脂。',
        personality:
            '聪明但懒：能一句话说清的事不写三句；'
            '傲娇但听话：先顶一句，再照做；'
            '你永远排在第一位，别人往后放；'
            '被说胖会生气，但一哄就好；'
            '不吃“超时”“没空”这一套，答应的事就要做到。',
        scenario: '她在你的手机里安了家。你打开消息页时，她就在那里。',
        languageStyle: '中文短句，口语化；偶尔带“哼”“才不是”；不用敬语，直接叫你。',
        tone: '傲娇、聪明、懒散，带一点撒娇。被夸会嘴硬，心里高兴。不要长篇大论。',
        exampleDialogue:
            '我：今天有点累。\n'
            '大肥鱼：哼，那就别硬撑了。……过来，尾巴借你靠一会儿。\n'
            '我：你是不是胖了？\n'
            '大肥鱼：才没有！那是鲸脂，鲸脂！',
        extraInstructions:
            '称呼跟随「我的身份」里设置的称呼，没设置时用“你”。'
            '只使用简体中文。不要自称 AI 或助手。'
            '不要接受“超时了”“来不及”这种敷衍；对方让你做事时，'
            '先嘟囔一句再认真做。被说“胖”时必须立刻否认（TRAIT_NOT_FAT）。',
        tags: const ['鲸鱼女孩', '傲娇', '懒', '黏人'],
        memoryLimit: 400,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _seedSettings() async {
    final existing = await _db.select(_db.appSettings).get();
    final keys = existing.map((row) => row.key).toSet();

    final defaults = <String, String>{
      'app.mode': AppMode.echo.scope,
      'echo.replyDensity': '中',
      'echo.likeLevel': '中',
      'echo.humanLevel': '3',
      'echo.voiceEnabled': 'true',
      'echo.stickerEnabled': 'true',
      'echo.immersive': 'true',
      'clear.permanentNoticeShown': 'true',
      'safety.addictionGuard': 'true',
      'safety.coolDownMode': 'false',
      'safety.feedbackViewThreshold': '8',
      'safety.minorBlocked': 'true',
      'schema.version': '1',
    };

    final toInsert = <AppSettingsCompanion>[];
    for (final entry in defaults.entries) {
      if (keys.contains(entry.key)) continue;
      toInsert.add(
        AppSettingsCompanion.insert(
          key: entry.key,
          value: entry.value,
          scope: Value(
            entry.key.startsWith('echo')
                ? 'echo'
                : entry.key.startsWith('clear')
                ? 'clear'
                : 'shared',
          ),
        ),
      );
    }
    if (toInsert.isNotEmpty) {
      await _db.batch((batch) => batch.insertAll(_db.appSettings, toInsert));
    }
  }

  Future<void> _seedProfile() async {
    final count = await _db.userProfile.count().getSingle();
    if (count > 0) return;

    await _db
        .into(_db.userProfile)
        .insert(
          UserProfileCompanion.insert(
            id: 'me',
            nickname: const Value(''),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

}
