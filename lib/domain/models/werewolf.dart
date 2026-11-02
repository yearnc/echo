import 'dart:convert';

import 'game.dart';

/// 狼人杀角色（v50）。
enum WerewolfRole {
  werewolf('狼人', '每晚和狼队友一起刀一个人。你知道其他狼是谁。', evil: true),
  seer('预言家', '每晚查验一名玩家的阵营。', evil: false),
  witch('女巫', '有一瓶解药和一瓶毒药，每夜最多用一瓶。', evil: false),
  hunter('猎人', '被刀或被放逐时，可以开枪带走一名玩家（被毒杀不能开枪）。', evil: false),
  villager('村民', '没有技能，靠发言和投票找出狼人。', evil: false);

  const WerewolfRole(this.label, this.ability, {required this.evil});

  final String label;
  final String ability;
  final bool evil;

  static WerewolfRole fromKey(String raw) {
    for (final role in values) {
      if (role.name == raw) return role;
    }
    return WerewolfRole.villager;
  }
}

enum WerewolfPhase {
  night,
  dayAnnounce,
  sheriffElection,
  speaking,
  voting,
  hunter,
  over,
}

WerewolfPhase werewolfPhaseFromKey(String raw) {
  for (final phase in WerewolfPhase.values) {
    if (phase.name == raw) return phase;
  }
  return WerewolfPhase.night;
}

/// 一局狼人杀的完整状态。
///
/// 玩家自己的角色与存活状态落在 `game_match_players`；这里只放
/// 公共阶段、夜晚行动、发言与投票的暂存，以及给用户的等待标记。
class WerewolfState {
  WerewolfState({
    this.phase = WerewolfPhase.night,
    this.day = 0,
    this.night = 0,
    this.nightStage = 'wolves',
    this.awaiting = '',
    this.nightKill,
    this.saved = false,
    this.poison,
    this.seerTarget,
    this.seerResult,
    this.witchSaveAvailable = true,
    this.witchPoisonAvailable = true,
    this.pendingHunter,
    this.hunterAtNight = false,
    this.winner = '',
    this.lastDeaths = const [],
    this.speeches = const {},
    this.votes = const {},
    this.aiVotes = const {},
    this.log = const [],
    this.privateLog = const {},
    this.endedByPoison = false,
    this.sheriffId,
    this.sheriffStage = 'candidacy',
    this.sheriffElectionDone = false,
    this.candidates = const [],
    this.campaignSpeeches = const {},
    this.sheriffVotes = const {},
    this.sheriffLog = const [],
    this.sheriffSummary = '',
    this.speechOrder = const [],
    this.speechIndex = 0,
    this.wolfDiscussion = const [],
    this.runDecisions = const {},
    this.campaignIndex = 0,
  }) {
    // 默认参数用的是 const 集合；这一局后面要往里加发言、投票和私密信息，
    // 必须换成可变的副本，否则会抛 “Cannot modify unmodifiable map/list”。
    lastDeaths = List<int>.of(lastDeaths);
    speeches = Map<int, String>.of(speeches);
    votes = Map<int, int>.of(votes);
    aiVotes = Map<int, int>.of(aiVotes);
    log = List<String>.of(log);
    privateLog = {
      for (final entry in privateLog.entries)
        entry.key: List<String>.of(entry.value),
    };
    candidates = List<int>.of(candidates);
    campaignSpeeches = Map<int, String>.of(campaignSpeeches);
    sheriffVotes = Map<int, int>.of(sheriffVotes);
    sheriffLog = List<String>.of(sheriffLog);
    speechOrder = List<int>.of(speechOrder);
    wolfDiscussion = List<String>.of(wolfDiscussion);
    runDecisions = Map<int, bool>.of(runDecisions);
  }

  WerewolfPhase phase;
  int day;
  int night;

  /// 夜晚内部阶段：wolves / seer / witch / resolve
  String nightStage;

  /// `user_night` / `user_speech` / `user_vote` / `user_hunter` /
  /// `user_sheriff_run` / `user_sheriff_speech` / `user_sheriff_vote` / 空。
  String awaiting;

