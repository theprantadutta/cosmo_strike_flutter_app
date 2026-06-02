import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart' as db;
import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart' show ChallengeDifficulty;
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/models/weekly_quest.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/battle_pass_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// Weekly quests service.
///
/// Source of truth: the backend (catalog generated weekly via the Hangfire
/// `generate-weekly-quests` job, progress via `/weekly-quests/progress`).
/// Drift mirrors only ROWS THE USER ACTUALLY INTERACTED WITH — at minimum
/// the quests they've claimed — so the screen state survives reinstall
/// and the SyncEngine has something to push to the backend's
/// UserWeeklyQuestClaim table.
///
/// Modelled tightly on [DailyChallengeService] — same shape, same lifecycle,
/// same Drift + sync queue choreography.
class WeeklyQuestService extends ChangeNotifier {
  static final WeeklyQuestService _instance = WeeklyQuestService._internal();
  factory WeeklyQuestService() => _instance;
  WeeklyQuestService._internal();

  final StorageService _storageService = StorageService();

  List<WeeklyQuest> _quests = [];
  bool _isLoading = false;
  DateTime? _lastSuccessfulRefresh;

  /// The user id whose quests are currently hydrated in memory. This is a
  /// singleton, so on a user switch (sign-out → sign-in) we must re-hydrate
  /// instead of serving the previous user's stale list.
  String? _hydratedUserId;

  List<WeeklyQuest> get quests => List.unmodifiable(_quests);
  bool get isLoading => _isLoading;

  int get completedCount => _quests.where((q) => q.isCompleted).length;
  int get claimableCount => _quests.where((q) => q.canClaim).length;
  bool get hasUnclaimedRewards =>
      _quests.any((q) => q.isCompleted && !q.claimedReward);

  /// True when the cached quest list is older than 12h. The screen uses
  /// this to hint at a stale state without forcing a blocking refresh.
  bool get isStale {
    final last = _lastSuccessfulRefresh;
    if (last == null) return true;
    return DateTime.now().difference(last) > const Duration(hours: 12);
  }

  /// Idempotent. Re-hydrates from Drift and triggers a background refresh
  /// from the backend if the user is authenticated. Safe to call from
  /// build() — only loads if not already loaded.
  Future<void> initialize() async {
    final currentUserId = ApiService().currentUserId;
    if (_quests.isNotEmpty && _hydratedUserId == currentUserId) {
      // Already hydrated for this user — let a manual refresh handle
      // staleness.
      return;
    }
    await _hydrateFromDrift();
    _hydratedUserId = currentUserId;
    if (ApiService().isAuthenticated) {
      // Fire-and-forget — never block UI on the network round-trip.
      unawaited(refresh());
    }
  }

