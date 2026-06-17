import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:get_it/get_it.dart';
import 'package:cosmo_strike_flutter_app/data/daos/tournament_dao.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/models/tournament.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/services/notification_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';
import 'package:uuid/uuid.dart';

/// Server-authoritative leaderboard shape used by the tournament
/// detail screen.
class TournamentLeaderboardResult {
  final List<TournamentParticipant> entries;
  final int? userRank;

  const TournamentLeaderboardResult({
    required this.entries,
    required this.userRank,
  });
}

/// Drift-first tournament cache.
///
///   * `getXxx` reads return whatever the local cache currently holds
///     (fast, offline-safe).
///   * `refreshXxx` methods fetch the backend and write through to
///     Drift via atomic DAO replace operations.
///   * `join` and `submitScore` are **live** API calls — entry quotas
///     and final ranking are server-validated in real time; deferring
///     them would let the user join a tournament they don't qualify
///     for and discover the rejection only after they've played.
///   * Per-resource staleness is tracked in [TournamentMeta] so the
///     UI can render an "Updated X ago" chip per board / detail page.
class TournamentService {
  static TournamentService? _instance;

  TournamentService._internal();

  factory TournamentService() {
    _instance ??= TournamentService._internal();
    return _instance!;
  }

  final ApiService _api = ApiService();
  final Uuid _uuid = const Uuid();

  // Broadcast hook the cubits + dashboards listen to so they can
  // re-fetch their own state right after a join succeeds.
  final StreamController<String> _joinedController =
      StreamController<String>.broadcast();
  Stream<String> get onTournamentJoined => _joinedController.stream;

  TournamentDao get _dao => GetIt.I<AppDatabase>().tournamentDao;

  // -------------- Reads (cache-first) --------------

  Future<List<Tournament>> getActiveTournaments() async {
    final rows = await _dao.getActive();
    return rows.map(_rowToTournament).toList();
  }

  Future<List<Tournament>> getTournamentHistory({int limit = 10}) async {
    final rows = await _dao.getHistory();
    return rows.take(limit).map(_rowToTournament).toList();
  }

  Future<Tournament?> getTournament(String tournamentId) async {
    final row = await _dao.getTournament(tournamentId);
    if (row == null) return null;
    return _rowToTournament(row);
  }

  Future<TournamentLeaderboardResult> getTournamentLeaderboard(
    String tournamentId, {
    int limit = 50,
  }) async {
    final rows = await _dao.getLeaderboard(tournamentId);
    final meta =
        await _dao.getMeta(TournamentMetaKey.leaderboard(tournamentId));
    return TournamentLeaderboardResult(
      entries: rows.take(limit).map(_leaderboardRowToParticipant).toList(),
      userRank: meta?.currentUserRank,
    );
  }

  Future<Map<String, dynamic>> getUserTournamentStats() async => const {};

  Future<bool> hasCachedData() async {
    final actives = await _dao.getActive();
    return actives.isNotEmpty;
  }

  Future<void> clearCache() => _dao.clear();

  Stream<List<Tournament>> watchActiveTournaments() => _dao
      .watchActive()
      .map((rows) => rows.map(_rowToTournament).toList());

  Stream<List<Tournament>> watchTournamentHistory() => _dao
      .watchHistory()
      .map((rows) => rows.map(_rowToTournament).toList());

  Stream<Tournament?> watchTournament(String tournamentId) => _dao
      .watchTournament(tournamentId)
      .map((row) => row == null ? null : _rowToTournament(row));

  Stream<List<TournamentParticipant>> watchTournamentLeaderboard(
    String tournamentId, {
    int limit = 50,
  }) =>
      _dao.watchLeaderboard(tournamentId).map(
            (rows) => rows
                .take(limit)
                .map(_leaderboardRowToParticipant)
                .toList(),
          );

  Future<DateTime?> getLastRefreshedAt(String metaKey) async {
    final meta = await _dao.getMeta(metaKey);
    return meta?.lastRefreshedAt;
  }

  // -------------- Refresh (write-through) --------------

  /// Pull /tournaments/active and overwrite the active-list cache.
  Future<void> refreshActive() async {
    final body = await _safeFetch(() => _api.getActiveTournaments());
    if (body == null) return;
    final raw = body['tournaments'];
    if (raw is! List) {
      AppLogger.warning(
        'TournamentService.refreshActive: missing tournaments list',
      );
      return;
    }
    final companions = raw
        .whereType<Map<String, dynamic>>()
        .map(_companionFromWire)
        .whereType<TournamentsCacheCompanion>()
        .toList();
    await _dao.replaceActive(
      tournaments: companions,
      refreshedAt: DateTime.now(),
    );
  }

