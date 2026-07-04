import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/models/achievement.dart';
import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';
import 'package:cosmo_strike_flutter_app/models/tournament.dart';
import 'package:cosmo_strike_flutter_app/models/user_profile.dart';
import 'package:cosmo_strike_flutter_app/services/achievement_service.dart';
import 'package:cosmo_strike_flutter_app/services/daily_challenge_service.dart';
import 'package:cosmo_strike_flutter_app/services/leaderboard_service.dart';
import 'package:cosmo_strike_flutter_app/services/social_service.dart';
import 'package:cosmo_strike_flutter_app/services/statistics_service.dart';
import 'package:cosmo_strike_flutter_app/services/progression_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/services/tournament_service.dart';
import 'package:cosmo_strike_flutter_app/services/weekly_quest_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// Centralized data cache that preloads all app data at startup.
///
/// This service loads ALL data concurrently during LoadingScreen so that
/// screens display instantly without loading indicators.
class AppDataCache extends ChangeNotifier {
  static final AppDataCache _instance = AppDataCache._internal();
  factory AppDataCache() => _instance;
  AppDataCache._internal() {
    _wireStatisticsListener();
  }

  // True once we've installed the cross-listener so the singleton can't
  // double-subscribe if [AppDataCache._internal] ever runs twice (e.g.
  // hot-reload tests).
  bool _statisticsListenerWired = false;

  /// Subscribe to StatisticsService.notifyListeners() so any reactive
  /// Drift update there (snapshot apply on first sign-in, end-of-game
  /// writes) refreshes our cached display maps. Without this, the cache
  /// captures whatever StatisticsService had at preload time — which on
  /// fresh install is [GameStatistics.initial()] (zeros), and the
  /// screens stay stuck on zeros even after the cloud restore lands.
  void _wireStatisticsListener() {
    if (_statisticsListenerWired) return;
    _statisticsListenerWired = true;
    StatisticsService().addListener(() {
      // Re-pull and notify our own listeners (statistics screens).
      // Swallow errors to keep the listener alive past a transient
      // disk hiccup.
      unawaited(refreshStatistics());
    });
  }

  // === Cached Data ===

  // Statistics & Profile
  Map<String, dynamic>? _statistics;
  Map<String, dynamic>? _performanceTrends;
  Map<String, dynamic>? _playPatterns;
  List<Achievement>? _recentAchievements;
  List<String>? _replayKeys;

  // Settings
  Map<String, dynamic>? _settingsData;

  // Daily Challenges
  List<DailyChallenge>? _dailyChallenges;

  // Leaderboards
  List<Map<String, dynamic>>? _globalLeaderboard;
  List<Map<String, dynamic>>? _weeklyLeaderboard;
  List<Map<String, dynamic>>? _dailyLeaderboard;
  List<Map<String, dynamic>>? _friendsLeaderboard;

  // Tournaments
  List<Tournament>? _activeTournaments;
  List<Tournament>? _historyTournaments;

  // Social
  List<UserProfile>? _friendsList;
  List<FriendRequest>? _friendRequests;

  bool _isFullyLoaded = false;
  bool _isLoading = false;
  DateTime? _lastRefreshTime;
  static const Duration _refreshThrottle = Duration(seconds: 60);

  // === Public Getters (instant access) ===

  bool get isFullyLoaded => _isFullyLoaded;
  bool get isLoading => _isLoading;
  DateTime? get lastRefreshTime => _lastRefreshTime;

  /// Returns true if data was refreshed recently (within throttle window)
  bool get isRecentlyRefreshed =>
      _lastRefreshTime != null &&
      DateTime.now().difference(_lastRefreshTime!) < _refreshThrottle;

  Map<String, dynamic>? get statistics => _statistics;
  Map<String, dynamic>? get performanceTrends => _performanceTrends;
  Map<String, dynamic>? get playPatterns => _playPatterns;
  List<Achievement>? get recentAchievements => _recentAchievements;
  List<String>? get replayKeys => _replayKeys;
  Map<String, dynamic>? get settingsData => _settingsData;
  List<DailyChallenge>? get dailyChallenges => _dailyChallenges;
  List<Map<String, dynamic>>? get globalLeaderboard => _globalLeaderboard;
  List<Map<String, dynamic>>? get weeklyLeaderboard => _weeklyLeaderboard;
  List<Map<String, dynamic>>? get dailyLeaderboard => _dailyLeaderboard;
  List<Map<String, dynamic>>? get friendsLeaderboard => _friendsLeaderboard;
  List<Tournament>? get activeTournaments => _activeTournaments;
  List<Tournament>? get historyTournaments => _historyTournaments;
  List<UserProfile>? get friendsList => _friendsList;
  List<FriendRequest>? get friendRequests => _friendRequests;

