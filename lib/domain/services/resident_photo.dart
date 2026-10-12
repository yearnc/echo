import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/media/media_service.dart';
import '../../data/repositories/post_repository.dart';
import '../models/ai_persona.dart';
import '../models/model_config.dart';
import '../models/resident_post.dart';
import 'model_content_generator.dart';
import 'model_gateway.dart';

/// 住民发图文帖的规矩（B3.5）。
///
/// 分工跟签名一样：这里管"这次该不该拍、拍的是哪儿"，成不成图是文生图
/// 那条通道的事。所以它是纯逻辑，能单独测。
class ResidentPhoto {
  /// 明确不值得掏手机的地方：家是躺着的地方、工位是干活的地方。
  ///
  /// 用精确匹配而不是包含——`家门` 是另一回事（下楼取外卖、等人、傍晚的灯），
  /// 不该被 `家` 这个字一起扫掉。
  static const Set<String> notWorthShooting = {'家', '床上', '被窝里', '沙发', '工位', '会议室'};

  /// 作息对不上的时候，按圈层给一个画面。
  ///
  /// 没有作息不等于没什么可拍的——住民照样在过日子，只是没登记几点在哪。
  /// 圈层给了最低限度的一点方向感，省得所有图都长成同一个样子。
  static const Map<String, String> circleScenes = {
    '日常': '窗外的街道',
    '吐槽': '队伍前面的背影',
    '职场': '工位旁边那扇窗',
    '深夜': '夜里还亮着的那扇窗',
    '树洞': '夜里的窗台',
    '运动': '跑道和跑道边的树',
    '摄影': '傍晚的天空',
    '美食': '刚做好的一顿饭',
    '读书': '摊开的书页',
    '音乐': '绕在桌上的耳机线',
    '宠物': '趴在窗台上的猫',
    '出行': '路上看到的一段风景',
  };

  /// 两次发图之间至少隔这么久。
  ///
  /// 图比文字贵一个量级、也慢一个量级。一天下来 1—2 张正好——
  /// 信息流里全是配图，那是相册，不是社区。
  static const Duration cooldown = Duration(hours: 8);

  /// 冷却过得去的时候，仍然只有这个概率真的掏手机。
  static const double chance = 0.35;

  /// 一次 tick 最多几张（所以 [pick] 只挑一个）。
  static const int maxPerTick = 1;

  /// 这个点他有没有值得拍的东西。
  static bool isWorthShooting(AiPersona persona, DateTime at) {
    final place = persona.routineAt(at.hour)?.place.trim() ?? '';
    if (place.isEmpty) return true;
    return !notWorthShooting.contains(place);
  }

  /// 这张照片会拍到哪里。
  static String sceneFor(AiPersona persona, DateTime at) {
    final place = persona.routineAt(at.hour)?.place.trim() ?? '';
    if (place.isNotEmpty) return place;
    return circleScenes[persona.circle] ?? '生活里的一个角落';
  }

  /// 挑这次配图的那条动态。返回 null 就是这次一张都不发。
  ///
  /// [lastAt] 是上一次发图的时刻（全局一个水位：图上一次出现在社区里是什么时候）。
  static ResidentMoment? pick({
    required List<ResidentMoment> moments,
    required DateTime at,
    required DateTime? lastAt,
    Random? random,
    double chance = ResidentPhoto.chance,
  }) {
    if (lastAt != null && at.difference(lastAt) < cooldown) return null;

    final candidates = moments
        .where((moment) => isWorthShooting(moment.persona, moment.at))
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    final rng = random ?? Random();
    if (rng.nextDouble() >= chance) return null;
    return candidates[rng.nextInt(candidates.length)];
  }

  /// 出图用的提示词。
  ///
  /// 这一段真正要压住的是"太好看"：构图讲究、光影完美的图一眼就是生成的，
  /// 而真人随手拍的是歪的、有点糊、带噪点的。所以除了交代场景，
  /// 还得**主动要那些缺点**——不这么写，模型默认就往壁纸那个方向去。
  static String promptFor({required AiPersona persona, required DateTime at}) {
    final scene = sceneFor(persona, at);
    final activity = persona.routineAt(at.hour)?.activity ?? '';

    final buffer = StringBuffer()
      ..writeln('一张用手机随手拍下的日常照片，画面是「$scene」的场景。')
      ..writeln('拍摄时间：${ModelContentGenerator.momentLabel(at)}。');
    if (activity.isNotEmpty) {
      buffer.writeln('拍的时候他正在$activity，照片是顺手按下的那一张，不是特地摆拍的。');
    }

    buffer
      ..writeln('要的是这种质感：')
      ..writeln('- 手机摄影：轻微模糊、自然噪点、光线不均匀')
      ..writeln('- 构图随意，主体不必居中，可以有一点点歪')
      ..writeln('- 真实、日常、有点旧，像手机相册里翻出来的')
      ..writeln()
      ..writeln('不要：影棚布光、完美构图、滤镜感、人像特写、插画或 3D 渲染的味道，')
      ..writeln('画面里不要出现任何文字、水印或 logo。');

    return buffer.toString();
  }
}

