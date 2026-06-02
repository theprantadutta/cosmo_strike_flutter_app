import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';
import 'package:cosmo_strike_flutter_app/models/player_level.dart';

part 'game_dao.g.dart';

@DriftAccessor(tables: [
  Statistics,
  Achievements,
  Replays,
  DailyChallenges,
  WeeklyQuests,
  PlayerProgressTable,
])
class GameDao extends DatabaseAccessor<AppDatabase> with _$GameDaoMixin {
  GameDao(super.db);

  // ==================== Statistics ====================

  /// Watch statistics for reactive UI
  Stream<Statistic?> watchStatistics() =>
      select(statistics).watchSingleOrNull();

  /// Get current statistics
  Future<Statistic?> getStatistics() => select(statistics).getSingleOrNull();

  // ==================== Player Progress (lifetime XP + level) ====================

  /// Watch the lifetime player-progress singleton for reactive UI.
  Stream<PlayerProgressRow?> watchPlayerProgress() =>
      select(playerProgressTable).watchSingleOrNull();

  /// Current lifetime player progress (null until the first XP grant).
  Future<PlayerProgressRow?> getPlayerProgress() =>
      select(playerProgressTable).getSingleOrNull();

  /// Add [delta] lifetime XP, recompute the level from the [PlayerLevel]
  /// curve, and enqueue a `player_progress` sync outbox row — all in one
  /// transaction so the row write and its sync marker land atomically
  /// (offline-first). Returns the updated row.
  Future<PlayerProgressRow> addPlayerXp(int delta) async {
    return transaction(() async {
      final current = await getPlayerProgress();
      final safeDelta = delta < 0 ? 0 : delta;
      final newTotal = (current?.totalXp ?? 0) + safeDelta;
      final newLevel = PlayerLevel.levelForXp(newTotal);
      final now = DateTime.now();

      if (current == null) {
        await into(playerProgressTable).insert(
          PlayerProgressTableCompanion.insert(
            totalXp: Value(newTotal),
            level: Value(newLevel),
            updatedAt: Value(now),
          ),
        );
      } else {
        await (update(playerProgressTable)
              ..where((t) => t.id.equals(current.id)))
            .write(PlayerProgressTableCompanion(
          totalXp: Value(newTotal),
          level: Value(newLevel),
          updatedAt: Value(now),
        ));
      }

      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.playerProgress,
        entityKey: 'player_progress:1',
      );

      return (await getPlayerProgress())!;
    });
  }

  /// Apply an authoritative XP value from a cloud snapshot restore. MAX-merge
  /// so a restore never regresses local lifetime XP. Does NOT enqueue sync
  /// (the value came FROM the backend). Returns the resulting row.
  Future<void> applyPlayerProgressSnapshot(int snapshotTotalXp) async {
    await transaction(() async {
      final current = await getPlayerProgress();
      final merged = (current?.totalXp ?? 0) > snapshotTotalXp
          ? (current?.totalXp ?? 0)
          : snapshotTotalXp;
      final level = PlayerLevel.levelForXp(merged);
      final now = DateTime.now();
      if (current == null) {
        await into(playerProgressTable).insert(
          PlayerProgressTableCompanion.insert(
            totalXp: Value(merged),
            level: Value(level),
            updatedAt: Value(now),
          ),
        );
      } else {
        await (update(playerProgressTable)
              ..where((t) => t.id.equals(current.id)))
            .write(PlayerProgressTableCompanion(
          totalXp: Value(merged),
          level: Value(level),
          updatedAt: Value(now),
        ));
      }
    });
  }

  /// Update statistics after a game
  Future<void> updateGameStats({
    required int score,
    required int shipLength,
    required int foodsEaten,
    required int gameDurationSeconds,
    required String deathCause, // 'wall' or 'self'
    required String gameMode,
  }) async {
    final current = await getStatistics();
    if (current == null) return;

    final newTotalGames = current.totalGamesPlayed + 1;
    final newTotalScore = current.totalScore + score;
    final newHighestScore =
        score > current.highestScore ? score : current.highestScore;
    final newTotalFoods = current.totalFoodsEaten + foodsEaten;
    final newTotalTime = current.totalGameTimeSeconds + gameDurationSeconds;
    final newMaxLength =
        shipLength > current.maxShipLength ? shipLength : current.maxShipLength;
    final newTotalLength = current.totalShipLength + shipLength;
    final newAvgLength = newTotalLength / newTotalGames;

    int newDeathsByWall = current.deathsByWall;
    int newDeathsBySelf = current.deathsBySelf;
    if (deathCause == 'wall') {
      newDeathsByWall++;
    } else if (deathCause == 'self') {
      newDeathsBySelf++;
    }

    final newShortestGame = current.shortestGameSeconds == 0 ||
            gameDurationSeconds < current.shortestGameSeconds
        ? gameDurationSeconds
        : current.shortestGameSeconds;
    final newLongestGame = gameDurationSeconds > current.longestGameSeconds
        ? gameDurationSeconds
        : current.longestGameSeconds;
    final newAvgDuration = newTotalTime / newTotalGames;
    final now = DateTime.now();

    await transaction(() async {
      await (update(statistics)..where((t) => t.id.equals(1))).write(
        StatisticsCompanion(
          totalGamesPlayed: Value(newTotalGames),
          totalScore: Value(newTotalScore),
          highestScore: Value(newHighestScore),
          totalFoodsEaten: Value(newTotalFoods),
          totalGameTimeSeconds: Value(newTotalTime),
          maxShipLength: Value(newMaxLength),
          totalShipLength: Value(newTotalLength),
          averageShipLength: Value(newAvgLength),
          deathsByWall: Value(newDeathsByWall),
          deathsBySelf: Value(newDeathsBySelf),
          totalDeaths: Value(newDeathsByWall + newDeathsBySelf),
          shortestGameSeconds: Value(newShortestGame),
          longestGameSeconds: Value(newLongestGame),
          averageGameDuration: Value(newAvgDuration),
          lastPlayedAt: Value(now),
          lastUpdated: Value(now),
          updatedAt: Value(now),
        ),
      );
      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.statistics,
        entityKey: 'statistics:1',
      );
    });
  }

  /// Persist the full GameStatistics model as a JSON blob.
  ///
  /// Previously this method tried to translate the model's JSON into the
  /// table's typed columns, but the field names didn't match
  /// (highScore vs highestScore, totalGameTime vs totalGameTimeSeconds,
  /// totalFoodConsumed vs totalFoodsEaten, etc.) so most fields were
  /// silently dropped on save and zero'd on load. The statistics screen
  /// kept showing 0 for win streak, play time, perfect games, high score,
  /// and everything else as a result.
  ///
  /// New approach: round-trip the model verbatim through the dedicated
  /// `modelJson` column. The typed columns aren't read anywhere — they
  /// stay zero'd and inert.
  ///
  /// [enqueueSync] defaults true so normal end-of-game writes mark the
  /// row for upload. Pass false when hydrating from the backend on
  /// first-sign-in so the pull doesn't bounce straight back as a push.
  Future<void> updateStatisticsFromJson(
    String jsonData, {
    bool enqueueSync = true,
  }) async {
    final now = DateTime.now();
    await transaction(() async {
      final existing = await getStatistics();
      if (existing == null) {
        await into(statistics).insert(
          StatisticsCompanion(
            modelJson: Value(jsonData),
            lastUpdated: Value(now),
            updatedAt: Value(now),
          ),
        );
      } else {
        await (update(statistics)..where((t) => t.id.equals(1))).write(
          StatisticsCompanion(
            modelJson: Value(jsonData),
            lastUpdated: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
      if (enqueueSync) {
        await attachedDatabase.enqueueSyncOutbox(
          dataType: SyncDataType.statistics,
          entityKey: 'statistics:1',
        );
      }
    });
  }

  /// Read the full GameStatistics JSON. Returns '{}' if no row exists yet
  /// (StatisticsService treats that as 'fresh install' and loads
  /// GameStatistics.initial()).
  Future<String> getStatisticsAsJson() async {
    final stats = await getStatistics();
    if (stats == null) return '{}';
    return stats.modelJson;
  }

  // ==================== Achievements ====================

  /// Watch all achievements
  Stream<List<Achievement>> watchAchievements() => select(achievements).watch();

  /// Get all achievements
  Future<List<Achievement>> getAllAchievements() =>
      select(achievements).get();

  /// Get unlocked achievements
  Future<List<Achievement>> getUnlockedAchievements() =>
      (select(achievements)..where((t) => t.isUnlocked.equals(true))).get();

  /// Get achievement by ID
  Future<Achievement?> getAchievementById(String id) =>
      (select(achievements)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Fetch many achievements in a single query. Used by SyncEngine
  /// drain to avoid one round-trip per achievement id.
  Future<List<Achievement>> getAchievementsByIds(Set<String> ids) {
    if (ids.isEmpty) return Future.value(<Achievement>[]);
    return (select(achievements)..where((t) => t.id.isIn(ids))).get();
  }

  /// Update achievement progress
  Future<void> updateAchievementProgress(
    String achievementId,
    int progress,
  ) async {
    final achievement = await (select(achievements)
          ..where((t) => t.id.equals(achievementId)))
        .getSingleOrNull();

    if (achievement == null) return;

    final isNowUnlocked = progress >= achievement.targetProgress;
    final now = DateTime.now();

    await transaction(() async {
      await (update(achievements)..where((t) => t.id.equals(achievementId)))
          .write(AchievementsCompanion(
        currentProgress: Value(progress),
        isUnlocked: Value(isNowUnlocked),
        unlockedAt: isNowUnlocked && !achievement.isUnlocked
            ? Value(now)
            : const Value.absent(),
        lastUpdated: Value(now),
        updatedAt: Value(now),
      ));
      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.achievement,
        entityKey: 'achievement:$achievementId',
      );
    });
  }

  /// Unlock achievement directly
  Future<void> unlockAchievement(String achievementId) async {
    final now = DateTime.now();
    await transaction(() async {
      await (update(achievements)..where((t) => t.id.equals(achievementId)))
          .write(AchievementsCompanion(
        isUnlocked: const Value(true),
        unlockedAt: Value(now),
        lastUpdated: Value(now),
        updatedAt: Value(now),
      ));
      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.achievement,
        entityKey: 'achievement:$achievementId',
      );
    });
  }

  /// Claim achievement reward
  Future<int> claimAchievementReward(String achievementId) async {
    final achievement = await (select(achievements)
          ..where((t) => t.id.equals(achievementId)))
        .getSingleOrNull();

    if (achievement == null || achievement.rewardClaimed) return 0;

    final now = DateTime.now();
    await transaction(() async {
      await (update(achievements)..where((t) => t.id.equals(achievementId)))
          .write(AchievementsCompanion(
        rewardClaimed: const Value(true),
        lastUpdated: Value(now),
        updatedAt: Value(now),
      ));
      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.achievement,
        entityKey: 'achievement:$achievementId',
      );
    });

    return achievement.rewardCoins;
  }

  /// Seed the Drift achievements catalog from the client's default
  /// definitions. Insert-or-ignore semantics: rows that already exist
  /// (with whatever progress / unlocked state the user has accumulated)
  /// are left untouched; only missing slugs get created. Never enqueues
  /// a sync — these are catalog rows the server already owns. Called
  /// once at startup from `AchievementService.initialize`; without it
  /// `loadAchievementsFromJson`'s Map branch silently skips every entry
  /// because `getAchievementById` returns null on a fresh install, which
  /// is the bug class that left achievements unsynced to the dashboard.
  Future<void> seedDefaultAchievementsIfMissing(
    Iterable<AchievementsCompanion> defaults,
  ) async {
    await batch((b) {
      for (final companion in defaults) {
        b.insert(achievements, companion, mode: InsertMode.insertOrIgnore);
      }
    });
  }

  /// Insert or update achievement.
  ///
  /// [enqueueSync] defaults true; pass false when seeding the catalog
  /// from a server pull so the same data doesn't bounce back as an
  /// outbound sync.
  Future<void> upsertAchievement(
    AchievementsCompanion achievement, {
    bool enqueueSync = true,
  }) async {
    final id = achievement.id.present ? achievement.id.value : null;
    await transaction(() async {
      await into(achievements).insertOnConflictUpdate(achievement);
      if (enqueueSync && id != null) {
        await attachedDatabase.enqueueSyncOutbox(
          dataType: SyncDataType.achievement,
          entityKey: 'achievement:$id',
        );
      }
    });
  }

  /// Get achievements as JSON
  Future<String> getAchievementsAsJson() async {
    final list = await getAllAchievements();
    return json.encode(list
        .map((a) => {
              'id': a.id,
              'name': a.name,
              'description': a.description,
              'category': a.category,
              'currentProgress': a.currentProgress,
              'targetProgress': a.targetProgress,
              'isUnlocked': a.isUnlocked,
              'unlockedAt': a.unlockedAt?.toIso8601String(),
              'rewardCoins': a.rewardCoins,
              'rewardClaimed': a.rewardClaimed,
            })
        .toList());
  }

  /// Load achievements from JSON. Supports both List format (full
  /// achievement data, used by the cloud-snapshot restore path) and
  /// Map format (progress-only, keyed by id — used by the in-game
  /// AchievementService's local save path).
  ///
  /// [enqueueSync] defaults to false so the historical restore caller
  /// doesn't echo the data back as a push. The local-save path passes
  /// `true` so AchievementService progress actually round-trips to the
  /// backend via the SyncEngine outbox. When `enqueueSync` is true, an
  /// outbox row is only enqueued for rows whose synced fields (progress
  /// / isUnlocked / unlockedAt / rewardClaimed) actually changed —
  /// without that diff, every `_saveProgress` would queue all ~50
  /// achievements every time and bloat the outbox.
  Future<void> loadAchievementsFromJson(
    String jsonData, {
    bool enqueueSync = false,
  }) async {
    final decoded = json.decode(jsonData);

    if (decoded is List) {
      // List format: full achievement data from backend or old format.
      // Restore-only path — never enqueue, regardless of the caller's
      // [enqueueSync] preference (the data is already authoritative
      // server-side).
      for (final item in decoded) {
        await upsertAchievement(
          AchievementsCompanion(
            id: Value(item['id']),
            name: Value(item['name']),
            description: Value(item['description']),
            category: Value(item['category'] ?? 'general'),
            currentProgress: Value(item['currentProgress'] ?? 0),
            targetProgress: Value(item['targetProgress'] ?? 1),
            isUnlocked: Value(item['isUnlocked'] ?? false),
            unlockedAt: item['unlockedAt'] != null
                ? Value(DateTime.parse(item['unlockedAt']))
                : const Value.absent(),
            rewardCoins: Value(item['rewardCoins'] ?? 0),
            rewardClaimed: Value(item['rewardClaimed'] ?? false),
          ),
          enqueueSync: false,
        );
      }
    } else if (decoded is Map) {
      // Map format: progress-only data keyed by achievement id.
      for (final entry in decoded.entries) {
        final id = entry.key.toString();
        final data = entry.value;
        if (data == null || data is! Map) continue;

        final existing = await getAchievementById(id);
        if (existing != null) {
          final newProgress =
              (data['currentProgress'] as int?) ?? existing.currentProgress;
          final newUnlocked =
              (data['isUnlocked'] as bool?) ?? existing.isUnlocked;
          final newRewardClaimed =
              (data['rewardClaimed'] as bool?) ?? existing.rewardClaimed;
          final rawUnlockedAt = data['unlockedAt'] as String?;
          final newUnlockedAt = rawUnlockedAt != null
              ? DateTime.tryParse(rawUnlockedAt)
              : existing.unlockedAt;

          final synced = enqueueSync &&
              (newProgress != existing.currentProgress ||
                  newUnlocked != existing.isUnlocked ||
                  newRewardClaimed != existing.rewardClaimed ||
                  newUnlockedAt != existing.unlockedAt);

          await upsertAchievement(
            AchievementsCompanion(
              id: Value(id),
              name: Value(existing.name),
              description: Value(existing.description),
              category: Value(existing.category),
              currentProgress: Value(newProgress),
              targetProgress: Value(existing.targetProgress),
              isUnlocked: Value(newUnlocked),
              unlockedAt: newUnlockedAt != null
                  ? Value(newUnlockedAt)
                  : const Value.absent(),
              rewardCoins: Value(existing.rewardCoins),
              rewardClaimed: Value(newRewardClaimed),
            ),
            enqueueSync: synced,
          );
        }
      }
    }
  }

  // ==================== Replays ====================
  // Replays are excluded from the sync surface (the user explicitly
  // left them off the v1 sync scope — replays can be hundreds of KB
  // each so we'd want to think about bandwidth before turning them on).

  /// Watch all replays
  Stream<List<Replay>> watchReplays() =>
      (select(replays)..orderBy([(t) => OrderingTerm.desc(t.recordedAt)]))
          .watch();

  /// Get all replays
  Future<List<Replay>> getAllReplays() =>
      (select(replays)..orderBy([(t) => OrderingTerm.desc(t.recordedAt)]))
          .get();

  /// Get replay by ID
  Future<Replay?> getReplay(String id) =>
      (select(replays)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Save a replay and apply the retention policy: keep top 10 by
  /// score + the 10 most recent (deduplicated). Everything outside
  /// that union gets deleted. Wrapped in a transaction so a half-
  /// applied cull can't leave the table inconsistent.
  Future<void> saveReplay(ReplaysCompanion replay) async {
    await transaction(() async {
      await into(replays).insertOnConflictUpdate(replay);
      await _applyReplayRetention();
    });
  }

  /// Cull replays down to the keep-set: union of top-10-by-score and
  /// last-10-by-recordedAt. Called from inside [saveReplay]'s
  /// transaction so concurrent inserts can't race the delete.
  Future<void> _applyReplayRetention() async {
    final topByScore = await (select(replays)
          ..orderBy([(t) => OrderingTerm.desc(t.score)])
          ..limit(10))
        .get();
    final topByRecent = await (select(replays)
          ..orderBy([(t) => OrderingTerm.desc(t.recordedAt)])
          ..limit(10))
        .get();
    final keepIds = <String>{
      ...topByScore.map((r) => r.id),
      ...topByRecent.map((r) => r.id),
    };
    if (keepIds.isEmpty) return;
    await (delete(replays)..where((t) => t.id.isNotIn(keepIds))).go();
  }

  /// Delete a replay
  Future<void> deleteReplay(String id) async {
    await (delete(replays)..where((t) => t.id.equals(id))).go();
  }

  /// Toggle replay favorite
  Future<void> toggleReplayFavorite(String id) async {
    final replay = await getReplay(id);
    if (replay == null) return;

    await (update(replays)..where((t) => t.id.equals(id)))
        .write(ReplaysCompanion(isFavorite: Value(!replay.isFavorite)));
  }

  /// Get replay keys (IDs)
  Future<List<String>> getReplayKeys() async {
    final list = await getAllReplays();
    return list.map((r) => r.id).toList();
  }

  // ==================== Daily Challenges ====================
  // Offline-first: both progress and claims write to Drift (one row per
  // challenge_id — a unique index + an upsert targeting challenge_id keep it
  // single). DailyChallengeService pushes via the sync outbox.

  /// Watch today's challenges
  Stream<List<DailyChallenge>> watchTodaysChallenges() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return (select(dailyChallenges)
          ..where((t) =>
              t.challengeDate.isBiggerOrEqualValue(startOfDay) &
              t.challengeDate.isSmallerThanValue(endOfDay)))
        .watch();
  }

  /// Get today's challenges
  Future<List<DailyChallenge>> getTodaysChallenges() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return (select(dailyChallenges)
          ..where((t) =>
              t.challengeDate.isBiggerOrEqualValue(startOfDay) &
              t.challengeDate.isSmallerThanValue(endOfDay)))
        .get();
  }

  /// Claim challenge reward. Marks the row claimed + enqueues an
  /// outbox row so the backend records the claim.
  Future<int> claimChallengeReward(String challengeId) async {
    final challenge = await (select(dailyChallenges)
          ..where((t) => t.challengeId.equals(challengeId)))
        .getSingleOrNull();

    if (challenge == null || challenge.rewardClaimed || !challenge.isCompleted) {
      return 0;
    }

    final now = DateTime.now();
    await transaction(() async {
      await (update(dailyChallenges)
            ..where((t) => t.challengeId.equals(challengeId)))
          .write(DailyChallengesCompanion(
        rewardClaimed: const Value(true),
        updatedAt: Value(now),
      ));
      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.dailyChallengeClaim,
        entityKey: 'daily_challenge_claim:$challengeId',
      );
    });

    return challenge.rewardCoins;
  }

  /// Insert or update daily challenge.
  ///
  /// [enqueueSync] defaults true. The DailyChallengeService claim
  /// path uses this to persist + sync in one shot. Pass false when
  /// hydrating from the backend.
  Future<void> upsertDailyChallenge(
    DailyChallengesCompanion challenge, {
    bool enqueueSync = true,
  }) async {
    final id = challenge.challengeId.present
        ? challenge.challengeId.value
        : null;
    final now = DateTime.now();
    final stamped = challenge.copyWith(updatedAt: Value(now));
    await transaction(() async {
      // Upsert keyed on challenge_id, NOT the autoIncrement PK — Drift's
      // insertOnConflictUpdate targets the PK, so it would insert a fresh row
      // every time (and now throw against the unique challenge_id index).
      // DoUpdate(target: challengeId) makes it a real per-challenge upsert.
      await into(dailyChallenges).insert(
        stamped,
        onConflict: DoUpdate(
          (_) => stamped,
          target: [dailyChallenges.challengeId],
        ),
      );
      if (enqueueSync && id != null) {
        await attachedDatabase.enqueueSyncOutbox(
          dataType: SyncDataType.dailyChallengeClaim,
          entityKey: 'daily_challenge_claim:$id',
        );
      }
    });
  }

  /// Clean up expired challenges
  Future<void> cleanupExpiredChallenges() async {
    final now = DateTime.now();
    await (delete(dailyChallenges)..where((t) => t.expiresAt.isSmallerThanValue(now))).go();
  }

  // =========================================================================
  // WEEKLY QUESTS — mirrors the DailyChallenges DAO surface.
  // =========================================================================

  /// All weekly-quest rows currently in Drift. The service hydrates this
  /// to mark already-claimed rewards across reinstalls.
  Future<List<WeeklyQuest>> getAllWeeklyQuests() {
    return select(weeklyQuests).get();
  }

  /// Quests for the ISO week that contains [reference] (default: now).
  Future<List<WeeklyQuest>> getWeeklyQuestsForWeek({DateTime? reference}) {
    final ref = reference ?? DateTime.now();
    final monday = ref.subtract(Duration(days: ref.weekday - 1));
    final weekStart = DateTime(monday.year, monday.month, monday.day);
    final weekEnd = weekStart.add(const Duration(days: 7));
    return (select(weeklyQuests)
          ..where((t) =>
              t.weekStartDate.isBiggerOrEqualValue(weekStart) &
              t.weekStartDate.isSmallerThanValue(weekEnd)))
        .get();
  }

  /// Insert or update a weekly quest claim row. Same shape as the daily-
  /// challenge equivalent — used both for hydrating from the backend
  /// (enqueueSync=false) and for persisting a local claim
  /// (enqueueSync=true).
  Future<void> upsertWeeklyQuest(
    WeeklyQuestsCompanion quest, {
    bool enqueueSync = true,
  }) async {
    final id = quest.questId.present ? quest.questId.value : null;
    final now = DateTime.now();
    final stamped = quest.copyWith(updatedAt: Value(now));
    await transaction(() async {
      // Upsert keyed on quest_id, NOT the autoIncrement PK (same reason as
      // upsertDailyChallenge). Relies on the unique quest_id index (v8).
      await into(weeklyQuests).insert(
        stamped,
        onConflict: DoUpdate(
          (_) => stamped,
          target: [weeklyQuests.questId],
        ),
      );
      if (enqueueSync && id != null) {
        await attachedDatabase.enqueueSyncOutbox(
          dataType: SyncDataType.weeklyQuestClaim,
          entityKey: 'weekly_quest_claim:$id',
        );
      }
    });
  }

  /// Claim weekly-quest reward. Marks the row claimed + enqueues an
  /// outbox row so the backend records the claim. Returns the coin
  /// reward (or 0 if the quest wasn't claimable / found).
  Future<int> claimWeeklyQuestReward(String questId) async {
    final quest = await (select(weeklyQuests)
          ..where((t) => t.questId.equals(questId)))
        .getSingleOrNull();

    if (quest == null || quest.claimedReward || !quest.isCompleted) {
      return 0;
    }

    final now = DateTime.now();
    await transaction(() async {
      await (update(weeklyQuests)
            ..where((t) => t.questId.equals(questId)))
          .write(WeeklyQuestsCompanion(
        claimedReward: const Value(true),
        completedAt: Value(quest.completedAt ?? now),
        updatedAt: Value(now),
      ));
      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.weeklyQuestClaim,
        entityKey: 'weekly_quest_claim:$questId',
      );
    });

    return quest.coinReward;
  }
}