  /// Called by LoadingScreen - loads ALL data concurrently for maximum speed
  Future<void> preloadAll() async {
    if (_isLoading) return;
    _isLoading = true;

    try {
      // Load ALL data in parallel using Future.wait. Network groups use a
      // 4-second per-call timeout; if a backend group is slower than that
      // the loading screen no longer waits for it. The screen-level TTL
      // refresh on each provider will pick up the data later in the
      // background. Trade-off: a flaky connection might leave a cache miss
      // on first paint (skeletons / loading text shown) but the user reaches
      // the home screen up to ~4s sooner per slow endpoint.
      await Future.wait([
        // Group 1: Local data (fast — disk-only after StatisticsService's
        // initialize() was decoupled from cloud sync). _loadStatistics
        // still gets a 4s safety-net timeout in case the underlying disk
        // I/O stalls; we'd rather paint home with stale stats than block
        // the loading screen the way we used to when the backend was
        // unreachable and statsService.initialize chained a 15s API call.
        _loadStatistics().timeout(const Duration(seconds: 4), onTimeout: () {
          AppLogger.warning('AppDataCache: Statistics load timed out');
        }),
        _loadRecentAchievements(),
        _loadReplayKeys(),
        _loadSettingsData(),
        _loadDailyChallenges(),
        _loadWeeklyQuests(),
        _loadPlayerProgress(),

        // Group 2: Network data (with timeout + fallback)
        _loadLeaderboards().timeout(const Duration(seconds: 4), onTimeout: () {
          AppLogger.warning('AppDataCache: Leaderboards timed out');
        }),
        _loadTournaments().timeout(const Duration(seconds: 4), onTimeout: () {
          AppLogger.warning('AppDataCache: Tournaments timed out');
        }),
        _loadSocialData().timeout(const Duration(seconds: 4), onTimeout: () {
          AppLogger.warning('AppDataCache: Social data timed out');
        }),
      ]);

      _isFullyLoaded = true;
      _lastRefreshTime = DateTime.now();
      AppLogger.success('AppDataCache: All data preloaded successfully');
    } catch (e) {
      AppLogger.error('AppDataCache: Error during preload', e);
      // Even if some fail, mark as loaded so screens can still function
      _isFullyLoaded = true;
      _lastRefreshTime = DateTime.now();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // === Private Loaders (all run concurrently) ===

  Future<void> _loadStatistics() async {
    try {
      final statsService = getIt<StatisticsService>();
      await statsService.initialize();
      _statistics = statsService.getDisplayStatistics();
      _performanceTrends = statsService.getPerformanceTrends();
      _playPatterns = statsService.getPlayPatterns();
    } catch (e) {
      if (kDebugMode) print('AppDataCache: Stats load warning: $e');
    }
  }

  Future<void> _loadPlayerProgress() async {
    try {
      await getIt<ProgressionService>().initialize();
    } catch (e) {
      if (kDebugMode) print('AppDataCache: Player progress load warning: $e');
    }
  }

  Future<void> _loadRecentAchievements() async {
    try {
      final service = getIt<AchievementService>();
      // Get the 3 most recently unlocked achievements
      final unlocked = service.getUnlockedAchievements();
      unlocked.sort((a, b) {
        final aTime = a.unlockedAt ?? DateTime(1970);
        final bTime = b.unlockedAt ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });
      _recentAchievements = unlocked.take(3).toList();
    } catch (e) {
      if (kDebugMode) print('AppDataCache: Achievements load warning: $e');
    }
  }

  Future<void> _loadReplayKeys() async {
    try {
      final storageService = getIt<StorageService>();
      _replayKeys = await storageService.getReplayKeys();
    } catch (e) {
      if (kDebugMode) print('AppDataCache: Replays load warning: $e');
    }
  }

  Future<void> _loadSettingsData() async {
    try {
      final storage = getIt<StorageService>();
      // Load all settings concurrently
      final results = await Future.wait([
        storage.getBoardSize(),
        storage.getCrashFeedbackDuration(),
        storage.isDPadEnabled(),
        storage.getDPadPosition(),
        storage.isScreenShakeEnabled(),
      ]);
      _settingsData = {
        'boardSize': results[0],
        'crashFeedbackDuration': results[1],
        'dPadEnabled': results[2],
        'dPadPosition': results[3],
        'screenShakeEnabled': results[4],
      };
    } catch (e) {
      if (kDebugMode) print('AppDataCache: Settings load warning: $e');
    }
  }

  Future<void> _loadDailyChallenges() async {
    try {
      final service = DailyChallengeService();
      await service.initialize();
      // service.initialize() reads from the local Drift cache and fires a
      // network refresh in the background. The refresh wasn't being awaited
      // here, so on a fresh install or after a new day rolled over we'd
      // capture an empty _challenges list and every screen would fall back
      // to its loading path. Explicitly await one refresh attempt with a
      // tight timeout so the cache holds real data on first paint, but
      // never block the loading screen for more than 4 s if the server is
      // slow or unreachable.
      try {
        await service
            .refreshChallenges()
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        // Fall through with whatever the local cache + ongoing background
        // refresh produced. The provider can still skeleton/retry later.
      }
      _dailyChallenges = service.challenges;
    } catch (e) {
      if (kDebugMode) print('AppDataCache: Daily challenges load warning: $e');
    }
  }

  Future<void> _loadWeeklyQuests() async {
    try {
      // Warm the singleton so run-end reportProgressBatch calls have a
      // hydrated quest list (it no-ops on an empty one).
      await WeeklyQuestService().initialize();
    } catch (e) {
      if (kDebugMode) print('AppDataCache: Weekly quests load warning: $e');
    }
  }

  Future<void> _loadLeaderboards() async {
    // Critical: per-list try/catch leaves the field NULL on fetch failure
    // (not []). Per-screen providers distinguish 'preload got data' from
    // 'preload failed' by checking `!= null`, and storing [] disguises
    // failure as success — which is why the leaderboard tabs were
    // showing 'No scores yet' permanently on a slow first launch.
    //
    // Parallel-execute the three independent fetches so the wall-clock
    // cost is the SLOWEST of the three, not their sum. Previously they
    // ran serially under a 4-second outer timeout, giving each call only
    // ~1.3s budget — borderline on every connection and the source of
    // the "Leaderboards timed out" warning users saw on every launch.
    final service = LeaderboardService();
    await Future.wait([
      _safeLoad(
        () async => _globalLeaderboard =
            await service.getGlobalLeaderboard(limit: 100),
        'Global leaderboard',
      ),
      _safeLoad(
        () async => _weeklyLeaderboard =
            await service.getWeeklyLeaderboard(limit: 100),
        'Weekly leaderboard',
      ),
      _safeLoad(
        () async => _dailyLeaderboard =
            await service.getDailyLeaderboard(limit: 100),
        'Daily leaderboard',
      ),
    ]);
    // Friends leaderboard requires friend IDs and is loaded on-demand.
    _friendsLeaderboard = [];
  }

  /// Run a per-list loader, swallowing exceptions so one failure in a
  /// parallel batch doesn't tank the whole Future.wait. Leaves the
  /// matching cache field NULL on error so the per-screen provider
  /// re-fetches cleanly.
  Future<void> _safeLoad(Future<void> Function() load, String label) async {
    try {
      await load();
    } catch (e) {
      if (kDebugMode) print('AppDataCache: $label load failed: $e');
    }
  }

  Future<void> _loadTournaments() async {
    // Same pattern as leaderboards: parallel fetches under the outer
    // 4s timeout so the budget covers the slowest call, not the sum.
    // Per-list try/catch ensures one failure doesn't poison the other.
    final service = TournamentService();
    await Future.wait([
      _safeLoad(
        () async => _activeTournaments = await service.getActiveTournaments(),
        'Active tournaments',
      ),
      _safeLoad(
        () async => _historyTournaments = await service.getTournamentHistory(),
        'Tournament history',
      ),
    ]);
  }

  Future<void> _loadSocialData() async {
    final service = SocialService();
    await Future.wait([
      _safeLoad(
        () async => _friendsList = await service.getFriends(),
        'Friends',
      ),
      _safeLoad(
        () async => _friendRequests = await service.getFriendRequests(),
        'Friend requests',
      ),
    ]);
  }

  /// Background refresh - call when entering a screen for silent updates.
  /// Throttled to avoid redundant refreshes within [_refreshThrottle].
  Future<void> refreshInBackground() async {
    // Skip if we just refreshed recently
    if (isRecentlyRefreshed) return;

    // Don't block - run in background
    Future.microtask(() async {
      try {
        await Future.wait([
          _loadStatistics(),
          _loadRecentAchievements(),
          _loadLeaderboards(),
          _loadTournaments(),
          _loadSocialData(),
          _loadDailyChallenges(),
        ]);
        _lastRefreshTime = DateTime.now();
        notifyListeners();
      } catch (e) {
        if (kDebugMode) print('AppDataCache: Background refresh warning: $e');
      }
    });
  }

  /// Refresh specific data types
  Future<void> refreshStatistics() async {
    await _loadStatistics();
    notifyListeners();
  }

  Future<void> refreshAchievements() async {
    await _loadRecentAchievements();
    notifyListeners();
  }

  Future<void> refreshLeaderboards() async {
    await _loadLeaderboards();
    notifyListeners();
  }

  Future<void> refreshTournaments() async {
    await _loadTournaments();
    notifyListeners();
  }

  Future<void> refreshSocial() async {
    await _loadSocialData();
    notifyListeners();
  }

  Future<void> refreshDailyChallenges() async {
    await _loadDailyChallenges();
    notifyListeners();
  }

  Future<void> refreshSettings() async {
    await _loadSettingsData();
    notifyListeners();
  }

  /// Clear all cached data
  void clearCache() {
    _statistics = null;
    _performanceTrends = null;
    _playPatterns = null;
    _recentAchievements = null;
    _replayKeys = null;
    _settingsData = null;
    _dailyChallenges = null;
    _globalLeaderboard = null;
    _weeklyLeaderboard = null;
    _friendsLeaderboard = null;
    _activeTournaments = null;
    _historyTournaments = null;
    _friendsList = null;
    _friendRequests = null;
    _isFullyLoaded = false;
    notifyListeners();
  }
}
