import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart' as db;
import 'package:cosmo_strike_flutter_app/models/game_statistics.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/services/data_sync_service.dart';
import 'package:cosmo_strike_flutter_app/services/unified_user_service.dart';

class StatisticsService extends ChangeNotifier {
  static StatisticsService? _instance;
  final StorageService _storageService = StorageService();
  final DataSyncService _syncService = DataSyncService();
  final UnifiedUserService _userService = UnifiedUserService();

  GameStatistics _currentStatistics = GameStatistics.initial();
  bool _initialized = false;

  /// The raw JSON the last applied [_currentStatistics] was parsed from.
  /// Used to skip redundant notifies when the Drift watch re-emits an
  /// identical row (GameStatistics has no value equality, so an object
  /// `identical` check never short-circuits — the parse always makes a
  /// fresh instance).
  String? _lastStatsJson;

  /// Drift watch keeps [_currentStatistics] in lock-step with the
  /// `statistics` row. Critical for the first-sign-in flow: the
  /// snapshot apply writes the cloud stats to Drift AFTER this
  /// service's initial _loadFromDrift saw an empty row, and without a
  /// watch the in-memory state would stay at [GameStatistics.initial()]
  /// (= zeros) for the rest of the session.
  StreamSubscription<db.Statistic?>? _statisticsWatch;

  StatisticsService._internal();

  factory StatisticsService() {
    _instance ??= StatisticsService._internal();
    return _instance!;
  }

  GameStatistics get statistics => _currentStatistics;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Hydrate from Drift (the single source of truth for stats).
      await _loadFromDrift();
      _wireDriftWatch();

      // Mark ready as soon as local data is available so callers that
      // await initialize() (GameSettingsCubit, AppDataCache, etc.) are
      // never blocked on a network round-trip. Previously this was set
      // AFTER _syncWithCloud, which made the whole offline-first chain
      // wait up to ~30s on backend timeouts when the server was down —
      // turning a clean local-only state into a "high score reads 0"
      // bug for the full timeout window.
      _initialized = true;

