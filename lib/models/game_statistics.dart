import 'dart:convert';

class GameStatistics {
  /// Catalog size used for the local `achievementProgress` ratio.
  /// Keep in sync with Achievement.getDefaultAchievements() in
  /// `lib/models/achievement.dart`. Used as both the default and the
  /// fallback when reading legacy JSON.
  static const int kTotalAchievements = 110;

  // Basic game metrics
  final int totalGamesPlayed;
  final int totalScore;
  final int highScore;
  final int totalGameTime; // in seconds
  final int averageGameTime; // in seconds

  // Food consumption stats
  final int totalFoodConsumed;
  final Map<String, int> foodTypeCount; // normal, bonus, special
  /// Sum of *scored* points from food across all games — includes combo
  /// multipliers and active score-multiplier power-ups. NOT the sum of
  /// raw food values (10/25/50). Used by `averagePointsPerFood` which
  /// is currently not surfaced on any screen.
  final int totalFoodPoints;

  // Power-up statistics
  final int totalPowerUpsCollected;
  final Map<String, int> powerUpTypeCount; // speedBoost, invincibility, etc.
  final int totalPowerUpTime; // total time with active power-ups (seconds)

  // Survival and performance metrics
  final int longestSurvivalTime; // in seconds
  final int highestLevel;
  final int totalLevelsGained;
  final double averageScore;
  /// Count of games whose duration was >= 30s. Used to derive the
  /// `survivalRate` getter below. Previously survivalRate was a stored
  /// double computed from the bounded `recentScores` window (last 10 games),
  /// which capped the numerator and made the rate meaningless for long-time
  /// players. Tracking the count gives us an accurate ratio across the
  /// entire history.
  final int gamesSurvived30s;

  // Collision statistics
  final int wallCollisions;
  final int selfCollisions;
  final int totalCollisions;
  final double collisionRate; // collisions per game

  // Streak and consistency metrics
  final int currentWinStreak; // games without dying quickly (>30s)
  final int longestWinStreak;
  /// Current streak of consecutive games without any wall hit. RESET to 0
  /// when a game ends with a wall hit; otherwise incremented by 1 per
  /// game. Read by AchievementService.checkSpecialAchievements via the
  /// `noWallGames` parameter for the no-wall-hit-streak achievement.
  final int gamesWithoutWallHit;
  final int perfectGames; // games with no collisions

  // Session and time-based stats
  final int totalSessions;
  final int averageGamesPerSession;
  final DateTime? lastPlayedDate;
  final DateTime? firstPlayedDate;
  final List<int> recentScores; // last 10 scores
  final Map<String, int> dailyPlayTime; // date -> seconds played

  // Achievement progress
  final int achievementsUnlocked;
  final int totalAchievements;
  final double achievementProgress; // percentage

  const GameStatistics({
    this.totalGamesPlayed = 0,
    this.totalScore = 0,
    this.highScore = 0,
    this.totalGameTime = 0,
    this.averageGameTime = 0,
    this.totalFoodConsumed = 0,
    this.foodTypeCount = const {},
    this.totalFoodPoints = 0,
    this.totalPowerUpsCollected = 0,
    this.powerUpTypeCount = const {},
    this.totalPowerUpTime = 0,
    this.longestSurvivalTime = 0,
    this.highestLevel = 1,
    this.totalLevelsGained = 0,
    this.averageScore = 0.0,
    this.gamesSurvived30s = 0,
    this.wallCollisions = 0,
    this.selfCollisions = 0,
    this.totalCollisions = 0,
    this.collisionRate = 0.0,
    this.currentWinStreak = 0,
    this.longestWinStreak = 0,
    this.gamesWithoutWallHit = 0,
    this.perfectGames = 0,
    this.totalSessions = 0,
    this.averageGamesPerSession = 0,
    this.lastPlayedDate,
    this.firstPlayedDate,
    this.recentScores = const [],
    this.dailyPlayTime = const {},
    this.achievementsUnlocked = 0,
    this.totalAchievements = kTotalAchievements,
    this.achievementProgress = 0.0,
  });

  factory GameStatistics.initial() {
    return GameStatistics(
      firstPlayedDate: DateTime.now(),
      lastPlayedDate: DateTime.now(),
    );
  }

  // Calculate derived metrics
  double get averageFoodPerGame {
    return totalGamesPlayed > 0 ? totalFoodConsumed / totalGamesPlayed : 0.0;
  }

