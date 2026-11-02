import 'package:echo/domain/models/game.dart';
import 'package:echo/domain/models/werewolf.dart';
import 'package:echo/domain/services/werewolf_service.dart';
import 'package:flutter_test/flutter_test.dart';

GameMatchPlayer _player(int seat, WerewolfRole role, {bool alive = true}) =>
    GameMatchPlayer(
      id: 'p$seat',
      matchId: 'm1',
      name: '$seat号',
      seat: seat,
      isUser: seat == 1,
      alive: alive,
      role: role.name,
    );

void main() {
  test('狼人杀状态可以完整编码再还原', () {
    final state = WerewolfState(
      phase: WerewolfPhase.speaking,
      day: 2,
      night: 3,
      awaiting: 'user_speech',
      nightKill: 4,
      saved: true,
      poison: 6,
      seerTarget: 8,
      seerResult: true,
      speeches: {1: '我先听', 2: '我怀疑 3 号'},
      votes: {1: 3, 2: 3},
      log: ['第 1 天，天亮了。'],
      privateLog: {
        1: ['你是狼人'],
      },
      sheriffId: 2,
      sheriffElectionDone: true,
      sheriffStage: 'done',
      candidates: [2, 3],
      campaignSpeeches: {2: '我上警', 3: '投我'},
      sheriffVotes: {1: 2, 4: 2},
      sheriffLog: ['2 号当选警长'],
      speechOrder: [2, 3, 1],
      speechIndex: 1,
      wolfDiscussion: ['1号：刀 4'],
    );
    final restored = WerewolfState.fromJson(state.toJson());
    expect(restored.phase, WerewolfPhase.speaking);
    expect(restored.day, 2);
    expect(restored.awaiting, 'user_speech');
    expect(restored.saved, isTrue);
    expect(restored.seerResult, isTrue);
    expect(restored.speeches[2], '我怀疑 3 号');
    expect(restored.privateLog[1], ['你是狼人']);
    expect(restored.sheriffId, 2);
    expect(restored.sheriffElectionDone, isTrue);
    expect(restored.candidates, [2, 3]);
    expect(restored.campaignSpeeches[3], '投我');
    expect(restored.sheriffVotes[4], 2);
    expect(restored.speechOrder, [2, 3, 1]);
    expect(restored.speechIndex, 1);
    expect(restored.wolfDiscussion.single, '1号：刀 4');
  });

  test('胜负：狼人清空好人赢，好人清空狼人赢', () {
    final goodWin = [
      _player(1, WerewolfRole.villager),
      _player(2, WerewolfRole.seer),
      _player(3, WerewolfRole.werewolf, alive: false),
    ];
    expect(WerewolfService.winnerFor(goodWin), 'good');

    final evilWin = [
      _player(1, WerewolfRole.werewolf),
      _player(2, WerewolfRole.werewolf),
      _player(3, WerewolfRole.villager),
      _player(4, WerewolfRole.seer, alive: false),
    ];
    expect(WerewolfService.winnerFor(evilWin), 'evil');

    final running = [
      _player(1, WerewolfRole.werewolf),
      _player(2, WerewolfRole.villager),
      _player(3, WerewolfRole.villager),
      _player(4, WerewolfRole.seer),
    ];
    expect(WerewolfService.winnerFor(running), isNull);

    // GameWeb 的“屠边”：村民全死或神职全死，狼人也赢。
    final noVillagers = [
      _player(1, WerewolfRole.werewolf),
      _player(2, WerewolfRole.seer),
      _player(3, WerewolfRole.witch),
    ];
    expect(WerewolfService.winnerFor(noVillagers), 'evil');
    final noSpecial = [
      _player(1, WerewolfRole.werewolf),
      _player(2, WerewolfRole.villager),
      _player(3, WerewolfRole.villager),
    ];
    expect(WerewolfService.winnerFor(noSpecial), 'evil');
  });

  test('狼人投票按多数决，平票回退', () {
    expect(WerewolfService.majorityFor([2, 2, 3], fallback: 5), 2);
    expect(WerewolfService.majorityFor([], fallback: 5), 5);
  });

  test('发言顺序蛇形交替，警长最后', () {
    final players = [
      for (var seat = 1; seat <= 5; seat++)
        _player(seat, WerewolfRole.villager),
    ];
    expect(WerewolfService.speechOrderFor(1, players, null), [1, 2, 3, 4, 5]);
    expect(WerewolfService.speechOrderFor(2, players, null), [5, 4, 3, 2, 1]);
    expect(WerewolfService.speechOrderFor(1, players, 3), [1, 2, 4, 5, 3]);
  });

  test('角色名和阵营映射稳定', () {
    expect(WerewolfRole.fromKey('werewolf').evil, isTrue);
    expect(WerewolfRole.fromKey('seer').evil, isFalse);
    expect(WerewolfRole.fromKey('unknown'), WerewolfRole.villager);
  });
}
