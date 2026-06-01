import 'package:drift/drift.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';

part 'tournament_dao.g.dart';

/// String keys for the [TournamentMeta] table. Centralised here so
/// service + screen don't drift on the format.
class TournamentMetaKey {
  static const String activeList = 'active';
  static const String historyList = 'history';
  static String detail(String tournamentId) => 'detail:$tournamentId';
  static String leaderboard(String tournamentId) => 'leaderboard:$tournamentId';
}

@DriftAccessor(tables: [
  TournamentsCache,
  TournamentLeaderboardCache,
  TournamentMeta,
])
class TournamentDao extends DatabaseAccessor<AppDatabase>
    with _$TournamentDaoMixin {
  TournamentDao(super.db);

  // -------------- Tournaments list --------------

  /// Currently-cached tournaments tagged as belonging to the active
  /// list, ordered by end date ascending so the closest-to-ending
  /// shows first (matches typical UX expectations).
  Stream<List<TournamentsCacheData>> watchActive() =>
      (select(tournamentsCache)
            ..where((t) => t.isActiveList.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.endDate)]))
          .watch();

  Future<List<TournamentsCacheData>> getActive() =>
      (select(tournamentsCache)
            ..where((t) => t.isActiveList.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.endDate)]))
          .get();

  /// Past tournaments (status in {'ended', 'completed'} OR explicitly
  /// not in the active list). Ordered most-recent-first.
  Stream<List<TournamentsCacheData>> watchHistory() =>
      (select(tournamentsCache)
            ..where((t) => t.isActiveList.equals(false))
            ..orderBy([(t) => OrderingTerm.desc(t.endDate)]))
          .watch();

  Future<List<TournamentsCacheData>> getHistory() =>
      (select(tournamentsCache)
            ..where((t) => t.isActiveList.equals(false))
            ..orderBy([(t) => OrderingTerm.desc(t.endDate)]))
          .get();

  /// Single tournament row by id.
  Future<TournamentsCacheData?> getTournament(String id) =>
      (select(tournamentsCache)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Stream<TournamentsCacheData?> watchTournament(String id) =>
      (select(tournamentsCache)..where((t) => t.id.equals(id)))
          .watchSingleOrNull();

  /// Atomic replace of the "active list" cache: tags every supplied
  /// row with `is_active_list=true`, leaves rows from a previous
  /// active fetch that aren't in this batch demoted to history
  /// (they probably ended). Updates the meta row too.
  Future<void> replaceActive({
    required List<TournamentsCacheCompanion> tournaments,
    required DateTime refreshedAt,
  }) async {
    await transaction(() async {
      // Demote any previously-active rows so we can identify removed
      // ones; the upsert below will re-promote the survivors.
      await (update(tournamentsCache)..where((t) => t.isActiveList.equals(true)))
          .write(const TournamentsCacheCompanion(
        isActiveList: Value(false),
      ));
      for (final t in tournaments) {
        await into(tournamentsCache).insertOnConflictUpdate(
          t.copyWith(isActiveList: const Value(true)),
        );
      }
      await into(tournamentMeta).insertOnConflictUpdate(
        TournamentMetaCompanion(
          metaKey: const Value(TournamentMetaKey.activeList),
          lastRefreshedAt: Value(refreshedAt),
        ),
      );
    });
  }

  /// Atomic replace of the history list. Existing rows that match
  /// incoming ids are upserted; everything else is left alone so a
  /// freshly-active row (currently in active cache) isn't wiped when
  /// only the history list refreshes.
  Future<void> replaceHistory({
    required List<TournamentsCacheCompanion> tournaments,
    required DateTime refreshedAt,
  }) async {
    await transaction(() async {
      for (final t in tournaments) {
        await into(tournamentsCache).insertOnConflictUpdate(
          t.copyWith(isActiveList: const Value(false)),
        );
      }
      await into(tournamentMeta).insertOnConflictUpdate(
        TournamentMetaCompanion(
          metaKey: const Value(TournamentMetaKey.historyList),
          lastRefreshedAt: Value(refreshedAt),
        ),
      );
    });
  }

  /// Upsert a single tournament row (used by the detail-fetch path).
  Future<void> upsertTournament({
    required TournamentsCacheCompanion tournament,
    required DateTime refreshedAt,
  }) async {
    final tid = tournament.id.present ? tournament.id.value : null;
    await transaction(() async {
      await into(tournamentsCache).insertOnConflictUpdate(tournament);
      if (tid != null) {
        await into(tournamentMeta).insertOnConflictUpdate(
          TournamentMetaCompanion(
            metaKey: Value(TournamentMetaKey.detail(tid)),
            lastRefreshedAt: Value(refreshedAt),
          ),
        );
      }
    });
  }

  // -------------- Per-tournament leaderboard --------------

  Stream<List<TournamentLeaderboardCacheData>> watchLeaderboard(
    String tournamentId,
  ) =>
      (select(tournamentLeaderboardCache)
            ..where((t) => t.tournamentId.equals(tournamentId))
            ..orderBy([(t) => OrderingTerm.asc(t.rank)]))
          .watch();

  Future<List<TournamentLeaderboardCacheData>> getLeaderboard(
    String tournamentId,
  ) =>
      (select(tournamentLeaderboardCache)
            ..where((t) => t.tournamentId.equals(tournamentId))
            ..orderBy([(t) => OrderingTerm.asc(t.rank)]))
          .get();

  Future<void> replaceLeaderboard({
    required String tournamentId,
    required List<TournamentLeaderboardCacheCompanion> entries,
    required int? currentUserRank,
    required DateTime refreshedAt,
  }) async {
    await transaction(() async {
      await (delete(tournamentLeaderboardCache)
            ..where((t) => t.tournamentId.equals(tournamentId)))
          .go();
      if (entries.isNotEmpty) {
        await batch((b) {
          b.insertAll(tournamentLeaderboardCache, entries);
        });
      }
      await into(tournamentMeta).insertOnConflictUpdate(
        TournamentMetaCompanion(
          metaKey: Value(TournamentMetaKey.leaderboard(tournamentId)),
          lastRefreshedAt: Value(refreshedAt),
          currentUserRank: Value(currentUserRank),
        ),
      );
    });
  }

  // -------------- Meta / staleness --------------

  Future<TournamentMetaData?> getMeta(String metaKey) =>
      (select(tournamentMeta)..where((t) => t.metaKey.equals(metaKey)))
          .getSingleOrNull();

  Stream<TournamentMetaData?> watchMeta(String metaKey) =>
      (select(tournamentMeta)..where((t) => t.metaKey.equals(metaKey)))
          .watchSingleOrNull();

  // -------------- Cleanup --------------

  Future<void> clear() async {
    await transaction(() async {
      await delete(tournamentsCache).go();
      await delete(tournamentLeaderboardCache).go();
      await delete(tournamentMeta).go();
    });
  }
}
