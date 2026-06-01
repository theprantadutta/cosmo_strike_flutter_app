import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:cosmo_strike_flutter_app/services/app_data_cache.dart';
import 'package:cosmo_strike_flutter_app/services/leaderboard_service.dart';
import 'package:cosmo_strike_flutter_app/providers/providers.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// Leaderboard types
enum LeaderboardType { global, weekly, daily, friends }

/// State for leaderboard data
class LeaderboardState {
  final List<Map<String, dynamic>> entries;
  final Map<String, dynamic>? userRank;
  final bool isLoading;
  final String? error;
  /// When the Drift cache for this board was last successfully refreshed
  /// from the server. Null until the first refresh lands. Used by the
  /// "Updated X ago" chip.
  final DateTime? lastRefreshedAt;

  const LeaderboardState({
    this.entries = const [],
    this.userRank,
    this.isLoading = false,
    this.error,
    this.lastRefreshedAt,
  });

  LeaderboardState copyWith({
    List<Map<String, dynamic>>? entries,
    Map<String, dynamic>? userRank,
    bool? isLoading,
    String? error,
    DateTime? lastRefreshedAt,
  }) {
    return LeaderboardState(
      entries: entries ?? this.entries,
      userRank: userRank ?? this.userRank,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
    );
  }
}

/// Notifier for a specific leaderboard type with TTL-based auto-refresh
class LeaderboardNotifier extends StateNotifier<LeaderboardState> {
  final Ref _ref;
  final LeaderboardService _service;
  final AppDataCache _appCache;
  final LeaderboardType _type;
  Timer? _ttlTimer;

  // TTL varies by leaderboard type
  Duration get _ttl {
    switch (_type) {
      case LeaderboardType.daily:
        return const Duration(seconds: 60); // Daily changes frequently
      case LeaderboardType.weekly:
        return const Duration(minutes: 5);
      case LeaderboardType.global:
        return const Duration(minutes: 15);
      case LeaderboardType.friends:
        return const Duration(minutes: 2);
    }
  }

  /// Pull the matching preloaded leaderboard out of AppDataCache, if any.
  /// Global / Weekly / Daily are preloaded; Friends still falls back to a
  /// network load on first open because it depends on the user's friend
  /// list which isn't fixed at preload time.
  List<Map<String, dynamic>>? _cachedEntries() {
    if (!_appCache.isFullyLoaded) return null;
    switch (_type) {
      case LeaderboardType.global:
        return _appCache.globalLeaderboard;
      case LeaderboardType.weekly:
        return _appCache.weeklyLeaderboard;
      case LeaderboardType.daily:
        return _appCache.dailyLeaderboard;
      case LeaderboardType.friends:
        return null;
    }
  }

  LeaderboardNotifier(this._ref, this._type)
    : _service = LeaderboardService(),
      _appCache = AppDataCache(),
      super(const LeaderboardState(isLoading: true)) {
    _initialize();
  }

  void _initialize() {
    // Use preloaded cache for the first paint when available, then refresh
    // in the background. Removes the empty-state flash users see on
    // global/weekly tabs. Daily and Friends still go through _loadData
    // since they aren't preloaded — those will get skeletons in Commit C.
    final cached = _cachedEntries();
    if (cached != null) {
      state = LeaderboardState(entries: cached, isLoading: false);
      _refreshInBackground();
    } else {
      _loadData();
    }

    // Set up TTL-based refresh
    _startTtlTimer();

    // Listen for connectivity changes - refresh when coming online
    _ref.listen<AsyncValue<bool>>(isOnlineProvider, (previous, next) {
      final wasOffline = previous?.value == false;
      final isNowOnline = next.value == true;
      if (wasOffline && isNowOnline) {
        // Stagger connectivity-restore refreshes to avoid API stampede
        Future.delayed(const Duration(seconds: 1), () => refresh());
      }
    });
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
    // Cache-first paint. Falling through to the in-place refresh below
    // means the spinner only shows when the cache is genuinely empty.
    final cached = await _readCached();
    state = state.copyWith(
      entries: cached,
      isLoading: cached.isEmpty,
      error: null,
      lastRefreshedAt: await _service.getLastRefreshedAt(_boardTypeStr()),
    );

    await _doRefresh();
    final refreshed = await _readCached();
    state = state.copyWith(
      entries: refreshed,
      isLoading: false,
      lastRefreshedAt: await _service.getLastRefreshedAt(_boardTypeStr()),
    );
  }