  double get averagePowerUpsPerGame {
    return totalGamesPlayed > 0
        ? totalPowerUpsCollected / totalGamesPlayed
        : 0.0;
  }

  double get averagePointsPerFood {
    return totalFoodConsumed > 0 ? totalFoodPoints / totalFoodConsumed : 0.0;
  }

  double get averageLevelPerGame {
    return totalGamesPlayed > 0 ? totalLevelsGained / totalGamesPlayed : 1.0;
  }

  double get wallCollisionRate {
    return totalGamesPlayed > 0 ? wallCollisions / totalGamesPlayed : 0.0;
  }

  double get selfCollisionRate {
    return totalGamesPlayed > 0 ? selfCollisions / totalGamesPlayed : 0.0;
  }

  String get favoriteFood {
    if (foodTypeCount.isEmpty) return 'none';

    final sortedFood = foodTypeCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sortedFood.first.key;
  }

  String get favoritePowerUp {
    if (powerUpTypeCount.isEmpty) return 'none';

    final sortedPowerUps = powerUpTypeCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sortedPowerUps.first.key;
  }

  int get totalPlayTimeHours {
    return (totalGameTime / 3600).round();
  }

  /// Percentage (0.0–1.0) of all games whose duration was >= 30 seconds.
  /// Derived from `gamesSurvived30s` so it stays accurate across the
  /// player's entire history rather than the last-10 window.
  double get survivalRate {
    return totalGamesPlayed > 0 ? gamesSurvived30s / totalGamesPlayed : 0.0;
  }

  /// Seconds of play time accumulated today. NOT a games-count — the
  /// underlying `dailyPlayTime` map values are seconds, not game counts.
  /// Previously named `gamesPlayedToday`, which was misleading. No
  /// current caller; kept for future per-day play-time displays.
  int get playTimeTodaySeconds {
    final today = DateTime.now();
    final todayKey = '${today.year}-${today.month}-${today.day}';
    return dailyPlayTime[todayKey] ?? 0;
  }

