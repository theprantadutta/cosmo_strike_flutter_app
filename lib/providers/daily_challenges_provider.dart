import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';
import 'package:cosmo_strike_flutter_app/services/app_data_cache.dart';
import 'package:cosmo_strike_flutter_app/services/daily_challenge_service.dart';
import 'package:cosmo_strike_flutter_app/providers/providers.dart';

/// State for daily challenges data
class DailyChallengesState {
  final List<DailyChallenge> challenges;
  final int completedCount;
  final int totalCount;
  final bool allCompleted;
  final int bonusCoins;
  final bool isBonusClaimed;
  final bool isLoading;
  final bool hasUnclaimedRewards;
  final String? error;

  const DailyChallengesState({
    this.challenges = const [],
    this.completedCount = 0,
    this.totalCount = 0,
    this.allCompleted = false,
    this.bonusCoins = 0,
    this.isBonusClaimed = false,
    this.isLoading = false,
    this.hasUnclaimedRewards = false,
    this.error,
  });

  DailyChallengesState copyWith({
    List<DailyChallenge>? challenges,
    int? completedCount,
    int? totalCount,
    bool? allCompleted,
    int? bonusCoins,
    bool? isBonusClaimed,
    bool? isLoading,
    bool? hasUnclaimedRewards,
    String? error,
  }) {
    return DailyChallengesState(
      challenges: challenges ?? this.challenges,
      completedCount: completedCount ?? this.completedCount,
      totalCount: totalCount ?? this.totalCount,
      allCompleted: allCompleted ?? this.allCompleted,
      bonusCoins: bonusCoins ?? this.bonusCoins,
      isBonusClaimed: isBonusClaimed ?? this.isBonusClaimed,
      isLoading: isLoading ?? this.isLoading,
      hasUnclaimedRewards: hasUnclaimedRewards ?? this.hasUnclaimedRewards,
      error: error,
    );
  }
}

/// Notifier for daily challenges with TTL-based auto-refresh
class DailyChallengesNotifier extends StateNotifier<DailyChallengesState> {
  final Ref _ref;
  final DailyChallengeService _service;
  final AppDataCache _appCache;
  Timer? _ttlTimer;
  VoidCallback? _serviceListener;
  String? _lastRefreshDate;

  static const _ttl = Duration(minutes: 30);

  DailyChallengesNotifier(this._ref)
    : _service = DailyChallengeService(),
      _appCache = AppDataCache(),
      super(const DailyChallengesState(isLoading: true)) {
    _initialize();
  }