  int? nightKill;
  bool saved;
  int? poison;
  int? seerTarget;
  bool? seerResult;
  bool witchSaveAvailable;
  bool witchPoisonAvailable;

  /// 猎人刚死亡、还没开枪时的座位。
  int? pendingHunter;

  /// 猎人是在夜里被刀死的（开枪后要进入白天），还是白天被放逐的。
  bool hunterAtNight;
  String winner;
  List<int> lastDeaths;

  /// 发言：seat -> 内容。
  Map<int, String> speeches;

  /// 已经投出的票：seat -> target，0 表示弃权。
  Map<int, int> votes;

  /// AI / 住民已经投好、等用户一起结算的票。
  Map<int, int> aiVotes;

  /// 所有人可见的日志。
  List<String> log;

  /// 只给某个座位看的日志（狼队友、预言家查验、女巫用药）。
  Map<int, List<String>> privateLog;

  bool endedByPoison;

  /// 警长（GameWeb 逻辑）：1.5 票、最后发言，死亡后警徽自动移交。
  int? sheriffId;

  /// candidacy / campaign / vote / done
  String sheriffStage;
  bool sheriffElectionDone;
  List<int> candidates;
  Map<int, String> campaignSpeeches;
  Map<int, int> sheriffVotes;
  List<String> sheriffLog;
  String sheriffSummary;

  /// 发言顺序：每天蛇形交替，警长最后。
  List<int> speechOrder;
  int speechIndex;

  /// 狼人夜里的讨论（只进狼人私密日志）。
  List<String> wolfDiscussion;

  /// 警长竞选报名决定：seat -> 是否上警。
  Map<int, bool> runDecisions;

  /// 竞选发言进行到第几位候选人。
  int campaignIndex;

  bool get isOver => phase == WerewolfPhase.over;

