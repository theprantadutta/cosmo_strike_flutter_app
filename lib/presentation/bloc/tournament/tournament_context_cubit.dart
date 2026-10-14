import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../models/tournament.dart';

/// The one piece of cross-screen game context: which tournament (if any) the
/// next Flame run is played for. TournamentDetailScreen sets it before pushing
/// the gameplay route, PreGameLoadingScreen reads the mode override, and
/// GameplayScreen attributes the run's score to the tournament and clears the
/// context when it unmounts.
///
/// This replaces the tournament fields that used to live on the retired
/// snake-era GameCubit — the run itself lives entirely in Flame.
class TournamentContextState extends Equatable {
  final String? tournamentId;
  final TournamentGameMode? mode;

  /// Set for a Daily Run: seeds the game's RNG so everyone flies the same
  /// spawn layout today. Can be set without a tournament (offline daily run).
  final int? dailySeed;

  const TournamentContextState({this.tournamentId, this.mode, this.dailySeed});

  bool get isTournamentMode => tournamentId != null;
  bool get isDailyRun => dailySeed != null;

  @override
  List<Object?> get props => [tournamentId, mode, dailySeed];
}

class TournamentContextCubit extends Cubit<TournamentContextState> {
  TournamentContextCubit() : super(const TournamentContextState());

  void enterTournament(String tournamentId, TournamentGameMode mode) =>
      emit(TournamentContextState(tournamentId: tournamentId, mode: mode));

  /// Arm a Daily Run (today's seed), attributed to [tournamentId] when the
  /// daily tournament is known and joined.
  void enterDailyRun({required int seed, String? tournamentId, TournamentGameMode? mode}) =>
      emit(TournamentContextState(tournamentId: tournamentId, mode: mode, dailySeed: seed));

  void exitTournament() => emit(const TournamentContextState());
}