  /// Pull-to-refresh entry point. Fetches the current week's quests from
  /// the backend, persists them to Drift (without enqueuing sync rows
  /// — these came FROM the backend), and rebuilds the in-memory list.
  /// Failures leave the previous list in place so offline doesn't blank
  /// the screen.
  Future<void> refresh() async {
    if (!ApiService().isAuthenticated) return;
    _isLoading = true;
    notifyListeners();
    try {
      final body = await ApiService().getCurrentWeeklyQuestsRemote();
      if (body == null) return;
      final raw = body['quests'] ?? body['weekly_quests'] ?? body['data'];
      if (raw is! List) {
        AppLogger.warning(
          'WeeklyQuestService.refresh: missing quests list in response',
        );
        return;
      }

      final parsed = <WeeklyQuest>[];
      for (final entry in raw) {
        if (entry is! Map<String, dynamic>) continue;
        try {
          parsed.add(WeeklyQuest.fromJson(entry));
        } catch (e) {
          AppLogger.warning(
            'WeeklyQuestService.refresh: skipping malformed entry: $e',
          );
        }
      }

      // Reconcile each backend quest against its local Drift row, which is
      // the offline-durable source of truth. currentProgress is monotonic so
      // we take MAX (client-ahead offline gains win); isCompleted /
      // claimedReward are absorbing-true. Without the MAX-merge a refresh
      // would clobber progress the client earned offline but hasn't pushed.
      final localById = await _loadLocalById();
      _quests = [
        for (final q in parsed) _mergeWithLocal(q, localById[q.id]),
      ];

      // Persist the reconciled quests to Drift so the next cold-start can
      // hydrate from cache without a network round-trip. enqueueSync: false —
      // the backend half came FROM the backend, and any client-ahead delta
      // already carries its own outbox row from when reportProgressBatch
      // wrote it.
      for (final q in _quests) {
        await _storageService.gameDao.upsertWeeklyQuest(
          _toCompanion(q),
          enqueueSync: false,
        );
      }

      _lastSuccessfulRefresh = DateTime.now();
    } catch (e) {
      AppLogger.error('WeeklyQuestService.refresh errored', e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Local Drift quest rows keyed by quest id — the offline-durable source
  /// of truth used to reconcile a backend refresh (see [_mergeWithLocal]).
  Future<Map<String, db.WeeklyQuest>> _loadLocalById() async {
    try {
      final rows = await _storageService.gameDao.getAllWeeklyQuests();
      return {for (final r in rows) r.questId: r};
    } catch (e) {
      AppLogger.error('WeeklyQuestService: error loading local quests', e);
      return const {};
    }
  }

  /// Reconcile a backend quest with its local Drift row: MAX on the
  /// monotonic progress (client-ahead wins), OR on the absorbing-true
  /// completed / claimed flags. Claimed implies completed.
  WeeklyQuest _mergeWithLocal(WeeklyQuest backend, db.WeeklyQuest? local) {
    if (local == null) return backend;
    final mergedProgress = local.currentProgress > backend.currentProgress
        ? local.currentProgress
        : backend.currentProgress;
    final mergedClaimed = backend.claimedReward || local.claimedReward;
    final mergedCompleted = mergedClaimed ||
        backend.isCompleted ||
        local.isCompleted ||
        mergedProgress >= backend.targetValue;
    return backend.copyWith(
      currentProgress: mergedProgress,
      isCompleted: mergedCompleted,
      claimedReward: mergedClaimed,
    );
  }

  Future<void> _hydrateFromDrift() async {
    try {
      final rows = await _storageService.gameDao
          .getWeeklyQuestsForWeek(reference: DateTime.now());
      _quests = rows.map(_fromRow).toList();
      notifyListeners();
    } catch (e) {
      AppLogger.error('WeeklyQuestService: hydrate from Drift failed', e);
    }
  }

  /// Single-type progress increment — used when only one quest type can
  /// possibly match the event. Most game-end paths use the batch variant.
  Future<void> reportProgress({
    required WeeklyQuestType type,
    required int incrementBy,
    String? gameMode,
  }) async {
    if (incrementBy <= 0) return;
    await reportProgressBatch([
      (type: type, incrementBy: incrementBy, gameMode: gameMode),
    ]);
  }

  /// Batched per-game progress events. Offline-first: the canonical write
  /// is Drift (which enqueues a sync_outbox row), so progress survives an
  /// app-kill or offline window and the SyncEngine pushes the live snapshot
  /// to the backend's UserWeeklyQuestClaim mirror on the next online tick.
  /// The in-memory list is updated optimistically so the UI reflects the
  /// gain immediately.
  Future<void> reportProgressBatch(
    List<({WeeklyQuestType type, int incrementBy, String? gameMode})> updates,
  ) async {
    final positive = updates.where((u) => u.incrementBy > 0).toList();
    if (positive.isEmpty) return;

    // 1. Optimistic in-memory update — apply the deltas so the user sees the
    //    bump right away, and collect the quests that actually changed.
    final changed = <String, WeeklyQuest>{};
    for (final u in positive) {
      for (final q
          in _applyLocalProgress(u.type, u.incrementBy, gameMode: u.gameMode)) {
        changed[q.id] = q; // last state wins if several updates touch one quest
      }
    }
    notifyListeners();
    if (changed.isEmpty) return;

    // 2. Canonical write: persist each changed quest to Drift. upsertWeeklyQuest
    //    enqueues a weekly_quest_claim outbox row in the same transaction, so
    //    the SyncEngine drains it and pushes the snapshot when online. This is
    //    the offline-durable source of truth — no SharedPreferences, no direct
    //    API dependency for the write to land.
    for (final quest in changed.values) {
      try {
        await _storageService.gameDao.upsertWeeklyQuest(_toCompanion(quest));
      } catch (e) {
        AppLogger.error(
          'WeeklyQuestService.reportProgressBatch: Drift persist failed',
          e,
        );
      }
    }

    // 3. Best-effort duplicate signal to the legacy /weekly-quests/progress
    //    endpoint, which keeps the gameplay-side UserWeeklyQuest table warm.
    //    NOT the canonical path (that's Drift + outbox above) — purely a
    //    redundant nudge, safely skipped when offline / unauthenticated.
    if (ApiService().isAuthenticated) {
      try {
        await ApiService().updateWeeklyQuestProgressBatch(
          positive
              .map((u) => {
                    'type': u.type.apiValue,
                    'increment_by': u.incrementBy,
                    if (u.gameMode != null) 'game_mode': u.gameMode,
                  })
              .toList(),
        );
      } catch (e) {
        AppLogger.error(
          'WeeklyQuestService.reportProgressBatch: legacy progress push errored',
          e,
        );
      }
    }
  }

  /// Applies the delta to matching in-memory quests and returns the quests
  /// that actually changed, so the caller can persist exactly those to Drift.
  List<WeeklyQuest> _applyLocalProgress(WeeklyQuestType type, int incrementBy,
      {String? gameMode}) {
    final changed = <WeeklyQuest>[];
    for (int i = 0; i < _quests.length; i++) {
      final quest = _quests[i];
      if (quest.type != type) continue;
      if (quest.isCompleted) continue;
      if (type == WeeklyQuestType.gameMode &&
          quest.requiredGameMode != null &&
          gameMode != null &&
          quest.requiredGameMode!.toLowerCase() != gameMode.toLowerCase()) {
        continue;
      }

      int newProgress;
      if (type == WeeklyQuestType.score || type == WeeklyQuestType.survival) {
        // Max-wins semantics for high-water-mark quest types.
        newProgress = incrementBy > quest.currentProgress
            ? incrementBy
            : quest.currentProgress;
      } else {
        newProgress = quest.currentProgress + incrementBy;
      }
      final isNowCompleted = newProgress >= quest.targetValue;

      // Skip no-op updates (e.g. a lower score for a max-wins quest) so we
      // don't churn the Drift row / sync outbox for nothing.
      if (newProgress == quest.currentProgress &&
          isNowCompleted == quest.isCompleted) {
        continue;
      }

      final updated = quest.copyWith(
        currentProgress: newProgress,
        isCompleted: isNowCompleted,
      );
      _quests[i] = updated;
      changed.add(updated);
    }
    return changed;
  }

  /// Claim a completed quest. Writes the row to Drift (the sync engine
  /// drains it to the backend's UserWeeklyQuestClaim), credits coins +
  /// battle-pass XP via the in-app cubits, and returns true on success.
  Future<bool> claimReward(String questId) async {
    final index = _quests.indexWhere((q) => q.id == questId);
    if (index < 0) return false;

    final quest = _quests[index];
    if (!quest.isCompleted || quest.claimedReward) return false;

    final claimed = quest.copyWith(
      claimedReward: true,
      completedAt: quest.completedAt ?? DateTime.now(),
    );
    _quests[index] = claimed;
    await _persistClaim(claimed);

    // Optimistic credit — the backend's /weekly-quests/claim endpoint is
    // the authoritative source for the actual coin transfer, but we
    // credit locally so the UI doesn't lag waiting on the network.
    if (claimed.coinReward > 0 && GetIt.I.isRegistered<CoinsCubit>()) {
      await GetIt.I<CoinsCubit>().earnCoins(
        CoinEarningSource.dailyChallenge, // closest existing source
        customAmount: claimed.coinReward,
        itemName: claimed.title,
      );
    }

    _grantBattlePassXp(claimed.battlePassXpReward);

    // Server-side acknowledgement — fire-and-forget. If the server
    // disagrees (already claimed elsewhere, expired, etc.) the next
    // refresh will reconcile the local state.
    if (ApiService().isAuthenticated) {
      unawaited(ApiService().claimWeeklyQuestRewardRemote(claimed.id));
    }

    notifyListeners();
    return true;
  }

  Future<void> _persistClaim(WeeklyQuest quest) async {
    try {
      await _storageService.gameDao.upsertWeeklyQuest(
        _toCompanion(quest),
      );
    } catch (e) {
      AppLogger.error('Error persisting claimed weekly quest to Drift', e);
    }
  }

  void _grantBattlePassXp(int xp) {
    if (xp <= 0) return;
    if (!GetIt.I.isRegistered<BattlePassCubit>()) return;
    final cubit = GetIt.I<BattlePassCubit>();
    // bufferXP source is a free-form string used for analytics/audit;
    // mirrors the daily_challenge source string used elsewhere.
    cubit.bufferXP(xp, source: 'weekly_quest');
    cubit.flushXP();
  }

  // ---------------------------------------------------------------------------
  // Drift <-> model conversions
  // ---------------------------------------------------------------------------

  WeeklyQuest _fromRow(db.WeeklyQuest row) {
    return WeeklyQuest(
      id: row.questId,
      weekStartDate: row.weekStartDate,
      type: WeeklyQuestType.fromString(row.questType),
      difficulty: ChallengeDifficulty.easy, // Drift mirror doesn't track this
      title: row.title,
      description: row.description,
      targetValue: row.targetValue,
      currentProgress: row.currentProgress,
      isCompleted: row.isCompleted,
      claimedReward: row.claimedReward,
      coinReward: row.coinReward,
      battlePassXpReward: row.battlePassXpReward,
      completedAt: row.completedAt,
    );
  }

  db.WeeklyQuestsCompanion _toCompanion(WeeklyQuest q) {
    return db.WeeklyQuestsCompanion(
      questId: Value(q.id),
      questType: Value(q.type.apiValue),
      title: Value(q.title),
      description: Value(q.description),
      currentProgress: Value(q.currentProgress),
      targetValue: Value(q.targetValue),
      coinReward: Value(q.coinReward),
      battlePassXpReward: Value(q.battlePassXpReward),
      isCompleted: Value(q.isCompleted),
      claimedReward: Value(q.claimedReward),
      weekStartDate: Value(q.weekStartDate),
      completedAt: Value(q.completedAt),
    );
  }
}