  // Update statistics with new game data. `wallHits` and `selfHits` are
  // per-game COUNTS, not booleans — a Survival-mode game that crashes
  // multiple times before final game-over correctly increments
  // wallCollisions/selfCollisions by the actual number of crashes.
  GameStatistics updateWithGameResult({
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
  }) {
    final newTotalGames = totalGamesPlayed + 1;
    final newTotalScore = totalScore + score;
    final newHighScore = score > highScore ? score : highScore;
    final newTotalGameTime = totalGameTime + gameTime;
    final newAverageGameTime = (newTotalGameTime / newTotalGames).round();

    final newTotalFoodConsumed = totalFoodConsumed + foodConsumed;
    final newFoodTypeCount = Map<String, int>.from(foodTypeCount);
    foodTypes.forEach((key, value) {
      newFoodTypeCount[key] = (newFoodTypeCount[key] ?? 0) + value;
    });

    final newTotalPowerUps = totalPowerUpsCollected + powerUpsCollected;
    final newPowerUpTypeCount = Map<String, int>.from(powerUpTypeCount);
    powerUpTypes.forEach((key, value) {
      newPowerUpTypeCount[key] = (newPowerUpTypeCount[key] ?? 0) + value;
    });

    final newWallCollisions = wallCollisions + wallHits;
    final newSelfCollisions = selfCollisions + selfHits;
    final newTotalCollisions = newWallCollisions + newSelfCollisions;

    final survived30Seconds = gameTime >= 30;
    final newCurrentStreak = survived30Seconds ? currentWinStreak + 1 : 0;
    final newLongestStreak = newCurrentStreak > longestWinStreak
        ? newCurrentStreak
        : longestWinStreak;
    final newGamesSurvived30s =
        survived30Seconds ? gamesSurvived30s + 1 : gamesSurvived30s;

    final newGamesWithoutWallHit =
        wallHits > 0 ? 0 : gamesWithoutWallHit + 1;
    final newPerfectGames = isPerfectGame ? perfectGames + 1 : perfectGames;

    final newRecentScores = [...recentScores, score];
    if (newRecentScores.length > 10) {
      newRecentScores.removeAt(0);
    }

    final today = DateTime.now();
    final todayKey = '${today.year}-${today.month}-${today.day}';
    final newDailyPlayTime = Map<String, int>.from(dailyPlayTime);
    newDailyPlayTime[todayKey] = (newDailyPlayTime[todayKey] ?? 0) + gameTime;

    // Cap the daily-playtime map at the most recent 30 day-keys. Without
    // this the map grows unbounded across the player's lifetime and the
    // full set is JSON-serialized on every save.
    const maxDailyPlayTimeEntries = 30;
    if (newDailyPlayTime.length > maxDailyPlayTimeEntries) {
      final sortedKeys = newDailyPlayTime.keys.toList()..sort();
      for (final key in sortedKeys.take(
        newDailyPlayTime.length - maxDailyPlayTimeEntries,
      )) {
        newDailyPlayTime.remove(key);
      }
    }

    final newAchievementsUnlocked =
        achievementsUnlocked + unlockedAchievements.length;
    final newAchievementProgress = newAchievementsUnlocked / totalAchievements;

    return GameStatistics(
      totalGamesPlayed: newTotalGames,
      totalScore: newTotalScore,
      highScore: newHighScore,
      totalGameTime: newTotalGameTime,
      averageGameTime: newAverageGameTime,
      totalFoodConsumed: newTotalFoodConsumed,
      foodTypeCount: newFoodTypeCount,
      totalFoodPoints: totalFoodPoints + foodPoints,
      totalPowerUpsCollected: newTotalPowerUps,
      powerUpTypeCount: newPowerUpTypeCount,
      totalPowerUpTime: totalPowerUpTime + powerUpTime,
      longestSurvivalTime: gameTime > longestSurvivalTime
          ? gameTime
          : longestSurvivalTime,
      highestLevel: level > highestLevel ? level : highestLevel,
      totalLevelsGained: totalLevelsGained + (level - 1),
      averageScore: newTotalScore / newTotalGames,
      gamesSurvived30s: newGamesSurvived30s,
      wallCollisions: newWallCollisions,
      selfCollisions: newSelfCollisions,
      totalCollisions: newTotalCollisions,
      collisionRate: newTotalCollisions / newTotalGames,
      currentWinStreak: newCurrentStreak,
      longestWinStreak: newLongestStreak,
      gamesWithoutWallHit: newGamesWithoutWallHit,
      perfectGames: newPerfectGames,
      totalSessions: totalSessions,
      averageGamesPerSession: totalSessions > 0
          ? (newTotalGames / totalSessions).round()
          : newTotalGames,
      lastPlayedDate: today,
      firstPlayedDate: firstPlayedDate ?? today,
      recentScores: newRecentScores,
      dailyPlayTime: newDailyPlayTime,
      achievementsUnlocked: newAchievementsUnlocked,
      totalAchievements: totalAchievements,
      achievementProgress: newAchievementProgress,
    );
  }