  /// Silent network refresh — does not toggle isLoading, so the cached
  /// entries stay on screen until the fetch lands.
  Future<void> _refreshInBackground() async {
    try {
      await _doRefresh();
      final entries = await _readCached();
      state = state.copyWith(
        entries: entries,
        lastRefreshedAt: await _service.getLastRefreshedAt(_boardTypeStr()),
      );
    } catch (_) {
      // Background refresh failures stay silent — the cached data is still
      // good enough to show; the next TTL tick will retry.
    }
  }

  Future<void> _doRefresh() async {
    switch (_type) {
      case LeaderboardType.global:
        return _service.refreshGlobal();
      case LeaderboardType.weekly:
        return _service.refreshWeekly();
      case LeaderboardType.daily:
        return _service.refreshDaily();
      case LeaderboardType.friends:
        return _service.refreshFriends();
    }
  }

  Future<List<Map<String, dynamic>>> _readCached({int limit = 50}) async {
    switch (_type) {
      case LeaderboardType.global:
        return _service.getGlobalLeaderboard(limit: limit);
      case LeaderboardType.weekly:
        return _service.getWeeklyLeaderboard(limit: limit);
      case LeaderboardType.daily:
        return _service.getDailyLeaderboard(limit: limit);
      case LeaderboardType.friends:
        return _service.getFriendsLeaderboard(const [], limit: limit);
    }
  }

  String _boardTypeStr() {
    switch (_type) {
      case LeaderboardType.global:
        return 'global';
      case LeaderboardType.weekly:
        return 'weekly';
      case LeaderboardType.daily:
        return 'daily';
      case LeaderboardType.friends:
        return 'friends';
    }
  }

  /// Refresh leaderboard from the server, holding the cached entries
  /// on screen until the network call lands.
  Future<void> refresh() async {
    state = state.copyWith(isLoading: state.entries.isEmpty, error: null);

    try {
      await _doRefresh();
      final entries = await _readCached();
      state = state.copyWith(
        entries: entries,
        isLoading: false,
        lastRefreshedAt: await _service.getLastRefreshedAt(_boardTypeStr()),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to refresh leaderboard',
      );
    }
  }

  /// Get user rank from the leaderboard
  Future<Map<String, dynamic>?> getUserRank(String userId) async {
    return await _service.getUserRank(userId);
  }

  /// Update user rank in state
  void setUserRank(Map<String, dynamic>? rank) {
    state = state.copyWith(userRank: rank);
  }

  @override
  void dispose() {
    _ttlTimer?.cancel();
    super.dispose();
  }
}

/// Family provider for leaderboards by type
final leaderboardProvider =
    StateNotifierProvider.family<
      LeaderboardNotifier,
      LeaderboardState,
      LeaderboardType
    >((ref, type) => LeaderboardNotifier(ref, type));

/// Combined leaderboard state for screens that show multiple types
class CombinedLeaderboardState {
  final List<Map<String, dynamic>> globalEntries;
  final List<Map<String, dynamic>> weeklyEntries;
  final Map<String, dynamic>? userRank;
  final bool isLoadingGlobal;
  final bool isLoadingWeekly;
  final String? globalError;
  final String? weeklyError;
  /// Drift-cache freshness timestamps; null until the first network
  /// refresh lands. Surfaced to the screen so it can show an
  /// "Updated X ago" chip per board.
  final DateTime? globalLastRefreshedAt;
  final DateTime? weeklyLastRefreshedAt;

  const CombinedLeaderboardState({
    this.globalEntries = const [],
    this.weeklyEntries = const [],
    this.userRank,
    this.isLoadingGlobal = false,
    this.isLoadingWeekly = false,
    this.globalError,
    this.weeklyError,
    this.globalLastRefreshedAt,
    this.weeklyLastRefreshedAt,
  });