  /// Pull /tournaments?status=completed and merge the rows into the
  /// cache as history entries. Doesn't wipe active-list rows.
  Future<void> refreshHistory({int limit = 50}) async {
    final body = await _safeFetch(
      () => _api.getTournamentsList(status: 'completed'),
    );
    if (body == null) return;
    final raw = body['tournaments'];
    if (raw is! List) {
      AppLogger.warning(
        'TournamentService.refreshHistory: missing tournaments list',
      );
      return;
    }
    final companions = raw
        .whereType<Map<String, dynamic>>()
        .take(limit)
        .map(_companionFromWire)
        .whereType<TournamentsCacheCompanion>()
        .toList();
    await _dao.replaceHistory(
      tournaments: companions,
      refreshedAt: DateTime.now(),
    );
  }

  /// Pull a single tournament's full detail (with user-specific stats)
  /// and upsert the row.
  Future<Tournament?> refreshTournament(String tournamentId) async {
    final body = await _safeFetch(() => _api.getTournament(tournamentId));
    if (body == null) return getTournament(tournamentId);
    final companion = _companionFromWire(body);
    if (companion != null) {
      await _dao.upsertTournament(
        tournament: companion,
        refreshedAt: DateTime.now(),
      );
    }
    return getTournament(tournamentId);
  }

  /// Pull and replace the per-tournament leaderboard cache.
  Future<TournamentLeaderboardResult> refreshTournamentLeaderboard(
    String tournamentId, {
    int limit = 100,
  }) async {
    final body = await _safeFetch(
      () => _api.getTournamentLeaderboardRemote(tournamentId, limit: limit),
    );
    if (body == null) return getTournamentLeaderboard(tournamentId);

    final rawEntries = body['entries'];
    if (rawEntries is! List) {
      return getTournamentLeaderboard(tournamentId);
    }

    final companions = <TournamentLeaderboardCacheCompanion>[];
    for (final raw in rawEntries) {
      if (raw is! Map<String, dynamic>) continue;
      companions.add(TournamentLeaderboardCacheCompanion.insert(
        tournamentId: tournamentId,
        rank: raw['rank'] as int? ?? 0,
        userId: (raw['user_id'] ?? raw['userId'] ?? '').toString(),
        username: d.Value(raw['username'] as String?),
        displayName:
            d.Value((raw['display_name'] ?? raw['displayName']) as String?),
        photoUrl: d.Value((raw['photo_url'] ?? raw['photoUrl']) as String?),
        bestScore:
            d.Value((raw['best_score'] ?? raw['bestScore']) as int? ?? 0),
        gamesPlayed:
            d.Value((raw['games_played'] ?? raw['gamesPlayed']) as int? ?? 0),
        prizeClaimed: d.Value(
          (raw['prize_claimed'] ?? raw['prizeClaimed']) as bool? ?? false,
        ),
      ));
    }

    final currentUserRank =
        (body['current_user_rank'] ?? body['currentUserRank']) as int?;

    await _dao.replaceLeaderboard(
      tournamentId: tournamentId,
      entries: companions,
      currentUserRank: currentUserRank,
      refreshedAt: DateTime.now(),
    );

    return getTournamentLeaderboard(tournamentId);
  }

  // -------------- Live mutations --------------

  /// Join a tournament. Live call — server validates entry quota and
  /// status. On success, the returned tournament row (now with
  /// is_joined=true) is upserted into the cache so the UI flips the
  /// "join" button without waiting for a re-fetch.
  Future<bool> joinTournament(
    String tournamentId, {
    String? entryTier,
  }) async {
    if (!_api.isAuthenticated) return false;
    final body = await _safeFetch(() => _api.joinTournamentRemote(tournamentId));
    if (body == null) return false;
    final companion = _companionFromWire(body);
    if (companion != null) {
      await _dao.upsertTournament(
        tournament: companion,
        refreshedAt: DateTime.now(),
      );
    }
    _joinedController.add(tournamentId);
    // Subscribe to this tournament's FCM topic so per-tournament
    // reminders from the backend actually reach this device (gated by
    // the tournament notification toggle inside the service).
    unawaited(NotificationService().onTournamentJoined(tournamentId));
    return true;
  }

