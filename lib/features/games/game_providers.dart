import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/game_repository.dart';
import '../../domain/models/game.dart';
import '../../domain/services/werewolf_service.dart';
import 'game_board.dart';

final gameMatchProvider = StreamProvider.autoDispose.family<GameMatch?, String>(
  (ref, id) => ref.watch(gameRepositoryProvider).watchMatch(id),
);

final gameInviteProvider = StreamProvider.autoDispose
    .family<GameInvite?, String>(
      (ref, id) => ref.watch(gameRepositoryProvider).watchInvite(id),
    );

final gameMessagesProvider = StreamProvider.autoDispose
    .family<List<GameMessage>, String>(
      (ref, matchId) =>
          ref.watch(gameRepositoryProvider).watchMessagesFor(matchId),
    );

final gameInvitesForResidentProvider = StreamProvider.autoDispose
    .family<List<GameInvite>, String>(
      (ref, residentId) =>
          ref.watch(gameRepositoryProvider).watchInvitesFor(residentId),
    );

final gameMatchesForResidentProvider = StreamProvider.autoDispose
    .family<List<GameMatch>, String>(
      (ref, residentId) =>
          ref.watch(gameRepositoryProvider).watchMatchesFor(residentId),
    );

final activeGameMatchesProvider = StreamProvider.autoDispose<List<GameMatch>>(
  (ref) => ref.watch(gameRepositoryProvider).watchActiveMatches(),
);

final allGameInvitesProvider = StreamProvider.autoDispose<List<GameInvite>>(
  (ref) => ref.watch(gameRepositoryProvider).watchAllInvites(),
);

final recentGameMatchesProvider = StreamProvider.autoDispose<List<GameMatch>>(
  (ref) => ref.watch(gameRepositoryProvider).watchRecentMatches(),
);

final boardImageRendererProvider = Provider<BoardImageRenderer>(
  (ref) => BoardImageRenderer(),
);

final gamePlayersProvider = StreamProvider.autoDispose
    .family<List<GameMatchPlayer>, String>(
      (ref, matchId) =>
          ref.watch(gameRepositoryProvider).watchPlayersFor(matchId),
    );

final werewolfStateProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>?, String>(
      (ref, matchId) => ref.watch(werewolfServiceProvider).watchState(matchId),
    );

final gameStateProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>?, String>(
      (ref, matchId) => ref.watch(gameRepositoryProvider).watchState(matchId),
    );
