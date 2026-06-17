import 'dart:convert';

/// Lifetime player statistics for the Cosmo Strike shoot-'em-up.
///
/// Cumulative counters + maxes are folded in [updateWithGameResult] from each
/// run's `GameResult`. Rates/averages are getters (never stored), so they can't
/// drift from the counters. The whole thing serialises to the `Statistics`
/// Drift row's `modelJson` blob (the authoritative store) and to the backend
/// `UserStatistics` mirror via the statistics sync.
class GameStatistics {
  /// Catalog size used for the local `achievementProgress` ratio. Keep in sync
  /// with Achievement.getDefaultAchievements() in `lib/models/achievement.dart`.
  static const int kTotalAchievements = 110;

  /// A run counts as "survived" (for [survivalRate]) at or beyond this many
  /// seconds — long enough to be a real attempt, not an instant death.
  static const int kSurvivalThresholdSeconds = 60;

  // Core
  final int totalGamesPlayed;
  final int totalScore;
  final int highScore;
  final int totalPlayTimeSeconds;

  // Combat / run aggregates
  final int totalEnemiesKilled;
  final int totalBossesKilled;
  final int totalMissilesFired;
  final int totalLevelsCleared;
  final int totalGrazes;
  final int totalRevivesUsed;
  final int victories; // campaign completions (final boss felled)
  final int noHitClears; // levels cleared without taking a hit
  final int gamesSurvived60s;

  // Bests (maxes)
  final int highestStageReached;
  final int highestWaveReached;
  final int longestSurvivalSeconds;
  final int bestCombo;
  final int longestWinStreak;

  // Streak (a "win" = a run that cleared at least one level)
  final int currentWinStreak;

  // Sessions / time
  final int totalSessions;
  final DateTime? firstPlayedDate;
  final DateTime? lastPlayedDate;
  final List<int> recentScores; // last 10
  final Map<String, int> dailyPlayTime; // dayKey -> seconds (last 30 days)
  final Map<String, int> gamesPerMode; // mode name -> games

  // Achievements (display mirror; real unlock state lives in the catalog)
  final int achievementsUnlocked;
  final int totalAchievements;

  const GameStatistics({
    this.totalGamesPlayed = 0,
    this.totalScore = 0,
    this.highScore = 0,
    this.totalPlayTimeSeconds = 0,
    this.totalEnemiesKilled = 0,
    this.totalBossesKilled = 0,
    this.totalMissilesFired = 0,
    this.totalLevelsCleared = 0,
    this.totalGrazes = 0,
    this.totalRevivesUsed = 0,
    this.victories = 0,
    this.noHitClears = 0,
    this.gamesSurvived60s = 0,
    this.highestStageReached = 0,
    this.highestWaveReached = 0,
    this.longestSurvivalSeconds = 0,
    this.bestCombo = 0,
    this.longestWinStreak = 0,
    this.currentWinStreak = 0,
    this.totalSessions = 0,
    this.firstPlayedDate,
    this.lastPlayedDate,
    this.recentScores = const [],
    this.dailyPlayTime = const {},
    this.gamesPerMode = const {},
    this.achievementsUnlocked = 0,
    this.totalAchievements = kTotalAchievements,
  });

  factory GameStatistics.initial() => GameStatistics(
        firstPlayedDate: DateTime.now(),
        lastPlayedDate: DateTime.now(),
      );

  // ---- Derived (never stored) --------------------------------------------

  double get averageScore =>
      totalGamesPlayed > 0 ? totalScore / totalGamesPlayed : 0.0;

  double get survivalRate =>
      totalGamesPlayed > 0 ? gamesSurvived60s / totalGamesPlayed : 0.0;

  double get averageEnemiesPerGame =>
      totalGamesPlayed > 0 ? totalEnemiesKilled / totalGamesPlayed : 0.0;

  double get achievementProgress =>
      totalAchievements > 0 ? achievementsUnlocked / totalAchievements : 0.0;

  int get totalPlayTimeHours => (totalPlayTimeSeconds / 3600).round();

