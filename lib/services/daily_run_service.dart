import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../models/tournament.dart';
import '../presentation/bloc/tournament/tournament_context_cubit.dart';
import '../router/routes.dart';
import '../utils/logger.dart';
import 'tournament_service.dart';

/// The Daily Run: one shared run per UTC day.
///
/// - Seeded by the date, so every pilot flies the same spawn layout today.
/// - Attributed to today's "Daily Challenge" tournament (created by the
///   backend at UTC midnight: free entry, unlimited attempts, best score
///   wins, its own per-day leaderboard + prizes). Joining is automatic.
/// - Offline (or signed-out) it still plays with today's seed, just without
///   the tournament attribution.
class DailyRunService {
  DailyRunService._();

  /// Days since the Unix epoch in UTC — the seed and the run's identity.
  static int todaySeed([DateTime? now]) {
    final d = (now ?? DateTime.now()).toUtc();
    return DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;
  }

  /// Today's active daily tournament from the local cache, refreshing once
  /// when the cache has none (e.g. right after UTC midnight).
  static Future<Tournament?> todaysTournament() async {
    final service = TournamentService();
    Tournament? pick(List<Tournament> all) => all
        .where((t) => t.type == TournamentType.daily && t.status == TournamentStatus.active)
        .where((t) => t.endDate.isAfter(DateTime.now()))
        .firstOrNull;
    var found = pick(await service.getActiveTournaments());
    if (found == null) {
      try {
        await service.refreshActive();
        found = pick(await service.getActiveTournaments());
      } catch (e) {
        AppLogger.info('Daily run: tournament refresh failed ($e) — playing unattributed');
      }
    }
    return found;
  }

  /// Arm and start today's run (through the pre-game loader, from level 1).
  static Future<void> launch(BuildContext context) async {
    final contextCubit = context.read<TournamentContextCubit>();
    final router = GoRouter.of(context);
    final seed = todaySeed();
    final tournament = await todaysTournament();
    var attributedId = tournament?.id;
    if (tournament != null && !tournament.isJoinedServer) {
      final joined = await TournamentService().joinTournament(tournament.id);
      if (!joined) attributedId = null;
    }
    contextCubit.enterDailyRun(
      seed: seed,
      tournamentId: attributedId,
      mode: attributedId == null ? null : tournament?.gameMode,
    );
    router.push(AppRoutes.playLoading, extra: 1);
  }
}