  /// Submit a tournament score. Live call — server reranks immediately.
  /// Generates an idempotency key client-side so retries de-dupe.
  Future<bool> submitScore(
    String tournamentId,
    int score,
    Map<String, dynamic> gameStats, {
    String? idempotencyKey,
  }) async {
    if (!_api.isAuthenticated) return false;
    final body = await _safeFetch(
      () => _api.submitTournamentScoreRemote(
        tournamentId: tournamentId,
        score: score,
        gameDurationSeconds:
            (gameStats['gameDurationSeconds'] ?? gameStats['durationSeconds'])
                    as int? ??
                0,
        foodsEaten: gameStats['foodsEaten'] as int? ?? 0,
        // Caller-supplied stable key (per game run) so a timeout-retry
        // de-dupes server-side; fall back to a fresh key if not provided.
        idempotencyKey: idempotencyKey ?? _uuid.v4(),
      ),
    );
    if (body == null) return false;
    // Refresh the tournament + its leaderboard so the UI sees the
    // new rank immediately. Errors during refresh are swallowed —
    // the submission already landed.
    unawaited(refreshTournament(tournamentId));
    unawaited(refreshTournamentLeaderboard(tournamentId));
    return true;
  }

  /// Claim the caller's prize for [tournamentId] (idempotent on the server).
  /// Prizes are server-determined but credited CLIENT-SIDE so they ride the
  /// offline-first, client-authoritative coin balance (a server-side credit
  /// would be clobbered by the next coin sync). Credits coins locally only
  /// when this call actually performed the claim (`already_claimed == false`).
  /// Returns the coins credited (0 when nothing to claim / already claimed).
  Future<int> claimPrize(String tournamentId) async {
    if (!_api.isAuthenticated) return 0;
    final body =
        await _safeFetch(() => _api.claimTournamentPrizeRemote(tournamentId));
    if (body == null) return 0;

    final success = (body['success'] as bool?) ?? false;
    final alreadyClaimed =
        (body['already_claimed'] ?? body['alreadyClaimed']) as bool? ?? false;
    final prizeCoins =
        (body['prize_coins'] ?? body['prizeCoins']) as int? ?? 0;

    if (!success || alreadyClaimed || prizeCoins <= 0) return 0;

    if (GetIt.I.isRegistered<CoinsCubit>()) {
      await GetIt.I<CoinsCubit>().earnCoins(
        CoinEarningSource.tournamentReward,
        customAmount: prizeCoins,
        itemName: 'Tournament prize',
        metadata: {'tournament_id': tournamentId},
      );
    }
    // Refresh so the cached tournament reflects prize_claimed = true.
    unawaited(refreshTournament(tournamentId));
    return prizeCoins;
  }

  // -------------- Internals --------------

  Future<Map<String, dynamic>?> _safeFetch(
    Future<Map<String, dynamic>?> Function() fetch,
  ) async {
    try {
      return await fetch();
    } catch (e) {
      AppLogger.error('TournamentService fetch errored', e);
      return null;
    }
  }

  /// Build a [TournamentsCacheCompanion] from a wire response payload.
  /// Stores the full payload in `data_json` so the existing
  /// [Tournament.fromJson] consumer keeps reading it untouched.
  /// Returns null for a payload with no usable id — persisting it would
  /// collapse every malformed row onto the same empty-string cache key.
  TournamentsCacheCompanion? _companionFromWire(Map<String, dynamic> raw) {
    final id = (raw['id'] ?? raw['tournament_id'] ?? '').toString();
    if (id.isEmpty) {
      AppLogger.warning('TournamentService: dropping cache row with no id');
      return null;
    }
    final status = (raw['status'] as String?) ?? 'upcoming';
    final endDateRaw = raw['end_date'] ?? raw['endDate'];
    final endDate = endDateRaw is String
        ? DateTime.tryParse(endDateRaw) ?? DateTime.now()
        : DateTime.now();
    return TournamentsCacheCompanion.insert(
      id: id,
      dataJson: jsonEncode(raw),
      status: status,
      endDate: endDate,
    );
  }

  Tournament _rowToTournament(TournamentsCacheData row) {
    try {
      return Tournament.fromJsonString(row.dataJson);
    } catch (e) {
      AppLogger.error(
        'TournamentService: failed to deserialise cached tournament ${row.id}',
        e,
      );
      // Minimal fallback so the UI doesn't crash on a corrupted row.
      return Tournament(
        id: row.id,
        name: 'Unknown tournament',
        description: '',
        type: TournamentType.daily,
        status: TournamentStatus.upcoming,
        gameMode: TournamentGameMode.classic,
        startDate: row.endDate,
        endDate: row.endDate,
      );
    }
  }

  TournamentParticipant _leaderboardRowToParticipant(
    TournamentLeaderboardCacheData row,
  ) {
    return TournamentParticipant(
      userId: row.userId,
      displayName: row.displayName ?? row.username ?? 'Player',
      photoUrl: row.photoUrl,
      highScore: row.bestScore,
      attempts: row.gamesPlayed,
      lastScoreDate: row.cachedAt,
      joinedDate: row.cachedAt,
    );
  }
}
