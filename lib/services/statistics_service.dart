import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart' as db;
import 'package:cosmo_strike_flutter_app/models/game_statistics.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/services/data_sync_service.dart';
import 'package:cosmo_strike_flutter_app/services/unified_user_service.dart';

class StatisticsService extends ChangeNotifier {
  static StatisticsService? _instance;
  final StorageService _storageService = StorageService();
  final DataSyncService _syncService = DataSyncService();
  final UnifiedUserService _userService = UnifiedUserService();
  final ApiService _apiService = ApiService();

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

  /// Fold a finished shmup run into the lifetime stats. Offline-first: writes
  /// to Drift (which enqueues the statistics sync) and notifies listeners so
  /// the cached display map + stats screen refresh immediately.
  Future<void> recordGameResult({
    required int score,
    required int durationSeconds,
    required int stageReached,
    required int waveReached,
    required int enemiesKilled,
    required int bossesKilled,
    required int levelsCleared,
    int missilesFired = 0,
    int revivesUsed = 0,
    bool victory = false,
    int noHitClears = 0,
    int maxCombo = 0,
    int grazeCount = 0,
    String gameMode = 'classic',
  }) async {
    if (!_initialized) {
      await initialize();
    }

    _currentStatistics = _currentStatistics.updateWithGameResult(
      score: score,
      durationSeconds: durationSeconds,
      stageReached: stageReached,
      waveReached: waveReached,
      enemiesKilled: enemiesKilled,
      bossesKilled: bossesKilled,
      levelsCleared: levelsCleared,
      missilesFired: missilesFired,
      revivesUsed: revivesUsed,
      victory: victory,
      noHitClears: noHitClears,
      maxCombo: maxCombo,
      grazeCount: grazeCount,
      gameMode: gameMode,
    );

    await _persistToDrift();
    notifyListeners();
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
      'totalPlayTime': _formatDuration(_currentStatistics.totalPlayTimeSeconds),
      'averageScore': _currentStatistics.averageScore.round(),
      'longestSurvival': _formatDuration(
        _currentStatistics.longestSurvivalSeconds,
      ),
      'highestStage': _currentStatistics.highestStageReached,
      'highestWave': _currentStatistics.highestWaveReached,
      'enemiesKilled': _currentStatistics.totalEnemiesKilled,
      'bossesKilled': _currentStatistics.totalBossesKilled,
      'stagesCleared': _currentStatistics.totalLevelsCleared,
      'victories': _currentStatistics.victories,
      'bestCombo': _currentStatistics.bestCombo,
      'noHitClears': _currentStatistics.noHitClears,
      'winStreak': _currentStatistics.currentWinStreak,
      'longestStreak': _currentStatistics.longestWinStreak,
      'survivalRate': '${(_currentStatistics.survivalRate * 100).round()}%',
      'favoriteMode': _currentStatistics.favoriteMode,
      'achievementProgress':
          '${(_currentStatistics.achievementProgress * 100).round()}%',
      'recentScores': _currentStatistics.recentScores,
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
      final key = GameStatistics.dayKey(date);
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

  /// Wipe all statistics, high score, and leaderboard scores.
  ///
  /// This is deliberately NOT offline-first. Everything else in the app
  /// merges UPWARD (the statistics blob MAX-folds, the high score is
  /// never-decrease, scores are absorbing), so a purely-local reset would
  /// be undone by the next sync. The wipe only sticks if the SERVER clears
  /// its mirror first — so we require connectivity, await the backend reset,
  /// and only touch local state once it succeeds.
  ///
  /// Returns true on a full wipe, false if offline / the backend rejected it
  /// (local state left intact so the user can retry once connected).
  Future<bool> resetStatistics() async {
    if (!_initialized) {
      await initialize();
    }

    // A guest with no account has no server mirror to clear; there's nothing
    // that could resurrect the data, so a local wipe is authoritative.
    final signedIn = _userService.isSignedIn;
    if (signedIn) {
      final outcome = await _apiService.resetStatisticsRemote();
      if (!outcome.isSuccess) return false;
    }

    // Purge pending outbox rows that would otherwise resurrect the wiped
    // data on the next drain: game_score (leaderboard), the statistics blob,
    // and settings (carries the high score). The zeroed re-push enqueued by
    // _persistToDrift below replaces the statistics row we just removed.
    try {
      final syncDao = getIt<db.AppDatabase>().syncDao;
      await syncDao.removeSyncItemsByType(db.SyncDataType.gameScore);
      await syncDao.removeSyncItemsByType(db.SyncDataType.statistics);
      await syncDao.removeSyncItemsByType(db.SyncDataType.settings);
    } catch (_) {}

    // Reset high score FIRST (resetHighScore bypasses the never-decrease
    // guard), so the high-score reconciliation inside _persistToDrift sees
    // the canonical 0 instead of restoring the old value back onto the model.
    await _storageService.resetHighScore();

    _currentStatistics = GameStatistics.initial();
    await _persistToDrift();
    notifyListeners();
    return true;
  }

  // Force sync with cloud (for manual sync)
  Future<bool> forceSync() async {
    if (!_userService.isSignedIn) return false;

    try {
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