/// 住民自己发图文帖（B3.5）。
///
/// 图是**后补**的，不跟着发帖一起等：出图要几十秒，而发帖那条路在冷启动里
/// 跑着，让它去等一张图，用户开机就得先看几十秒空白。所以顺序反过来——
/// 文字先发出去，图生成好了再挂到那条动态上；生成失败就停在纯文字。
class ResidentPhotoService {
  ResidentPhotoService({
    required this.db,
    required this.posts,
    required this.media,
    required this.gateway,
    Random? random,
  }) : _random = random ?? Random();

  final AppDatabase db;
  final PostRepository posts;
  final MediaService media;
  final ModelGateway gateway;

  final Random _random;

  /// 上一次发图的时刻（全局一个）。
  static const String lastAtKey = 'resident.photo.lastAt';

  /// 给这次刚发出去的某条动态配一张图。返回配好的图片引用，没配成就是 null。
  ///
  /// [postIds] 是这次写进库的"住民 → 帖子"对照；[moments] 是这批动态
  /// 各自的时刻（图要在对的时刻拍，不是"现在"）。
  Future<String?> attach({
    required Map<String, String> postIds,
    required List<ResidentMoment> moments,
    required DateTime at,
  }) async {
    // 没配文生图就只发文字。这不是错误路径，是另一种正常走法——
    // 跟内容生成那边"没配模型就用预置台词"一个道理。
    //
    // 而"去查配置"这件事本身失败（配置表读不了、钥匙串读不出来）**不在这里
    // 兜**：那种情况下用户明明配了却永远只发文字，只留一行日志，等于把真问题
    // 伪装成"他没配"。让它抛出去，由调用方那条兜底的路去说清楚。
    final config = await gateway.activeConfig(kind: ModelKind.image);
    if (config == null) return null;

    final picked = ResidentPhoto.pick(
      moments: moments,
      at: at,
      lastAt: await _lastAt(),
      random: _random,
    );
    if (picked == null) return null;

    final postId = postIds[picked.persona.id];
    if (postId == null) return null;

    try {
      final bytes = await gateway.generateImage(
        config: config,
        prompt: ResidentPhoto.promptFor(persona: picked.persona, at: picked.at),
      );
      final ref = await media.saveBytes(bytes);
      final attached = await posts.attachImages(postId, [ref]);
      if (attached == 0) {
        // 帖子不在了（极少见：刚写进去的那条）。图已经落盘，得收回，
        // 不然就留下一个谁也不引用的文件，而它永远飘在用户的存储里。
        await media.deleteByRef(ref);
        return null;
      }
      await _saveLastAt(at);
      return ref;
    } catch (error) {
      // 不成不留痕：那条动态已经发出去了，就当这次是纯文字。
      // 水位也不记——没成的事不该占掉下一次的机会。
      debugPrint('[住民图文] 这次的图没挂上，这条就发纯文字：$error');
      return null;
    }
  }

  Future<DateTime?> _lastAt() async {
    final query = db.select(db.appSettings)
      ..where((t) => t.key.equals(lastAtKey));
    final row = await query.getSingleOrNull();
    final raw = int.tryParse(row?.value ?? '');
    return raw == null ? null : DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> _saveLastAt(DateTime at) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: lastAtKey,
            value: '${at.millisecondsSinceEpoch}',
            scope: const Value('echo'),
          ),
        );
  }
}

final residentPhotoServiceProvider = Provider<ResidentPhotoService>(
  (ref) => ResidentPhotoService(
    db: ref.watch(databaseProvider),
    posts: ref.watch(postRepositoryProvider),
    media: ref.watch(mediaServiceProvider),
    gateway: ref.watch(modelGatewayProvider),
  ),
);