  GameStatistics startNewSession() {
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
      totalSessions: totalSessions + 1,
      averageGamesPerSession: averageGamesPerSession,
      lastPlayedDate: DateTime.now(),
      firstPlayedDate: firstPlayedDate,
      recentScores: recentScores,
      dailyPlayTime: dailyPlayTime,
      achievementsUnlocked: achievementsUnlocked,
      totalAchievements: totalAchievements,
      achievementProgress: achievementProgress,
    );
  }

  // Create a copy with updated high score (for sync purposes)
  GameStatistics withHighScore(int newHighScore) {
    return GameStatistics(
      totalGamesPlayed: totalGamesPlayed,
      totalScore: totalScore,
      highScore: newHighScore,
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

  // JSON serialization
  Map<String, dynamic> toJson() {
    return {
      'totalGamesPlayed': totalGamesPlayed,
      'totalScore': totalScore,
      'highScore': highScore,
      'totalGameTime': totalGameTime,
      'averageGameTime': averageGameTime,
      'totalFoodConsumed': totalFoodConsumed,
      'foodTypeCount': foodTypeCount,
      'totalFoodPoints': totalFoodPoints,
      'totalPowerUpsCollected': totalPowerUpsCollected,
      'powerUpTypeCount': powerUpTypeCount,
      'totalPowerUpTime': totalPowerUpTime,
      'longestSurvivalTime': longestSurvivalTime,
      'highestLevel': highestLevel,
      'totalLevelsGained': totalLevelsGained,
      'averageScore': averageScore,
      // Persist both the new counter and the derived rate. The rate field
      // stays in the payload for backward compatibility with any external
      // consumers that might read the JSON (e.g. cloud sync), but the
      // counter is the source of truth on read-back.
      'gamesSurvived30s': gamesSurvived30s,
      'survivalRate': survivalRate,
      'wallCollisions': wallCollisions,
      'selfCollisions': selfCollisions,
      'totalCollisions': totalCollisions,
      'collisionRate': collisionRate,
      'currentWinStreak': currentWinStreak,
      'longestWinStreak': longestWinStreak,
      'gamesWithoutWallHit': gamesWithoutWallHit,
      'perfectGames': perfectGames,
      'totalSessions': totalSessions,
      'averageGamesPerSession': averageGamesPerSession,
      'lastPlayedDate': lastPlayedDate?.toIso8601String(),
      'firstPlayedDate': firstPlayedDate?.toIso8601String(),
      'recentScores': recentScores,
      'dailyPlayTime': dailyPlayTime,
      'achievementsUnlocked': achievementsUnlocked,
      'totalAchievements': totalAchievements,
      'achievementProgress': achievementProgress,
    };
  }

  factory GameStatistics.fromJson(Map<String, dynamic> json) {
    return GameStatistics(
      totalGamesPlayed: json['totalGamesPlayed'] ?? 0,
      totalScore: json['totalScore'] ?? 0,
      highScore: json['highScore'] ?? 0,
      totalGameTime: json['totalGameTime'] ?? 0,
      averageGameTime: json['averageGameTime'] ?? 0,
      totalFoodConsumed: json['totalFoodConsumed'] ?? 0,
      foodTypeCount: Map<String, int>.from(json['foodTypeCount'] ?? {}),
      totalFoodPoints: json['totalFoodPoints'] ?? 0,
      totalPowerUpsCollected: json['totalPowerUpsCollected'] ?? 0,
      powerUpTypeCount: Map<String, int>.from(json['powerUpTypeCount'] ?? {}),
      totalPowerUpTime: json['totalPowerUpTime'] ?? 0,
      longestSurvivalTime: json['longestSurvivalTime'] ?? 0,
      highestLevel: json['highestLevel'] ?? 1,
      totalLevelsGained: json['totalLevelsGained'] ?? 0,
      averageScore: (json['averageScore'] ?? 0.0).toDouble(),
      // Prefer the new counter when present; otherwise back-fill from the
      // legacy (broken) survivalRate so an existing user's displayed rate
      // doesn't suddenly drop to 0% on the upgrade. The back-fill is a
      // one-time estimate; the next game played will increment the counter
      // toward the true value.
      gamesSurvived30s: () {
        final stored = json['gamesSurvived30s'];
        if (stored is int) return stored;
        final legacyRate = (json['survivalRate'] ?? 0.0).toDouble();
        final games = (json['totalGamesPlayed'] ?? 0) as int;
        return (legacyRate * games).round();
      }(),
      wallCollisions: json['wallCollisions'] ?? 0,
      selfCollisions: json['selfCollisions'] ?? 0,
      totalCollisions: json['totalCollisions'] ?? 0,
      collisionRate: (json['collisionRate'] ?? 0.0).toDouble(),
      currentWinStreak: json['currentWinStreak'] ?? 0,
      longestWinStreak: json['longestWinStreak'] ?? 0,
      gamesWithoutWallHit: json['gamesWithoutWallHit'] ?? 0,
      perfectGames: json['perfectGames'] ?? 0,
      totalSessions: json['totalSessions'] ?? 0,
      averageGamesPerSession: json['averageGamesPerSession'] ?? 0,
      lastPlayedDate: json['lastPlayedDate'] != null
          ? DateTime.parse(json['lastPlayedDate'])
          : null,
      firstPlayedDate: json['firstPlayedDate'] != null
          ? DateTime.parse(json['firstPlayedDate'])
          : null,
      recentScores: List<int>.from(json['recentScores'] ?? []),
      dailyPlayTime: Map<String, int>.from(json['dailyPlayTime'] ?? {}),
      achievementsUnlocked: json['achievementsUnlocked'] ?? 0,
      totalAchievements: json['totalAchievements'] ?? kTotalAchievements,
      achievementProgress: (json['achievementProgress'] ?? 0.0).toDouble(),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory GameStatistics.fromJsonString(String jsonString) {
    return GameStatistics.fromJson(jsonDecode(jsonString));
  }
}