  bool get isLoading => isLoadingGlobal || isLoadingWeekly;

  CombinedLeaderboardState copyWith({
    List<Map<String, dynamic>>? globalEntries,
    List<Map<String, dynamic>>? weeklyEntries,
    Map<String, dynamic>? userRank,
    bool? isLoadingGlobal,
    bool? isLoadingWeekly,
    String? globalError,
    String? weeklyError,
    DateTime? globalLastRefreshedAt,
    DateTime? weeklyLastRefreshedAt,
  }) {
    return CombinedLeaderboardState(
      globalEntries: globalEntries ?? this.globalEntries,
      weeklyEntries: weeklyEntries ?? this.weeklyEntries,
      userRank: userRank ?? this.userRank,
      isLoadingGlobal: isLoadingGlobal ?? this.isLoadingGlobal,
      isLoadingWeekly: isLoadingWeekly ?? this.isLoadingWeekly,
      globalError: globalError,
      weeklyError: weeklyError,
      globalLastRefreshedAt:
          globalLastRefreshedAt ?? this.globalLastRefreshedAt,
      weeklyLastRefreshedAt:
          weeklyLastRefreshedAt ?? this.weeklyLastRefreshedAt,
    );
  }
}

/// Notifier for combined leaderboard data (for main leaderboard screen)
class CombinedLeaderboardNotifier
    extends StateNotifier<CombinedLeaderboardState> {
  final Ref _ref;
  final LeaderboardService _service;
  final AppDataCache _appCache;
  Timer? _globalTimer;
  Timer? _weeklyTimer;

  static const _globalTtl = Duration(minutes: 15);
  static const _weeklyTtl = Duration(minutes: 5);

  CombinedLeaderboardNotifier(this._ref)
    : _service = LeaderboardService(),
      _appCache = AppDataCache(),
      super(
        const CombinedLeaderboardState(
          isLoadingGlobal: true,
          isLoadingWeekly: true,
        ),
      ) {
    _initialize();
  }

  void _initialize() {
    // Check cache first - use preloaded data if available.
    // Critical: require BOTH fields to be non-null AND non-empty. If the
    // startup preload's network fetch failed, AppDataCache stores empty
    // [] lists — those still pass `!= null` but rendering them would
    // permanently show the empty 'No scores yet' state on first open
    // since the screen has no reason to refetch.
    if (_appCache.isFullyLoaded &&
        _appCache.globalLeaderboard != null &&
        _appCache.globalLeaderboard!.isNotEmpty &&
        _appCache.weeklyLeaderboard != null &&
        _appCache.weeklyLeaderboard!.isNotEmpty) {
      // Use cached data immediately - no loading state!
      state = CombinedLeaderboardState(
        globalEntries: _appCache.globalLeaderboard!,
        weeklyEntries: _appCache.weeklyLeaderboard!,
        isLoadingGlobal: false,
        isLoadingWeekly: false,
      );
      // Refresh in background (silent, no loading indicator)
      _refreshInBackground();
    } else {
      // No useful cache - load fresh from network. _loadData sets
      // isLoading=true, fetches via the service, and updates state with
      // the real data (or error + retry UI).
      _loadData();
    }

    // Set up TTL-based refresh for each type
    _startTtlTimers();

    // Listen for connectivity changes - refresh when coming online
    _ref.listen<AsyncValue<bool>>(isOnlineProvider, (previous, next) {
      final wasOffline = previous?.value == false;
      final isNowOnline = next.value == true;
      if (wasOffline && isNowOnline) {
        // Stagger connectivity-restore refreshes to avoid API stampede
        Future.delayed(const Duration(seconds: 1), () => refresh());
      }
    });
  }

  Future<void> _refreshInBackground() async {
    // Silent refresh - don't set isLoading. Each branch hits the
    // network then re-reads the (post-refresh) cache so the UI sees
    // whatever the server returned (or the previous good cache when
    // the network is down).
    try {
      await Future.wait([
        _service.refreshGlobal(),
        _service.refreshWeekly(),
      ]);
      final results = await Future.wait([
        _service.getGlobalLeaderboard(),
        _service.getWeeklyLeaderboard(),
      ]);
      state = state.copyWith(
        globalEntries: results[0],
        weeklyEntries: results[1],
        globalLastRefreshedAt:
            await _service.getLastRefreshedAt('global'),
        weeklyLastRefreshedAt:
            await _service.getLastRefreshedAt('weekly'),
      );
    } catch (_) {
      // Ignore errors in background refresh
    }
  }

  void _startTtlTimers() {
    _globalTimer?.cancel();
    _weeklyTimer?.cancel();

    _globalTimer = Timer.periodic(_globalTtl, (_) {
      final isOnline = _ref.read(isOnlineSyncProvider);
      if (isOnline) {
        _refreshGlobal();
      }
    });

    _weeklyTimer = Timer.periodic(_weeklyTtl, (_) {
      final isOnline = _ref.read(isOnlineSyncProvider);
      if (isOnline) {
        _refreshWeekly();
      }
    });
  }

  Future<void> _loadData() async {
    // Load both in parallel
    await Future.wait([_loadGlobal(), _loadWeekly()]);

    // Calculate user rank from global leaderboard
    _calculateUserRank();
  }

  Future<void> _loadGlobal() async {
    // The whole body lives in a try/finally so the loading flag ALWAYS
    // resolves to false, regardless of where a throw happens. Earlier
    // version only wrapped the network call; the Drift-cache reads
    // (`getGlobalLeaderboard` / `getLastRefreshedAt`) were outside the
    // try, and if EITHER threw the spinner spun forever because the
    // state never got a chance to update.
    bool cachedWasEmpty = true;
    try {
      List<Map<String, dynamic>> cached = const [];
      try {
        cached = await _service.getGlobalLeaderboard();
      } catch (e) {
        AppLogger.error('Global leaderboard cache read failed', e);
      }
      cachedWasEmpty = cached.isEmpty;

      DateTime? refreshedAt;
      try {
        refreshedAt = await _service.getLastRefreshedAt('global');
      } catch (_) {/* non-fatal */}

      state = state.copyWith(
        globalEntries: cached,
        isLoadingGlobal: cached.isEmpty,
        globalError: null,
        globalLastRefreshedAt: refreshedAt,
      );

      await _service.refreshGlobal();
      final entries = await _service.getGlobalLeaderboard();
      DateTime? refreshedAfter;
      try {
        refreshedAfter = await _service.getLastRefreshedAt('global');
      } catch (_) {/* non-fatal */}
      state = state.copyWith(
        globalEntries: entries,
        isLoadingGlobal: false,
        globalLastRefreshedAt: refreshedAfter,
      );
    } catch (e, st) {
      AppLogger.error('Global leaderboard load failed', e, st);
      state = state.copyWith(
        isLoadingGlobal: false,
        globalError: cachedWasEmpty ? 'Failed to load leaderboard' : null,
      );
    } finally {
      // Defense-in-depth: even if the catch above somehow doesn't fire
      // (re-emit in a future Dart version, etc.), force the flag off so
      // the screen can never get stuck on the spinner.
      if (state.isLoadingGlobal) {
        state = state.copyWith(isLoadingGlobal: false);
      }
    }
  }

  Future<void> _loadWeekly() async {
    bool cachedWasEmpty = true;
    try {
      List<Map<String, dynamic>> cached = const [];
      try {
        cached = await _service.getWeeklyLeaderboard();
      } catch (e) {
        AppLogger.error('Weekly leaderboard cache read failed', e);
      }
      cachedWasEmpty = cached.isEmpty;

      DateTime? refreshedAt;
      try {
        refreshedAt = await _service.getLastRefreshedAt('weekly');
      } catch (_) {/* non-fatal */}

      state = state.copyWith(
        weeklyEntries: cached,
        isLoadingWeekly: cached.isEmpty,
        weeklyError: null,
        weeklyLastRefreshedAt: refreshedAt,
      );

      await _service.refreshWeekly();
      final entries = await _service.getWeeklyLeaderboard();
      DateTime? refreshedAfter;
      try {
        refreshedAfter = await _service.getLastRefreshedAt('weekly');
      } catch (_) {/* non-fatal */}
      state = state.copyWith(
        weeklyEntries: entries,
        isLoadingWeekly: false,
        weeklyLastRefreshedAt: refreshedAfter,
      );
    } catch (e, st) {
      AppLogger.error('Weekly leaderboard load failed', e, st);
      state = state.copyWith(
        isLoadingWeekly: false,
        weeklyError:
            cachedWasEmpty ? 'Failed to load weekly leaderboard' : null,
      );
    } finally {
      if (state.isLoadingWeekly) {
        state = state.copyWith(isLoadingWeekly: false);
      }
    }
  }

  void _calculateUserRank() {
    // This will be called with userId from the screen
  }

  /// Calculate and set user rank for a given user ID
  void calculateUserRankFor(String? userId) {
    if (userId == null || state.globalEntries.isEmpty) {
      state = state.copyWith(userRank: null);
      return;
    }

    for (int i = 0; i < state.globalEntries.length; i++) {
      if (state.globalEntries[i]['uid'] == userId) {
        state = state.copyWith(
          userRank: {
            'rank': i + 1,
            'totalPlayers': state.globalEntries.length,
            'userScore': state.globalEntries[i]['highScore'] ?? 0,
            'percentile':
                ((state.globalEntries.length - i) /
                        state.globalEntries.length *
                        100)
                    .round(),
          },
        );
        return;
      }
    }

    state = state.copyWith(userRank: null);
  }

  /// Refresh all leaderboards
  Future<void> refresh() async {
    await Future.wait([_refreshGlobal(), _refreshWeekly()]);
  }

  Future<void> _refreshGlobal() async {
    state = state.copyWith(
      isLoadingGlobal: state.globalEntries.isEmpty,
      globalError: null,
    );
    try {
      await _service.refreshGlobal();
      final entries = await _service.getGlobalLeaderboard();
      state = state.copyWith(
        globalEntries: entries,
        isLoadingGlobal: false,
        globalLastRefreshedAt: await _service.getLastRefreshedAt('global'),
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingGlobal: false,
        globalError: state.globalEntries.isEmpty
            ? 'Failed to refresh leaderboard'
            : null,
      );
    }
  }

  Future<void> _refreshWeekly() async {
    state = state.copyWith(
      isLoadingWeekly: state.weeklyEntries.isEmpty,
      weeklyError: null,
    );
    try {
      await _service.refreshWeekly();
      final entries = await _service.getWeeklyLeaderboard();
      state = state.copyWith(
        weeklyEntries: entries,
        isLoadingWeekly: false,
        weeklyLastRefreshedAt: await _service.getLastRefreshedAt('weekly'),
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingWeekly: false,
        weeklyError: state.weeklyEntries.isEmpty
            ? 'Failed to refresh weekly leaderboard'
            : null,
      );
    }
  }

  @override
  void dispose() {
    _globalTimer?.cancel();
    _weeklyTimer?.cancel();
    super.dispose();
  }
}

/// Provider for combined leaderboard state (for main leaderboard screen)
final combinedLeaderboardProvider =
    StateNotifierProvider<
      CombinedLeaderboardNotifier,
      CombinedLeaderboardState
    >((ref) => CombinedLeaderboardNotifier(ref));

/// Convenience provider for global leaderboard entries
final globalLeaderboardProvider = Provider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(combinedLeaderboardProvider).globalEntries;
});

/// Convenience provider for weekly leaderboard entries
final weeklyLeaderboardProvider = Provider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(combinedLeaderboardProvider).weeklyEntries;
});

/// Convenience provider for global loading state
final globalLeaderboardLoadingProvider = Provider<bool>((ref) {
  return ref.watch(combinedLeaderboardProvider).isLoadingGlobal;
});

/// Convenience provider for weekly loading state
final weeklyLeaderboardLoadingProvider = Provider<bool>((ref) {
  return ref.watch(combinedLeaderboardProvider).isLoadingWeekly;
});

/// Convenience provider for user rank
final userRankProvider = Provider<Map<String, dynamic>?>((ref) {
  return ref.watch(combinedLeaderboardProvider).userRank;
});
