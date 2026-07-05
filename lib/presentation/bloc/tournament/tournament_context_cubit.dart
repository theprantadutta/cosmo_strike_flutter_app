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

  const TournamentContextState({this.tournamentId, this.mode});

  bool get isTournamentMode => tournamentId != null;

  @override
  List<Object?> get props => [tournamentId, mode];
}

class TournamentContextCubit extends Cubit<TournamentContextState> {
  TournamentContextCubit() : super(const TournamentContextState());

  void enterTournament(String tournamentId, TournamentGameMode mode) =>
      emit(TournamentContextState(tournamentId: tournamentId, mode: mode));

  void exitTournament() => emit(const TournamentContextState());
}
