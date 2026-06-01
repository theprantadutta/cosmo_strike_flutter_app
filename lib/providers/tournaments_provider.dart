import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:cosmo_strike_flutter_app/models/tournament.dart';
import 'package:cosmo_strike_flutter_app/services/tournament_service.dart';
import 'package:cosmo_strike_flutter_app/providers/providers.dart';

/// State for tournaments data
class TournamentsState {
  final List<Tournament> activeTournaments;
  final List<Tournament> historyTournaments;
  final Map<String, dynamic> userStats;
  final bool isLoading;
  final bool isOffline;
  final String? error;
  /// Drift-cache freshness — null until the first successful refresh
  /// per list. Surfaced to the screen so a stale offline view is
  /// labelled rather than silently presented as live.
  final DateTime? activeLastRefreshedAt;
  final DateTime? historyLastRefreshedAt;

  const TournamentsState({
    this.activeTournaments = const [],
    this.historyTournaments = const [],
    this.userStats = const {},
    this.isLoading = false,
    this.isOffline = false,
    this.error,
    this.activeLastRefreshedAt,
    this.historyLastRefreshedAt,
  });

  TournamentsState copyWith({
    List<Tournament>? activeTournaments,
    List<Tournament>? historyTournaments,
    Map<String, dynamic>? userStats,
    bool? isLoading,
    bool? isOffline,
    String? error,
    DateTime? activeLastRefreshedAt,
    DateTime? historyLastRefreshedAt,
  }) {
    return TournamentsState(
      activeTournaments: activeTournaments ?? this.activeTournaments,
      historyTournaments: historyTournaments ?? this.historyTournaments,
      userStats: userStats ?? this.userStats,
      isLoading: isLoading ?? this.isLoading,
      isOffline: isOffline ?? this.isOffline,
      error: error,
      activeLastRefreshedAt:
          activeLastRefreshedAt ?? this.activeLastRefreshedAt,
      historyLastRefreshedAt:
          historyLastRefreshedAt ?? this.historyLastRefreshedAt,
    );
  }
}

/// Notifier for tournaments with TTL-based auto-refresh
class TournamentsNotifier extends StateNotifier<TournamentsState> {
  final Ref _ref;
  final TournamentService _service;
  Timer? _ttlTimer;
  StreamSubscription<String>? _joinSubscription;

  static const _ttl = Duration(minutes: 5);

  TournamentsNotifier(this._ref)
    : _service = TournamentService(),
      super(const TournamentsState(isLoading: true)) {
    _initialize();
  }

  void _initialize() {
    // Drift-first paint: hydrate from the local cache immediately,
    // then trigger a background refresh that re-hydrates when it
    // lands. The legacy AppDataCache preload path is left intact
    // for the (still in-memory) FE startup pipeline but the Drift
    // cache survives across cold starts so the user always sees
    // their last-known data first.
    _loadData();

    // Set up TTL-based refresh
    _startTtlTimer();

    // Auto-refresh whenever ANY caller successfully joins a tournament.
    // The service broadcasts onTournamentJoined regardless of who
    // initiated the join (detail screen, deep link, anywhere), so the
    // list stays in sync without each call site reaching into Riverpod.
    _joinSubscription = _service.onTournamentJoined.listen((_) {
      _refreshInBackground();
    });

    // Listen for connectivity changes - refresh when coming online
    _ref.listen<AsyncValue<bool>>(isOnlineProvider, (previous, next) {
      final wasOffline = previous?.value == false;
      final isNowOnline = next.value == true;

      state = state.copyWith(isOffline: !(next.value ?? false));

      if (wasOffline && isNowOnline) {
        // Stagger connectivity-restore refreshes to avoid API stampede
        Future.delayed(const Duration(seconds: 3), () => refresh());
      }
    });
  }

  Future<void> _refreshInBackground() async {
    // Silent refresh - don't set isLoading. Cache-first: re-read from
    // Drift after the network refresh lands so the screen sees whatever
    // the server returned (or the previous good cache when offline).
    try {
      await Future.wait([
        _service.refreshActive(),
        _service.refreshHistory(),
      ]);
      await _hydrateFromCache();
    } catch (_) {
      // Ignore errors in background refresh
    }
  }

  void _startTtlTimer() {
    _ttlTimer?.cancel();
    _ttlTimer = Timer.periodic(_ttl, (_) {
      final isOnline = _ref.read(isOnlineSyncProvider);
      if (isOnline) {
        refresh();
      }
    });
  }

