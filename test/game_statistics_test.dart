// Guards the shmup GameStatistics model the live game now records into
// (gameplay_screen._submitRun → StatisticsService.recordGameResult →
// updateWithGameResult). Covers the fold math (cumulative counters, maxes,
// win streak, survival threshold, per-mode/daily maps), the derived getters,
// and the JSON round-trip the Drift blob + backend mirror depend on.

import 'package:cosmo_strike_flutter_app/models/game_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameStatistics.updateWithGameResult', () {
    test('folds a single run into the lifetime aggregates', () {
      final stats = GameStatistics.initial().updateWithGameResult(
        score: 1200,
        durationSeconds: 90,
        stageReached: 3,
        waveReached: 7,
        enemiesKilled: 40,
        bossesKilled: 1,
        levelsCleared: 2,
        missilesFired: 5,
        revivesUsed: 1,
        victory: false,
        noHitClears: 1,
        maxCombo: 12,
        grazeCount: 8,
        gameMode: 'campaign',
      );

      expect(stats.totalGamesPlayed, 1);
      expect(stats.totalScore, 1200);
      expect(stats.highScore, 1200);
      expect(stats.totalPlayTimeSeconds, 90);
      expect(stats.totalEnemiesKilled, 40);
      expect(stats.totalBossesKilled, 1);
      expect(stats.totalLevelsCleared, 2);
      expect(stats.totalGrazes, 8);
      expect(stats.totalRevivesUsed, 1);
      expect(stats.highestStageReached, 3);
      expect(stats.highestWaveReached, 7);
      expect(stats.longestSurvivalSeconds, 90);
      expect(stats.bestCombo, 12);
      // duration >= 60s threshold → counts as survived.
      expect(stats.gamesSurvived60s, 1);
      // cleared >= 1 level → win streak ticks up.
      expect(stats.currentWinStreak, 1);
      expect(stats.longestWinStreak, 1);
      expect(stats.recentScores, [1200]);
      expect(stats.gamesPerMode['campaign'], 1);
    });

    test('accumulates counters and maxes across two runs', () {
      final s1 = GameStatistics.initial().updateWithGameResult(
        score: 500,
        durationSeconds: 30, // below the 60s survival threshold
        stageReached: 2,
        waveReached: 4,
        enemiesKilled: 10,
        bossesKilled: 0,
        levelsCleared: 1,
        maxCombo: 5,
      );
      final s2 = s1.updateWithGameResult(
        score: 900,
        durationSeconds: 120,
        stageReached: 1, // lower → max stays at 2
        waveReached: 9,
        enemiesKilled: 25,
        bossesKilled: 2,
        levelsCleared: 0, // no clear → breaks the streak
        maxCombo: 3, // lower → best combo stays at 5
      );

      expect(s2.totalGamesPlayed, 2);
      expect(s2.totalScore, 1400);
      expect(s2.highScore, 900);
      expect(s2.totalEnemiesKilled, 35);
      expect(s2.totalBossesKilled, 2);
      // maxes don't regress.
      expect(s2.highestStageReached, 2);
      expect(s2.highestWaveReached, 9);
      expect(s2.bestCombo, 5);
      expect(s2.longestSurvivalSeconds, 120);
      // only the 120s run cleared the survival bar.
      expect(s2.gamesSurvived60s, 1);
      // run 2 cleared no level → current streak resets, longest remembers 1.
      expect(s2.currentWinStreak, 0);
      expect(s2.longestWinStreak, 1);
    });

    test('derived getters compute off the folded counters', () {
      final stats = GameStatistics.initial()
          .updateWithGameResult(
            score: 100,
            durationSeconds: 90,
            stageReached: 1,
            waveReached: 1,
            enemiesKilled: 10,
            bossesKilled: 0,
            levelsCleared: 1,
          )
          .updateWithGameResult(
            score: 300,
            durationSeconds: 20,
            stageReached: 1,
            waveReached: 1,
            enemiesKilled: 30,
            bossesKilled: 0,
            levelsCleared: 1,
          );

      expect(stats.averageScore, 200.0); // (100 + 300) / 2
      expect(stats.averageEnemiesPerGame, 20.0); // (10 + 30) / 2
      expect(stats.survivalRate, 0.5); // 1 of 2 runs >= 60s
    });

    test('empty stats never divide by zero', () {
      final stats = GameStatistics.initial();
      expect(stats.averageScore, 0.0);
      expect(stats.survivalRate, 0.0);
      expect(stats.achievementProgress, 0.0);
      expect(stats.favoriteMode, 'none');
    });
  });

  group('GameStatistics JSON round-trip', () {
    test('survives encode → decode with counters intact', () {
      final original = GameStatistics.initial().updateWithGameResult(
        score: 4242,
        durationSeconds: 75,
        stageReached: 5,
        waveReached: 11,
        enemiesKilled: 88,
        bossesKilled: 3,
        levelsCleared: 4,
        maxCombo: 20,
        gameMode: 'survival',
      );

      final restored =
          GameStatistics.fromJsonString(original.toJsonString());

      expect(restored.totalGamesPlayed, original.totalGamesPlayed);
      expect(restored.totalScore, original.totalScore);
      expect(restored.highScore, original.highScore);
      expect(restored.totalEnemiesKilled, original.totalEnemiesKilled);
      expect(restored.highestStageReached, original.highestStageReached);
      expect(restored.bestCombo, original.bestCombo);
      expect(restored.gamesPerMode['survival'], 1);
      // derived fields are emitted for the mirror but recomputed on read.
      expect(restored.averageScore, original.averageScore);
    });
  });

  group('GameStatistics.dayKey', () {
    test('is zero-padded YYYY-MM-DD', () {
      expect(GameStatistics.dayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(GameStatistics.dayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });
}