  bool get awaitingUser => awaiting.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'phase': phase.name,
    'day': day,
    'night': night,
    'night_stage': nightStage,
    'awaiting': awaiting,
    'night_kill': nightKill,
    'saved': saved,
    'poison': poison,
    'seer_target': seerTarget,
    'seer_result': seerResult,
    'witch_save': witchSaveAvailable,
    'witch_poison': witchPoisonAvailable,
    'pending_hunter': pendingHunter,
    'hunter_at_night': hunterAtNight,
    'winner': winner,
    'last_deaths': lastDeaths,
    'speeches': speeches.map((key, value) => MapEntry('$key', value)),
    'votes': votes.map((key, value) => MapEntry('$key', value)),
    'ai_votes': aiVotes.map((key, value) => MapEntry('$key', value)),
    'log': log,
    'private_log': privateLog.map((key, value) => MapEntry('$key', value)),
    'ended_by_poison': endedByPoison,
    'sheriff_id': sheriffId,
    'sheriff_stage': sheriffStage,
    'sheriff_election_done': sheriffElectionDone,
    'candidates': candidates,
    'campaign_speeches': campaignSpeeches.map(
      (key, value) => MapEntry('$key', value),
    ),
    'sheriff_votes': sheriffVotes.map((key, value) => MapEntry('$key', value)),
    'sheriff_log': sheriffLog,
    'sheriff_summary': sheriffSummary,
    'speech_order': speechOrder,
    'speech_index': speechIndex,
    'wolf_discussion': wolfDiscussion,
    'run_decisions': runDecisions.map((key, value) => MapEntry('$key', value)),
    'campaign_index': campaignIndex,
  };

  static WerewolfState fromJson(Map<String, dynamic> json) {
    Map<int, String> stringMap(Object? raw) {
      final result = <int, String>{};
      if (raw is Map) {
        for (final entry in raw.entries) {
          final key = int.tryParse('${entry.key}');
          if (key != null && entry.value is String) {
            result[key] = entry.value as String;
          }
        }
      }
      return result;
    }

    Map<int, int> intMap(Object? raw) {
      final result = <int, int>{};
      if (raw is Map) {
        for (final entry in raw.entries) {
          final key = int.tryParse('${entry.key}');
          final value = entry.value;
          if (key != null && value is num) result[key] = value.toInt();
        }
      }
      return result;
    }

    Map<int, List<String>> listMap(Object? raw) {
      final result = <int, List<String>>{};
      if (raw is Map) {
        for (final entry in raw.entries) {
          final key = int.tryParse('${entry.key}');
          final value = entry.value;
          if (key != null && value is List) {
            result[key] = [
              for (final item in value)
                if (item is String) item,
            ];
          }
        }
      }
      return result;
    }

    return WerewolfState(
      phase: werewolfPhaseFromKey('${json['phase'] ?? ''}'),
      day: _int(json['day']),
      night: _int(json['night']),
      nightStage: '${json['night_stage'] ?? 'wolves'}',
      awaiting: '${json['awaiting'] ?? ''}',
      nightKill: _intOrNull(json['night_kill']),
      saved: json['saved'] == true,
      poison: _intOrNull(json['poison']),
      seerTarget: _intOrNull(json['seer_target']),
      seerResult: json['seer_result'] is bool
          ? json['seer_result'] as bool
          : null,
      witchSaveAvailable: json['witch_save'] != false,
      witchPoisonAvailable: json['witch_poison'] != false,
      pendingHunter: _intOrNull(json['pending_hunter']),
      hunterAtNight: json['hunter_at_night'] == true,
      winner: '${json['winner'] ?? ''}',
      lastDeaths: [
        if (json['last_deaths'] is List)
          for (final item in json['last_deaths'] as List)
            if (item is num) item.toInt(),
      ],
      speeches: stringMap(json['speeches']),
      votes: intMap(json['votes']),
      aiVotes: intMap(json['ai_votes']),
      log: [
        if (json['log'] is List)
          for (final item in json['log'] as List)
            if (item is String) item,
      ],
      privateLog: listMap(json['private_log']),
      endedByPoison: json['ended_by_poison'] == true,
      sheriffId: _intOrNull(json['sheriff_id']),
      sheriffStage: '${json['sheriff_stage'] ?? 'candidacy'}',
      sheriffElectionDone: json['sheriff_election_done'] == true,
      candidates: [
        if (json['candidates'] is List)
          for (final item in json['candidates'] as List)
            if (item is num) item.toInt(),
      ],
      campaignSpeeches: stringMap(json['campaign_speeches']),
      sheriffVotes: intMap(json['sheriff_votes']),
      sheriffLog: [
        if (json['sheriff_log'] is List)
          for (final item in json['sheriff_log'] as List)
            if (item is String) item,
      ],
      sheriffSummary: '${json['sheriff_summary'] ?? ''}',
      speechOrder: [
        if (json['speech_order'] is List)
          for (final item in json['speech_order'] as List)
            if (item is num) item.toInt(),
      ],
      speechIndex: _int(json['speech_index']),
      wolfDiscussion: [
        if (json['wolf_discussion'] is List)
          for (final item in json['wolf_discussion'] as List)
            if (item is String) item,
      ],
      runDecisions: {
        for (final entry
            in (json['run_decisions'] is Map
                ? (json['run_decisions'] as Map).entries
                : const <MapEntry<dynamic, dynamic>>[]))
          if (int.tryParse('${entry.key}') != null && entry.value is bool)
            int.parse('${entry.key}'): entry.value as bool,
      },
      campaignIndex: _int(json['campaign_index']),
    );
  }

  String encode() => jsonEncode(toJson());

  static int _int(Object? raw) => raw is num ? raw.toInt() : 0;

  static int? _intOrNull(Object? raw) => raw is num ? raw.toInt() : null;
}

/// 给模型解析用的简单结果。
class WerewolfChoice {
  const WerewolfChoice({this.target, this.save, this.poison, this.text});

  final int? target;
  final bool? save;
  final int? poison;
  final String? text;
}

WerewolfRole? roleForSeat(List<GameMatchPlayer> players, int seat) {
  for (final player in players) {
    if (player.seat == seat) return WerewolfRole.fromKey(player.role);
  }
  return null;
}