  String get favoriteMode {
    if (gamesPerMode.isEmpty) return 'none';
    final sorted = gamesPerMode.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  /// Stable, zero-padded day key (YYYY-MM-DD) for the daily-playtime map.
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  int get playTimeTodaySeconds => dailyPlayTime[dayKey(DateTime.now())] ?? 0;

  // ---- Folding a run -------------------------------------------------------

  /// Fold one finished shmup run into the lifetime aggregates.
  GameStatistics updateWithGameResult({
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
  }) {
    final newTotalGames = totalGamesPlayed + 1;
    final newTotalScore = totalScore + score;
    final won = levelsCleared >= 1; // cleared at least one level
    final newCurrentStreak = won ? currentWinStreak + 1 : 0;

    final newRecent = [...recentScores, score];
    if (newRecent.length > 10) newRecent.removeRange(0, newRecent.length - 10);

    final today = DateTime.now();
    final key = dayKey(today);
    final newDaily = Map<String, int>.from(dailyPlayTime);
    newDaily[key] = (newDaily[key] ?? 0) + durationSeconds;
    // Cap at the most recent 30 day-keys so the blob doesn't grow unbounded.
    if (newDaily.length > 30) {
      final keys = newDaily.keys.toList()..sort();
      for (final k in keys.take(newDaily.length - 30)) {
        newDaily.remove(k);
      }
    }

    final newPerMode = Map<String, int>.from(gamesPerMode);
    newPerMode[gameMode] = (newPerMode[gameMode] ?? 0) + 1;

    return copyWith(
      totalGamesPlayed: newTotalGames,
      totalScore: newTotalScore,
      highScore: score > highScore ? score : highScore,
      totalPlayTimeSeconds: totalPlayTimeSeconds + durationSeconds,
      totalEnemiesKilled: totalEnemiesKilled + enemiesKilled,
      totalBossesKilled: totalBossesKilled + bossesKilled,
      totalMissilesFired: totalMissilesFired + missilesFired,
      totalLevelsCleared: totalLevelsCleared + levelsCleared,
      totalGrazes: totalGrazes + grazeCount,
      totalRevivesUsed: totalRevivesUsed + revivesUsed,
      victories: victories + (victory ? 1 : 0),
      noHitClears: noHitClears + this.noHitClears,
      gamesSurvived60s: durationSeconds >= kSurvivalThresholdSeconds
          ? gamesSurvived60s + 1
          : gamesSurvived60s,
      highestStageReached:
          stageReached > highestStageReached ? stageReached : highestStageReached,
      highestWaveReached:
          waveReached > highestWaveReached ? waveReached : highestWaveReached,
      longestSurvivalSeconds: durationSeconds > longestSurvivalSeconds
          ? durationSeconds
          : longestSurvivalSeconds,
      bestCombo: maxCombo > bestCombo ? maxCombo : bestCombo,
      currentWinStreak: newCurrentStreak,
      longestWinStreak:
          newCurrentStreak > longestWinStreak ? newCurrentStreak : longestWinStreak,
      lastPlayedDate: today,
      firstPlayedDate: firstPlayedDate ?? today,
      recentScores: newRecent,
      dailyPlayTime: newDaily,
      gamesPerMode: newPerMode,
    );
  }

  GameStatistics startNewSession() =>
      copyWith(totalSessions: totalSessions + 1, lastPlayedDate: DateTime.now());

  GameStatistics withHighScore(int newHighScore) =>
      copyWith(highScore: newHighScore);

  GameStatistics withAchievements(int unlocked, {int? total}) =>
      copyWith(achievementsUnlocked: unlocked, totalAchievements: total);

  GameStatistics copyWith({
    int? totalGamesPlayed,
    int? totalScore,
    int? highScore,
    int? totalPlayTimeSeconds,
    int? totalEnemiesKilled,
    int? totalBossesKilled,
    int? totalMissilesFired,
    int? totalLevelsCleared,
    int? totalGrazes,
    int? totalRevivesUsed,
    int? victories,
    int? noHitClears,
    int? gamesSurvived60s,
    int? highestStageReached,
    int? highestWaveReached,
    int? longestSurvivalSeconds,
    int? bestCombo,
    int? longestWinStreak,
    int? currentWinStreak,
    int? totalSessions,
    DateTime? firstPlayedDate,
    DateTime? lastPlayedDate,
    List<int>? recentScores,
    Map<String, int>? dailyPlayTime,
    Map<String, int>? gamesPerMode,
    int? achievementsUnlocked,
    int? totalAchievements,
  }) {
    return GameStatistics(
      totalGamesPlayed: totalGamesPlayed ?? this.totalGamesPlayed,
      totalScore: totalScore ?? this.totalScore,
      highScore: highScore ?? this.highScore,
      totalPlayTimeSeconds: totalPlayTimeSeconds ?? this.totalPlayTimeSeconds,
      totalEnemiesKilled: totalEnemiesKilled ?? this.totalEnemiesKilled,
      totalBossesKilled: totalBossesKilled ?? this.totalBossesKilled,
      totalMissilesFired: totalMissilesFired ?? this.totalMissilesFired,
      totalLevelsCleared: totalLevelsCleared ?? this.totalLevelsCleared,
      totalGrazes: totalGrazes ?? this.totalGrazes,
      totalRevivesUsed: totalRevivesUsed ?? this.totalRevivesUsed,
      victories: victories ?? this.victories,
      noHitClears: noHitClears ?? this.noHitClears,
      gamesSurvived60s: gamesSurvived60s ?? this.gamesSurvived60s,
      highestStageReached: highestStageReached ?? this.highestStageReached,
      highestWaveReached: highestWaveReached ?? this.highestWaveReached,
      longestSurvivalSeconds:
          longestSurvivalSeconds ?? this.longestSurvivalSeconds,
      bestCombo: bestCombo ?? this.bestCombo,
      longestWinStreak: longestWinStreak ?? this.longestWinStreak,
      currentWinStreak: currentWinStreak ?? this.currentWinStreak,
      totalSessions: totalSessions ?? this.totalSessions,
      firstPlayedDate: firstPlayedDate ?? this.firstPlayedDate,
      lastPlayedDate: lastPlayedDate ?? this.lastPlayedDate,
      recentScores: recentScores ?? this.recentScores,
      dailyPlayTime: dailyPlayTime ?? this.dailyPlayTime,
      gamesPerMode: gamesPerMode ?? this.gamesPerMode,
      achievementsUnlocked: achievementsUnlocked ?? this.achievementsUnlocked,
      totalAchievements: totalAchievements ?? this.totalAchievements,
    );
  }

  // ---- JSON ----------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'totalGamesPlayed': totalGamesPlayed,
        'totalScore': totalScore,
        'highScore': highScore,
        'totalPlayTimeSeconds': totalPlayTimeSeconds,
        'totalEnemiesKilled': totalEnemiesKilled,
        'totalBossesKilled': totalBossesKilled,
        'totalMissilesFired': totalMissilesFired,
        'totalLevelsCleared': totalLevelsCleared,
        'totalGrazes': totalGrazes,
        'totalRevivesUsed': totalRevivesUsed,
        'victories': victories,
        'noHitClears': noHitClears,
        'gamesSurvived60s': gamesSurvived60s,
        'highestStageReached': highestStageReached,
        'highestWaveReached': highestWaveReached,
        'longestSurvivalSeconds': longestSurvivalSeconds,
        'bestCombo': bestCombo,
        'longestWinStreak': longestWinStreak,
        'currentWinStreak': currentWinStreak,
        'totalSessions': totalSessions,
        'firstPlayedDate': firstPlayedDate?.toIso8601String(),
        'lastPlayedDate': lastPlayedDate?.toIso8601String(),
        'recentScores': recentScores,
        'dailyPlayTime': dailyPlayTime,
        'gamesPerMode': gamesPerMode,
        'achievementsUnlocked': achievementsUnlocked,
        'totalAchievements': totalAchievements,
        // Derived — emitted for the backend mirror / external readers; ignored
        // on read-back (the getters recompute from the counters).
        'averageScore': averageScore,
        'survivalRate': survivalRate,
        'achievementProgress': achievementProgress,
      };