  Future<void> _loadData() async {
    // Cache-first paint: show whatever's in Drift immediately. The
    // spinner only surfaces when there's nothing yet — the screen
    // hides the empty-state flash on subsequent opens.
    await _hydrateFromCache(isLoading: false);
    final hadCache = state.activeTournaments.isNotEmpty ||
        state.historyTournaments.isNotEmpty;
    state = state.copyWith(
      isLoading: !hadCache,
      error: null,
    );

    try {
      await Future.wait([
        _service.refreshActive(),
        _service.refreshHistory(),
      ]);
      await _hydrateFromCache(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        // Only surface an error when we have nothing to show at all.
        error: hadCache ? null : 'Failed to load tournaments',
      );
    }
  }

  /// Refresh tournaments from the server. Keeps the cached entries on
  /// screen while the network call is in flight so the user never
  /// stares at an empty page mid-refresh.
  Future<void> refresh() async {
    final hadCache = state.activeTournaments.isNotEmpty ||
        state.historyTournaments.isNotEmpty;
    state = state.copyWith(isLoading: !hadCache, error: null);

    try {
      await Future.wait([
        _service.refreshActive(),
        _service.refreshHistory(),
      ]);
      await _hydrateFromCache(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: hadCache ? null : 'Failed to refresh tournaments',
      );
    }
  }

  /// Pull whatever's currently in the Drift cache into Riverpod state.
  /// Called immediately on init (for the cache-first paint), after a
  /// network refresh lands, and whenever the underlying Drift stream
  /// notifies of an update from elsewhere (join / submit / restore).
  Future<void> _hydrateFromCache({bool? isLoading}) async {
    final active = await _service.getActiveTournaments();
    final history = await _service.getTournamentHistory(limit: 50);
    final activeMeta =
        await _service.getLastRefreshedAt('active');
    final historyMeta =
        await _service.getLastRefreshedAt('history');
    state = state.copyWith(
      activeTournaments: active,
      historyTournaments: history,
      isLoading: isLoading,
      isOffline: !_ref.read(isOnlineSyncProvider),
      activeLastRefreshedAt: activeMeta,
      historyLastRefreshedAt: historyMeta,
    );
  }

  /// Join a tournament
  Future<bool> joinTournament(String tournamentId) async {
    final success = await _service.joinTournament(tournamentId);
    if (success) {
      // Refresh to get updated participant count
      await refresh();
    }
    return success;
  }

  /// Submit score to a tournament
  Future<bool> submitScore(
    String tournamentId,
    int score,
    Map<String, dynamic> gameStats,
  ) async {
    return await _service.submitScore(tournamentId, score, gameStats);
  }

  /// Get tournament by ID
  Future<Tournament?> getTournament(String tournamentId) async {
    return await _service.getTournament(tournamentId);
  }

  /// Get tournament leaderboard. Returns just the entries — callers
  /// that need the server-authoritative current_user_rank should call
  /// the TournamentService directly so they receive the full
  /// TournamentLeaderboardResult.
  Future<List<TournamentParticipant>> getTournamentLeaderboard(
    String tournamentId, {
    int limit = 50,
  }) async {
    final result =
        await _service.getTournamentLeaderboard(tournamentId, limit: limit);
    return result.entries;
  }

  @override
  void dispose() {
    _ttlTimer?.cancel();
    _joinSubscription?.cancel();
    super.dispose();
  }
}

/// Provider for tournaments state
final tournamentsProvider =
    StateNotifierProvider<TournamentsNotifier, TournamentsState>((ref) {
      return TournamentsNotifier(ref);
    });

/// Convenience provider for active tournaments
final activeTournamentsProvider = Provider<List<Tournament>>((ref) {
  return ref.watch(tournamentsProvider).activeTournaments;
});

/// Convenience provider for tournament history
final tournamentHistoryProvider = Provider<List<Tournament>>((ref) {
  return ref.watch(tournamentsProvider).historyTournaments;
});

/// Convenience provider for loading state
final tournamentsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(tournamentsProvider).isLoading;
});

/// Convenience provider for offline state
final tournamentsOfflineProvider = Provider<bool>((ref) {
  return ref.watch(tournamentsProvider).isOffline;
});

/// Provider for tournament leaderboard (family provider by tournament ID)
final tournamentLeaderboardProvider =
    FutureProvider.family<List<TournamentParticipant>, String>((
      ref,
      tournamentId,
    ) async {
      final notifier = ref.watch(tournamentsProvider.notifier);
      return await notifier.getTournamentLeaderboard(tournamentId);
    });