  void _initialize() {
    // Listen to service changes
    _serviceListener = _onServiceChanged;
    _service.addListener(_serviceListener!);

    // Check cache first - use preloaded data if available
    if (_appCache.isFullyLoaded &&
        _appCache.dailyChallenges != null &&
        _appCache.dailyChallenges!.isNotEmpty) {
      // Use cached data immediately - no loading state!
      final challenges = _appCache.dailyChallenges!;
      state = DailyChallengesState(
        challenges: challenges,
        completedCount: challenges.where((c) => c.isCompleted).length,
        totalCount: challenges.length,
        allCompleted: challenges.every((c) => c.isCompleted),
        isLoading: false,
      );
      // Refresh in background (silent, no loading indicator)
      _refreshInBackground();
    } else {
      // No cache - load normally
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
        Future.delayed(const Duration(seconds: 4), () => refresh());
      }
    });
  }

  Future<void> _refreshInBackground() async {
    // Silent refresh - don't set isLoading
    try {
      // Check if new day started
      final today = DateTime.now().toIso8601String().split('T')[0];
      if (_lastRefreshDate != null && _lastRefreshDate != today) {
        await _service.clearCache();
      }

      await _service.refreshChallenges();
      _lastRefreshDate = today;
      _syncStateFromService();
    } catch (_) {
      // Ignore errors in background refresh
    }
  }

  void _onServiceChanged() {
    _syncStateFromService();
  }

  void _syncStateFromService() {
    state = state.copyWith(
      challenges: _service.challenges,
      completedCount: _service.completedCount,
      totalCount: _service.totalCount,
      allCompleted: _service.allCompleted,
      bonusCoins: _service.bonusCoins,
      isBonusClaimed: _service.isBonusClaimed,
      isLoading: false, // Never propagate loading from background refresh
      hasUnclaimedRewards: _service.hasUnclaimedRewards,
    );
  }

  void _startTtlTimer() {
    _ttlTimer?.cancel();
    _ttlTimer = Timer.periodic(_ttl, (_) async {
      // Detect a midnight rollover during a long-open session so the screen
      // doesn't keep showing yesterday's challenges. refresh() also re-checks
      // the day, but clearing here forces a clean fetch even while offline.
      final today = DateTime.now().toIso8601String().split('T')[0];
      if (_lastRefreshDate != null && _lastRefreshDate != today) {
        await _service.clearCache();
        _syncStateFromService();
      }
      final isOnline = _ref.read(isOnlineSyncProvider);
      if (isOnline) {
        refresh();
      }
    });
  }

  Future<void> _loadData() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      // initialize() hydrates from local Drift cache and FIRES a
      // network refresh in the background — but doesn't await it. On a
      // fresh install or after a stale-cache eviction, this means the
      // service holds an empty list right after initialize returns and
      // the screen renders its empty state.
      //
      // Await refreshChallenges() explicitly so this code path returns
      // with real network data (or a real error). The 8s timeout is
      // generous enough for cold-start networks but bounded so the
      // loading state doesn't hang forever.
      await _service.initialize();
      try {
        await _service
            .refreshChallenges()
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // refresh failed — keep going with whatever the local cache had.
        // _syncStateFromService below picks up cached challenges or an
        // empty list, and the UI can still pull-to-refresh.
      }
      _lastRefreshDate = DateTime.now().toIso8601String().split('T')[0];
      _syncStateFromService();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load daily challenges',
      );
    }
  }

  /// Refresh challenges from the server
  /// Automatically detects day changes and clears cache if needed
  Future<void> refresh() async {
    // Check if new day started - if so, clear cache to get fresh challenges
    final today = DateTime.now().toIso8601String().split('T')[0];
    if (_lastRefreshDate != null && _lastRefreshDate != today) {
      // New day detected - clear cache to force full refresh
      await _service.clearCache();
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      await _service.refreshChallenges();
      _lastRefreshDate = today;
      _syncStateFromService();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to refresh daily challenges',
      );
    }
  }

  /// Update progress for a challenge type (called after game ends)
  Future<void> updateProgress(
    ChallengeType type,
    int value, {
    String? gameMode,
  }) async {
    await _service.updateProgress(type, value, gameMode: gameMode);
    _syncStateFromService();
  }

  /// Claim reward for a specific challenge
  Future<bool> claimReward(String challengeId) async {
    final success = await _service.claimReward(challengeId);
    if (success) {
      _syncStateFromService();
    }
    return success;
  }

  /// Claim all unclaimed rewards
  Future<int> claimAllRewards() async {
    final totalClaimed = await _service.claimAllRewards();
    _syncStateFromService();
    return totalClaimed;
  }

  @override
  void dispose() {
    _ttlTimer?.cancel();
    if (_serviceListener != null) {
      _service.removeListener(_serviceListener!);
    }
    super.dispose();
  }
}

/// Provider for daily challenges state
final dailyChallengesProvider =
    StateNotifierProvider<DailyChallengesNotifier, DailyChallengesState>((ref) {
      return DailyChallengesNotifier(ref);
    });

/// Convenience provider for just the challenges list
final dailyChallengesListProvider = Provider<List<DailyChallenge>>((ref) {
  return ref.watch(dailyChallengesProvider).challenges;
});

/// Convenience provider for loading state
final dailyChallengesLoadingProvider = Provider<bool>((ref) {
  return ref.watch(dailyChallengesProvider).isLoading;
});

/// Convenience provider for unclaimed rewards
final hasUnclaimedRewardsProvider = Provider<bool>((ref) {
  return ref.watch(dailyChallengesProvider).hasUnclaimedRewards;
});

/// Number of completed challenges whose reward hasn't been claimed yet.
/// Watch this to keep badges in sync with claim/state changes.
final unclaimedRewardsCountProvider = Provider<int>((ref) {
  final challenges = ref.watch(dailyChallengesProvider).challenges;
  return challenges.where((c) => c.isCompleted && !c.claimedReward).length;
});