      // Cloud sync runs in the background. Local data is already usable;
      // any server-side aggregates land later and mutate _currentStatistics
      // in place. Listeners that need a refresh can call
      // [getDisplayStatistics] again or subscribe via AppDataCache.
      if (_userService.isSignedIn) {
        unawaited(_syncWithCloud());
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing statistics service: $e');
      }
      // Mark ready anyway — UI gets [GameStatistics.initial()] and the
      // next gameplay write or cloud snapshot apply will populate Drift.
      _initialized = true;
    }
  }

  /// Subscribe to the Drift `statistics` singleton so any write
  /// (snapshot apply on first sign-in, gameplay end, debug reset)
  /// reactively refreshes [_currentStatistics] and notifies listeners.
  /// AppDataCache subscribes to this service so the screens auto-update
  /// instead of capturing a stale [GameStatistics.initial()] snapshot.
  void _wireDriftWatch() {
    _statisticsWatch?.cancel();
    final dao = _storageService.gameDao;
    _statisticsWatch = dao.watchStatistics().listen((row) {
      if (row == null) {
        // Drift was wiped or never populated — keep the current
        // in-memory state. Avoid emitting an all-zeros snapshot just
        // because the row hasn't landed yet; the snapshot apply will
        // emit a real row a moment later.
        return;
      }
      if (row.modelJson == _lastStatsJson) return;
      GameStatistics parsed;
      try {
        parsed = GameStatistics.fromJsonString(row.modelJson);
      } catch (_) {
        return;
      }
      _currentStatistics = parsed;
      _lastStatsJson = row.modelJson;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _statisticsWatch?.cancel();
    _statisticsWatch = null;
    super.dispose();
  }

  /// Hydrate [_currentStatistics] from the Drift `statistics` singleton.
  ///
  /// **Empty row is a valid initial state** — it means "no stats yet
  /// on this device." We DO NOT write anything back to Drift here.
  /// Earlier builds had a "backfill empty row" branch that initialized
  /// Drift with [GameStatistics.initial()] (zeros) and enqueued a
  /// statistics outbox push, which on fresh-install + cloud-restore
  /// flows raced the snapshot pull and wiped the server's real stats.
  /// The new contract: only [recordGameResult] and the snapshot apply
  /// in `SyncEngine._applyCloudSnapshot` ever write a row.
  Future<void> _loadFromDrift() async {
    try {
      final row = await _storageService.gameDao.getStatistics();
      if (row != null) {
        _currentStatistics = GameStatistics.fromJsonString(row.modelJson);
      } else {
        _currentStatistics = GameStatistics.initial();
      }

      // Reconcile the stats-model's highScore with the canonical
      // GameSettings.highScore (Drift singleton). When the two
      // disagree, the higher value wins: a personal best earned in
      // gameplay always lives in GameSettings.highScore via the
      // never-decrease guard, and we mirror it into the stats model
      // so downstream UIs reading either source agree.
      final separateHighScore = await _storageService.getHighScore();
      final statsHighScore = _currentStatistics.highScore;

      if (separateHighScore != statsHighScore) {
        final syncedHighScore = separateHighScore > statsHighScore
            ? separateHighScore
            : statsHighScore;

        if (separateHighScore > statsHighScore) {
          _currentStatistics =
              _currentStatistics.withHighScore(syncedHighScore);
          // Only persist if we actually had a row to begin with; an
          // empty Drift row shouldn't be created just to mirror the
          // canonical high score — that would re-introduce the empty
          // push bug.
          if (row != null) await _persistToDrift();
        }

        if (statsHighScore > separateHighScore) {
          await _storageService.saveHighScore(syncedHighScore);
        }

        if (kDebugMode) {
          print(
            'High score synced: stats=$statsHighScore, '
            'separate=$separateHighScore -> $syncedHighScore',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading statistics from Drift: $e');
      }
      _currentStatistics = GameStatistics.initial();
    }
  }

  /// No-op in the offline-first build — statistics live entirely in
  /// Drift. Kept as a method so existing callers (initialize,
  /// resetStatistics, forceSync) compile unchanged.
  Future<void> _syncWithCloud() async {}

  /// Overlay server-aggregated cumulative fields onto a local GameStatistics
  /// snapshot. Dormant in the offline-first build but retained in case the
  /// server merge path is revived.
  // ignore: unused_element
  GameStatistics _applyServerAggregates(
    GameStatistics local,
    Map<String, dynamic> server,
  ) {
    final serverGames = (server['totalGamesPlayed'] ?? 0) as int;
    if (serverGames <= 0) return local;

    final serverScore = (server['totalScore'] ?? 0) as int;
    final serverHigh = (server['highScore'] ?? 0) as int;
    final serverTime = (server['totalPlayTimeSeconds'] ?? 0) as int;
    final serverFoods = (server['totalFoodsEaten'] ?? 0) as int;
    // gamesSurvived30s only present after Phase 6a backend deploy. Older
    // backends won't include the field; fall back to the local count so
    // we don't zero out the survival numerator pre-deploy.
    final serverSurvived = (server['gamesSurvived30s'] is int)
        ? server['gamesSurvived30s'] as int
        : local.gamesSurvived30s;

    // Take max() of server vs local for each cumulative field so a brief
    // backend lag (e.g. local just played a game whose score-submit hasn't
    // landed yet) doesn't visibly decrement a number on the screen.
    return GameStatistics(
      totalGamesPlayed:
          serverGames > local.totalGamesPlayed ? serverGames : local.totalGamesPlayed,
      totalScore: serverScore > local.totalScore ? serverScore : local.totalScore,
      highScore: serverHigh > local.highScore ? serverHigh : local.highScore,
      totalGameTime:
          serverTime > local.totalGameTime ? serverTime : local.totalGameTime,
      averageGameTime: local.averageGameTime,
      totalFoodConsumed: serverFoods > local.totalFoodConsumed
          ? serverFoods
          : local.totalFoodConsumed,
      foodTypeCount: local.foodTypeCount,
      totalFoodPoints: local.totalFoodPoints,
      totalPowerUpsCollected: local.totalPowerUpsCollected,
      powerUpTypeCount: local.powerUpTypeCount,
      totalPowerUpTime: local.totalPowerUpTime,
      longestSurvivalTime: local.longestSurvivalTime,
      highestLevel: local.highestLevel,
      totalLevelsGained: local.totalLevelsGained,
      averageScore: local.averageScore,
      gamesSurvived30s: serverSurvived > local.gamesSurvived30s
          ? serverSurvived
          : local.gamesSurvived30s,
      wallCollisions: local.wallCollisions,
      selfCollisions: local.selfCollisions,
      totalCollisions: local.totalCollisions,
      collisionRate: local.collisionRate,
      currentWinStreak: local.currentWinStreak,
      longestWinStreak: local.longestWinStreak,
      gamesWithoutWallHit: local.gamesWithoutWallHit,
      perfectGames: local.perfectGames,
      totalSessions: local.totalSessions,
      averageGamesPerSession: local.averageGamesPerSession,
      lastPlayedDate: local.lastPlayedDate,
      firstPlayedDate: local.firstPlayedDate,
      recentScores: local.recentScores,
      dailyPlayTime: local.dailyPlayTime,
      achievementsUnlocked: local.achievementsUnlocked,
      totalAchievements: local.totalAchievements,
      achievementProgress: local.achievementProgress,
    );
  }

  /// Merge two GameStatistics by taking max values for each field.
  /// Dormant in the offline-first build but kept in case cloud merge
  /// is revived.
  // ignore: unused_element
  GameStatistics _mergeStatistics(
    GameStatistics a,
    GameStatistics b,
  ) {
    // Cumulative fields: take max (both devices accumulate independently)
    final totalGamesPlayed = max(a.totalGamesPlayed, b.totalGamesPlayed);
    final totalScore = max(a.totalScore, b.totalScore);
    final totalGameTime = max(a.totalGameTime, b.totalGameTime);
    final totalFoodConsumed = max(a.totalFoodConsumed, b.totalFoodConsumed);
    final totalFoodPoints = max(a.totalFoodPoints, b.totalFoodPoints);
    final totalPowerUpsCollected = max(
      a.totalPowerUpsCollected,
      b.totalPowerUpsCollected,
    );
    final totalPowerUpTime = max(a.totalPowerUpTime, b.totalPowerUpTime);
    final totalLevelsGained = max(a.totalLevelsGained, b.totalLevelsGained);
    final wallCollisions = max(a.wallCollisions, b.wallCollisions);
    final selfCollisions = max(a.selfCollisions, b.selfCollisions);
    final totalCollisions = wallCollisions + selfCollisions;
    final totalSessions = max(a.totalSessions, b.totalSessions);
    final achievementsUnlocked = max(
      a.achievementsUnlocked,
      b.achievementsUnlocked,
    );
    final perfectGames = max(a.perfectGames, b.perfectGames);
    final gamesWithoutWallHit = max(
      a.gamesWithoutWallHit,
      b.gamesWithoutWallHit,
    );

    // Record fields: take max
    final highScore = max(a.highScore, b.highScore);
    final longestSurvivalTime = max(
      a.longestSurvivalTime,
      b.longestSurvivalTime,
    );
    final highestLevel = max(a.highestLevel, b.highestLevel);
    final longestWinStreak = max(a.longestWinStreak, b.longestWinStreak);
    final currentWinStreak = max(a.currentWinStreak, b.currentWinStreak);

    // Maps: merge by taking max per key
    final foodTypeCount = _mergeMaps(a.foodTypeCount, b.foodTypeCount);
    final powerUpTypeCount = _mergeMaps(a.powerUpTypeCount, b.powerUpTypeCount);
    final dailyPlayTime = _mergeMaps(a.dailyPlayTime, b.dailyPlayTime);

    // Lists: take whichever is longer (more history)
    final recentScores = a.recentScores.length >= b.recentScores.length
        ? a.recentScores
        : b.recentScores;

    // Dates: earliest first, latest last
    final firstPlayedDate = _earlierDate(a.firstPlayedDate, b.firstPlayedDate);
    final lastPlayedDate = _laterDate(a.lastPlayedDate, b.lastPlayedDate);

    // Derived fields: recalculate from merged base values
    final averageScore = totalGamesPlayed > 0
        ? totalScore / totalGamesPlayed
        : 0.0;
    final averageGameTime = totalGamesPlayed > 0
        ? (totalGameTime / totalGamesPlayed).round()
        : 0;
    final collisionRate = totalGamesPlayed > 0
        ? totalCollisions / totalGamesPlayed
        : 0.0;
    // survivalRate is now a derived getter on GameStatistics, so the
    // merged value comes from the merged gamesSurvived30s counter below.
    final gamesSurvived30s = max(a.gamesSurvived30s, b.gamesSurvived30s);
    final averageGamesPerSession = totalSessions > 0
        ? (totalGamesPlayed / totalSessions).round()
        : totalGamesPlayed;
    final totalAchievements = max(a.totalAchievements, b.totalAchievements);
    final achievementProgress = totalAchievements > 0
        ? achievementsUnlocked / totalAchievements
        : 0.0;

    return GameStatistics(
      totalGamesPlayed: totalGamesPlayed,
      totalScore: totalScore,
      highScore: highScore,
      totalGameTime: totalGameTime,
      averageGameTime: averageGameTime,
      totalFoodConsumed: totalFoodConsumed,
      foodTypeCount: foodTypeCount,
      totalFoodPoints: totalFoodPoints,
      totalPowerUpsCollected: totalPowerUpsCollected,
      powerUpTypeCount: powerUpTypeCount,
      totalPowerUpTime: totalPowerUpTime,
      longestSurvivalTime: longestSurvivalTime,
      highestLevel: highestLevel,
      totalLevelsGained: totalLevelsGained,
      averageScore: averageScore,
      gamesSurvived30s: gamesSurvived30s,
      wallCollisions: wallCollisions,
      selfCollisions: selfCollisions,
      totalCollisions: totalCollisions,
      collisionRate: collisionRate,
      currentWinStreak: currentWinStreak,
      longestWinStreak: longestWinStreak,
      gamesWithoutWallHit: gamesWithoutWallHit,
      perfectGames: perfectGames,
      totalSessions: totalSessions,
      averageGamesPerSession: averageGamesPerSession,
      lastPlayedDate: lastPlayedDate,
      firstPlayedDate: firstPlayedDate,
      recentScores: recentScores,
      dailyPlayTime: dailyPlayTime,
      achievementsUnlocked: achievementsUnlocked,
      totalAchievements: totalAchievements,
      achievementProgress: achievementProgress,
    );
  }

  /// Merge two maps by taking the max value for each key.
  Map<String, int> _mergeMaps(Map<String, int> a, Map<String, int> b) {
    final merged = Map<String, int>.from(a);
    for (final entry in b.entries) {
      merged[entry.key] = max(merged[entry.key] ?? 0, entry.value);
    }
    return merged;
  }

  /// Return the earlier of two nullable DateTimes.
  DateTime? _earlierDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
  }

  /// Return the later of two nullable DateTimes.
  DateTime? _laterDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  /// No-op in the offline-first build — stats live in Drift, and the
  /// `statistics` sync handler was removed when the backend endpoint
  /// went away. Earlier this still queued an item that immediately
  /// short-circuited through the default-true sync case, producing
  /// misleading "Synced: statistics" log noise on every game-end.
  Future<void> _uploadToCloud() async {}

  Future<void> recordGameResult({
    required int score,
    required int gameTime,
    required int level,
    required int foodConsumed,
    required Map<String, int> foodTypes,
    required int foodPoints,
    required int powerUpsCollected,
    required Map<String, int> powerUpTypes,
    required int powerUpTime,
    required int wallHits,
    required int selfHits,
    required bool isPerfectGame,
    required List<String> unlockedAchievements,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    // Update statistics with new game data
    _currentStatistics = _currentStatistics.updateWithGameResult(
      score: score,
      gameTime: gameTime,
      level: level,
      foodConsumed: foodConsumed,
      foodTypes: foodTypes,
      foodPoints: foodPoints,
      powerUpsCollected: powerUpsCollected,
      powerUpTypes: powerUpTypes,
      powerUpTime: powerUpTime,
      wallHits: wallHits,
      selfHits: selfHits,
      isPerfectGame: isPerfectGame,
      unlockedAchievements: unlockedAchievements,
    );

    // Save locally
    await _persistToDrift();

    // Upload to cloud if signed in
    if (_userService.isSignedIn) {
      await _uploadToCloud();
    }
  }

  Future<void> _persistToDrift() async {
    try {
      // Single source of truth for high score: GameSettings.highScore.
      // Mirror our in-memory model's highScore UP to settings first
      // (saveHighScore is never-decrease, so this only takes effect
      // when stats has the higher number), then pull back the canonical
      // value so the JSON we serialize agrees with GameSettings. Without
      // this reconciliation Statistics.modelJson.highScore and
      // GameSettings.highScore could drift apart — game_cubit writes to
      // settings on a new high, this service writes to the stats model
      // on every game-end, and if one path executed without the other
      // the two locations diverged.
      await _storageService.saveHighScore(_currentStatistics.highScore);
      final canonical = await _storageService.getHighScore();
      if (canonical != _currentStatistics.highScore) {
        _currentStatistics = _currentStatistics.withHighScore(canonical);
      }

      // Drift's statistics row is the only persistent store of the full
      // stats blob; SyncEngine reads it and pushes to /sync/statistics.
      // updateStatisticsFromJson enqueues an outbox row in the same
      // transaction, so the next drain ships the latest model JSON.
      final json = _currentStatistics.toJsonString();
      await _storageService.saveStatistics(json);
    } catch (e) {
      if (kDebugMode) {
        print('Error persisting statistics to Drift: $e');
      }
    }
  }

  Future<void> startNewSession() async {
    if (!_initialized) {
      await initialize();
    }

    _currentStatistics = _currentStatistics.startNewSession();
    await _persistToDrift();

    if (_userService.isSignedIn) {
      await _uploadToCloud();
    }
  }

  // Get specific statistics for UI display
  Map<String, dynamic> getDisplayStatistics() {
    return {
      'totalGames': _currentStatistics.totalGamesPlayed,
      'highScore': _currentStatistics.highScore,
      // Use _formatDuration (already used for longestSurvival) instead of
      // the rounded integer hours so users with sub-hour totals don't see
      // a confusing '0h'. The formatter emits 'Xs' / 'Xm Ys' / 'Xh Ym'
      // depending on magnitude; the screen drops the inline 'h' suffix.
      'totalPlayTime': _formatDuration(_currentStatistics.totalGameTime),
      'averageScore': _currentStatistics.averageScore.round(),
      'totalFood': _currentStatistics.totalFoodConsumed,
      'totalPowerUps': _currentStatistics.totalPowerUpsCollected,
      'longestSurvival': _formatDuration(
        _currentStatistics.longestSurvivalTime,
      ),
      'highestLevel': _currentStatistics.highestLevel,
      'winStreak': _currentStatistics.currentWinStreak,
      'longestStreak': _currentStatistics.longestWinStreak,
      'survivalRate': '${(_currentStatistics.survivalRate * 100).round()}%',
      'perfectGames': _currentStatistics.perfectGames,
      'favoriteFood': _currentStatistics.favoriteFood,
      'favoritePowerUp': _currentStatistics.favoritePowerUp,
      'achievementProgress':
          '${(_currentStatistics.achievementProgress * 100).round()}%',
      'recentScores': _currentStatistics.recentScores,
      'foodBreakdown': _currentStatistics.foodTypeCount,
      'powerUpBreakdown': _currentStatistics.powerUpTypeCount,
      'collisionStats': {
        'wall': _currentStatistics.wallCollisions,
        'self': _currentStatistics.selfCollisions,
        'total': _currentStatistics.totalCollisions,
      },
    };
  }

  // Get performance trends for charts
  Map<String, dynamic> getPerformanceTrends() {
    final recentScores = _currentStatistics.recentScores;
    final trend = _calculateTrend(recentScores);

    return {
      'recentScores': recentScores,
      'trend': trend, // 'improving', 'declining', 'stable'
      'averageRecentScore': recentScores.isNotEmpty
          ? (recentScores.reduce((a, b) => a + b) / recentScores.length).round()
          : 0,
      'bestRecentScore': recentScores.isNotEmpty
          ? recentScores.reduce((a, b) => a > b ? a : b)
          : 0,
      'worstRecentScore': recentScores.isNotEmpty
          ? recentScores.reduce((a, b) => a < b ? a : b)
          : 0,
    };
  }

  String _calculateTrend(List<int> scores) {
    if (scores.length < 3) return 'stable';

    final recent = scores.sublist(scores.length - 3);
    final older = scores.length >= 6
        ? scores.sublist(scores.length - 6, scores.length - 3)
        : scores.sublist(0, scores.length - 3);

    final recentAvg = recent.reduce((a, b) => a + b) / recent.length;
    final olderAvg = older.reduce((a, b) => a + b) / older.length;

    // Guard against divide-by-zero. If the older window averaged 0 (a
    // fresh account where the player scored 0 in their first few games)
    // any later non-zero score would yield Infinity here and always
    // return 'improving'. With olderAvg == 0 we just compare recentAvg
    // directly to 0.
    if (olderAvg == 0) {
      return recentAvg > 0 ? 'improving' : 'stable';
    }

    const threshold = 0.1; // 10% change threshold

    if ((recentAvg - olderAvg) / olderAvg > threshold) {
      return 'improving';
    } else if ((olderAvg - recentAvg) / olderAvg > threshold) {
      return 'declining';
    } else {
      return 'stable';
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      final remainingSeconds = seconds % 60;
      return '${minutes}m ${remainingSeconds}s';
    } else {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return '${hours}h ${minutes}m';
    }
  }

  // Get daily/weekly play patterns for charts
  Map<String, dynamic> getPlayPatterns() {
    final dailyPlayTime = _currentStatistics.dailyPlayTime;

    // Get last 7 days
    final now = DateTime.now();
    final last7Days = <String, int>{};

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final key = '${date.year}-${date.month}-${date.day}';
      last7Days[_formatDateForChart(date)] = dailyPlayTime[key] ?? 0;
    }

    return {
      'dailyPlayTime': last7Days,
      'totalWeeklyTime': last7Days.values.reduce((a, b) => a + b),
      'averageDailyTime': (last7Days.values.reduce((a, b) => a + b) / 7)
          .round(),
      'mostActiveDay': _getMostActiveDay(last7Days),
    };
  }

  String _formatDateForChart(DateTime date) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[date.weekday % 7];
  }

  String _getMostActiveDay(Map<String, int> dailyData) {
    if (dailyData.isEmpty) return 'None';

    final sortedDays = dailyData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedDays.first.key;
  }

  // Reset statistics (for testing or user request)
  Future<void> resetStatistics() async {
    _currentStatistics = GameStatistics.initial();
    await _persistToDrift();

    // Reset high score in storage. Has to go through the explicit
    // resetHighScore path — saveHighScore now refuses any write that
    // would decrease the stored value, by design.
    await _storageService.resetHighScore();

    // No backend reset call in the offline-first build — local state
    // is authoritative.
  }

  // Force sync with cloud (for manual sync)
  Future<bool> forceSync() async {
    if (!_userService.isSignedIn) return false;

    try {
      await _uploadToCloud();
      await _syncService.forceSyncNow();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error in force sync: $e');
      }
      return false;
    }
  }
}