  factory GameStatistics.fromJson(Map<String, dynamic> json) {
    int i(String k, [int d = 0]) => (json[k] as num?)?.toInt() ?? d;
    return GameStatistics(
      totalGamesPlayed: i('totalGamesPlayed'),
      totalScore: i('totalScore'),
      highScore: i('highScore'),
      totalPlayTimeSeconds: i('totalPlayTimeSeconds'),
      totalEnemiesKilled: i('totalEnemiesKilled'),
      totalBossesKilled: i('totalBossesKilled'),
      totalMissilesFired: i('totalMissilesFired'),
      totalLevelsCleared: i('totalLevelsCleared'),
      totalGrazes: i('totalGrazes'),
      totalRevivesUsed: i('totalRevivesUsed'),
      victories: i('victories'),
      noHitClears: i('noHitClears'),
      gamesSurvived60s: i('gamesSurvived60s'),
      highestStageReached: i('highestStageReached'),
      highestWaveReached: i('highestWaveReached'),
      longestSurvivalSeconds: i('longestSurvivalSeconds'),
      bestCombo: i('bestCombo'),
      longestWinStreak: i('longestWinStreak'),
      currentWinStreak: i('currentWinStreak'),
      totalSessions: i('totalSessions'),
      firstPlayedDate: json['firstPlayedDate'] != null
          ? DateTime.tryParse(json['firstPlayedDate'] as String)
          : null,
      lastPlayedDate: json['lastPlayedDate'] != null
          ? DateTime.tryParse(json['lastPlayedDate'] as String)
          : null,
      recentScores: List<int>.from(json['recentScores'] ?? const []),
      dailyPlayTime: Map<String, int>.from(json['dailyPlayTime'] ?? const {}),
      gamesPerMode: Map<String, int>.from(json['gamesPerMode'] ?? const {}),
      achievementsUnlocked: i('achievementsUnlocked'),
      totalAchievements: i('totalAchievements', kTotalAchievements),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory GameStatistics.fromJsonString(String jsonString) =>
      GameStatistics.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
}
