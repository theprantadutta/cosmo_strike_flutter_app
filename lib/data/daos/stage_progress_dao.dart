import 'package:drift/drift.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';
import 'package:cosmo_strike_flutter_app/models/level_run_result.dart';
import 'package:cosmo_strike_flutter_app/utils/campaign_catalog.dart';

part 'stage_progress_dao.g.dart';

/// Offline-first campaign progress. Drift is the source of truth: the
/// level-select screen watches [watchAll]; run results merge in through
/// [applyRunResults]; the SyncEngine drains changed rows to the backend's
/// absorbing-merge /sync/stage-progress endpoint; first-sign-in restores
/// arrive via [applyStageProgressSnapshot].
@DriftAccessor(tables: [StageProgressTable])
class StageProgressDao extends DatabaseAccessor<AppDatabase>
    with _$StageProgressDaoMixin {
  StageProgressDao(super.db);

  /// All stage rows in level order — the single watch feeding level select.
  Stream<List<StageProgressRow>> watchAll() =>
      (select(stageProgressTable)..orderBy([(t) => OrderingTerm.asc(t.stageId)]))
          .watch();

  Future<List<StageProgressRow>> getAll() =>
      (select(stageProgressTable)..orderBy([(t) => OrderingTerm.asc(t.stageId)]))
          .get();

  Future<StageProgressRow?> getStage(int stageId) =>
      (select(stageProgressTable)..where((t) => t.stageId.equals(stageId)))
          .getSingleOrNull();

  /// Batch fetch for the SyncEngine drain (one query per batch, not per row).
  Future<List<StageProgressRow>> getByStageIds(Set<int> ids) {
    if (ids.isEmpty) return Future.value(<StageProgressRow>[]);
    return (select(stageProgressTable)..where((t) => t.stageId.isIn(ids))).get();
  }

  /// Highest unlocked level (the level-select default selection /
  /// "continue" target). Falls back to 1 on an unseeded table.
  Future<int> getFurthestUnlocked() async {
    final rows = await (select(stageProgressTable)
          ..where((t) => t.unlocked.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.stageId)])
          ..limit(1))
        .get();
    return rows.isEmpty ? 1 : rows.first.stageId;
  }

  /// Seed rows 1..[CampaignCatalog.totalLevels] with level 1 unlocked.
  /// Insert-or-ignore so re-running (initializeDefaults on every launch)
  /// never touches accumulated progress. Never enqueues sync — a pure
  /// seed is not user progress.
  Future<void> seedDefaultsIfEmpty() async {
    await batch((b) {
      for (var level = 1; level <= CampaignCatalog.totalLevels; level++) {
        b.insert(
          stageProgressTable,
          StageProgressTableCompanion.insert(
            stageId: Value(level),
            unlocked: Value(level == 1),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Merge one run's per-level results into the persistent bests, unlock
  /// the next level on clears, recompute stars from the MERGED bests, and
  /// enqueue a sync outbox row per changed stage — all in one transaction.
  ///
  /// Every merge rule is monotonic (OR / MAX / MIN-nonzero), so calling
  /// this twice with the same results is harmless: only [clearCount]
  /// increments per call, and only for results with `cleared == true`.
  /// Pass [enqueueSync] = false when replaying results that were already
  /// persisted (e.g. the final game-over re-apply after incremental
  /// per-level saves — still safe either way, just avoids outbox noise).
  ///
  /// Returns one [StageClearOutcome] per CLEARED result so the caller can
  /// award first-clear bonuses and drive the overlay flourishes.
  Future<List<StageClearOutcome>> applyRunResults(
    List<LevelRunResult> results, {
    bool enqueueSync = true,
  }) async {
    if (results.isEmpty) return const <StageClearOutcome>[];

    return transaction(() async {
      final outcomes = <StageClearOutcome>[];
      final now = DateTime.now();

      for (final r in results) {
        if (r.stageId < 1 || r.stageId > CampaignCatalog.totalLevels) continue;

        final existing = await getStage(r.stageId);
        final wasCleared = existing?.cleared ?? false;
        final starsBefore = existing?.stars ?? 0;

        // Monotonic merge against the stored bests.
        final cleared = wasCleared || r.cleared;
        final noHit = (existing?.clearedNoHit ?? false) || (r.cleared && r.noHit);
        final bestScore = _max(existing?.bestScore ?? 0, r.score);
        final bestWave = _max(existing?.bestWaveReached ?? 0, r.waveReached);
        final bestTime = r.cleared
            ? _minNonZero(existing?.bestTimeSeconds ?? 0, r.timeSeconds)
            : (existing?.bestTimeSeconds ?? 0);
        final clearCount = (existing?.clearCount ?? 0) + (r.cleared ? 1 : 0);
        final firstClearedAt = existing?.firstClearedAt ??
            (r.cleared ? now : null);
        final stars = CampaignCatalog.starsFor(
          stageId: r.stageId,
          cleared: cleared,
          noHit: noHit,
          bestTimeSeconds: bestTime,
          bestScore: bestScore,
        );

        final changed = existing == null ||
            cleared != existing.cleared ||
            noHit != existing.clearedNoHit ||
            bestScore != existing.bestScore ||
            bestWave != existing.bestWaveReached ||
            bestTime != existing.bestTimeSeconds ||
            clearCount != existing.clearCount ||
            stars != existing.stars;

        if (changed) {
          await into(stageProgressTable).insert(
            StageProgressTableCompanion.insert(
              stageId: Value(r.stageId),
              unlocked: Value(existing?.unlocked ?? (r.stageId == 1)),
              cleared: Value(cleared),
              bestScore: Value(bestScore),
              bestTimeSeconds: Value(bestTime),
              bestWaveReached: Value(bestWave),
              clearedNoHit: Value(noHit),
              stars: Value(stars),
              clearCount: Value(clearCount),
              firstClearedAt: Value(firstClearedAt),
              updatedAt: Value(now),
            ),
            mode: InsertMode.insertOrReplace,
          );
          if (enqueueSync) {
            await attachedDatabase.enqueueSyncOutbox(
              dataType: SyncDataType.stageProgress,
              entityKey: 'stage_progress:${r.stageId}',
              priority: 1,
            );
          }
        }

        // Unlock rule: clearing N opens N+1.
        var unlockedNext = false;
        if (r.cleared && r.stageId < CampaignCatalog.totalLevels) {
          unlockedNext = await _unlockStage(r.stageId + 1,
              now: now, enqueueSync: enqueueSync);
        }

        if (r.cleared) {
          outcomes.add(StageClearOutcome(
            stageId: r.stageId,
            firstClear: !wasCleared,
            starsBefore: starsBefore,
            starsAfter: stars,
            unlockedNextStage: unlockedNext,
          ));
        }
      }

      return outcomes;
    });
  }

  /// Unlock a stage if it isn't already. Returns true when this call
  /// flipped the flag (drives the "LEVEL N UNLOCKED" flourish).
  Future<bool> _unlockStage(
    int stageId, {
    required DateTime now,
    required bool enqueueSync,
  }) async {
    final existing = await getStage(stageId);
    if (existing?.unlocked ?? false) return false;

    await into(stageProgressTable).insert(
      StageProgressTableCompanion.insert(
        stageId: Value(stageId),
        unlocked: const Value(true),
        cleared: Value(existing?.cleared ?? false),
        bestScore: Value(existing?.bestScore ?? 0),
        bestTimeSeconds: Value(existing?.bestTimeSeconds ?? 0),
        bestWaveReached: Value(existing?.bestWaveReached ?? 0),
        clearedNoHit: Value(existing?.clearedNoHit ?? false),
        stars: Value(existing?.stars ?? 0),
        clearCount: Value(existing?.clearCount ?? 0),
        firstClearedAt: Value(existing?.firstClearedAt),
        updatedAt: Value(now),
      ),
      mode: InsertMode.insertOrReplace,
    );
    if (enqueueSync) {
      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.stageProgress,
        entityKey: 'stage_progress:$stageId',
        priority: 1,
      );
    }
    return true;
  }

  /// First-sign-in hydration from the cloud snapshot's `stage_progress`
  /// section. Same monotonic max-merge as the backend so a restore can
  /// never regress local progress; if the LOCAL row is ahead on any
  /// field, re-enqueue it for push (the first-sign-in flow clears the
  /// sync queue before applying the snapshot — without this, local-ahead
  /// progress would be stranded; mirrors the coin-balance idiom).
  Future<void> applyStageProgressSnapshot(
    List<Map<String, dynamic>> rows,
  ) async {
    await transaction(() async {
      final now = DateTime.now();
      for (final row in rows) {
        final stageId = (row['stage_id'] as num?)?.toInt();
        if (stageId == null ||
            stageId < 1 ||
            stageId > CampaignCatalog.totalLevels) {
          continue;
        }

        final remoteUnlocked =
            ((row['unlocked'] as bool?) ?? false) || stageId == 1;
        final remoteCleared = (row['cleared'] as bool?) ?? false;
        final remoteNoHit = (row['cleared_no_hit'] as bool?) ?? false;
        final remoteScore = (row['best_score'] as num?)?.toInt() ?? 0;
        final remoteTime = (row['best_time_seconds'] as num?)?.toInt() ?? 0;
        final remoteWave = (row['best_wave_reached'] as num?)?.toInt() ?? 0;
        final remoteClearCount = (row['clear_count'] as num?)?.toInt() ?? 0;
        final remoteFirstCleared = row['first_cleared_at'] is String
            ? DateTime.tryParse(row['first_cleared_at'] as String)
            : null;

        final local = await getStage(stageId);

        final unlocked = (local?.unlocked ?? false) || remoteUnlocked;
        final cleared = (local?.cleared ?? false) || remoteCleared;
        final noHit = (local?.clearedNoHit ?? false) || remoteNoHit;
        final bestScore = _max(local?.bestScore ?? 0, remoteScore);
        final bestWave = _max(local?.bestWaveReached ?? 0, remoteWave);
        final bestTime = _minNonZero(local?.bestTimeSeconds ?? 0, remoteTime);
        final clearCount = _max(local?.clearCount ?? 0, remoteClearCount);
        final firstClearedAt =
            _earliestNonNull(local?.firstClearedAt, remoteFirstCleared);
        final stars = CampaignCatalog.starsFor(
          stageId: stageId,
          cleared: cleared,
          noHit: noHit,
          bestTimeSeconds: bestTime,
          bestScore: bestScore,
        );

        await into(stageProgressTable).insert(
          StageProgressTableCompanion.insert(
            stageId: Value(stageId),
            unlocked: Value(unlocked),
            cleared: Value(cleared),
            bestScore: Value(bestScore),
            bestTimeSeconds: Value(bestTime),
            bestWaveReached: Value(bestWave),
            clearedNoHit: Value(noHit),
            stars: Value(stars),
            clearCount: Value(clearCount),
            firstClearedAt: Value(firstClearedAt),
            updatedAt: Value(now),
          ),
          mode: InsertMode.insertOrReplace,
        );

        // Local was ahead of the cloud on something → push it back up.
        final localAhead = local != null &&
            ((local.cleared && !remoteCleared) ||
                (local.clearedNoHit && !remoteNoHit) ||
                local.bestScore > remoteScore ||
                local.bestWaveReached > remoteWave ||
                (local.bestTimeSeconds > 0 &&
                    (remoteTime == 0 || local.bestTimeSeconds < remoteTime)) ||
                local.clearCount > remoteClearCount ||
                (local.unlocked && !remoteUnlocked && stageId != 1));
        if (localAhead) {
          await attachedDatabase.enqueueSyncOutbox(
            dataType: SyncDataType.stageProgress,
            entityKey: 'stage_progress:$stageId',
            priority: 1,
          );
        }
      }

      // Make sure the un-restored tail of the campaign still has rows.
      await seedDefaultsIfEmpty();
    });
  }

  static int _max(int a, int b) => a > b ? a : b;

  /// Fastest-clear merge: 0 means "never cleared" and never wins.
  static int _minNonZero(int a, int b) {
    if (a == 0) return b;
    if (b == 0) return a;
    return a < b ? a : b;
  }

  static DateTime? _earliestNonNull(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
  }
}
