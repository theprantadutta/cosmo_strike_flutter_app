import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart' as db;
import 'package:cosmo_strike_flutter_app/models/battle_pass.dart';
import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';
import 'package:cosmo_strike_flutter_app/models/snake_coins.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/battle_pass_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// Daily challenges service.
///
/// Source of truth (eventually): the backend generator. Until that's
/// wired up the in-memory list is empty — the screen just shows the
/// empty state.
///
/// Offline-first: both progress AND claims are written to Drift, which
/// enqueues a `dailyChallengeClaim` sync_outbox row in the same
/// transaction. So in-session progress survives an app-kill / offline
/// window, and the SyncEngine pushes the live snapshot (progress + claim
/// state) to the backend's UserDailyChallengeClaims mirror on the next
/// online tick. The in-memory list is the optimistic UI mirror that the
/// screen renders; the next backend refresh reconciles it.
class DailyChallengeService extends ChangeNotifier {
  static final DailyChallengeService _instance =
      DailyChallengeService._internal();
  factory DailyChallengeService() => _instance;
  DailyChallengeService._internal();

  final StorageService _storageService = StorageService();

  // Flat coin + XP bonus granted exactly once on the day the player
  // completes every daily challenge. Persisted as a synthetic
  // [DailyChallenge] row in Drift (id = 'all_complete_bonus_$YYYY-MM-DD')
  // so the existing dailyChallengeClaim sync push carries it to the
  // backend mirror automatically — no new outbox dataType needed.
  static const int allCompleteBonusCoins = 50;
  static const int allCompleteBonusXp = 100;

  List<DailyChallenge> _challenges = [];
  int _completedCount = 0;
  int _totalCount = 0;
  bool _allCompleted = false;
  bool _bonusClaimedToday = false;
  // ignore: prefer_final_fields
  bool _isLoading = false;
  String? _lastLoadDate;

  List<DailyChallenge> get challenges => _challenges;
  int get completedCount => _completedCount;
  int get totalCount => _totalCount;
  bool get allCompleted => _allCompleted;
  int get bonusCoins => allCompleteBonusCoins;
  int get bonusXp => allCompleteBonusXp;
  bool get isBonusClaimed => _bonusClaimedToday;
  bool get isLoading => _isLoading;

  bool get hasUnclaimedRewards =>
      _challenges.any((c) => c.isCompleted && !c.claimedReward) ||
      (_allCompleted && !_bonusClaimedToday);

  int get unclaimedRewardsCount =>
      _challenges.where((c) => c.isCompleted && !c.claimedReward).length;

  Future<void> initialize() async {
    // Nothing to load locally — challenges arrive from the backend
    // call we haven't wired yet. Claimed rows live in Drift but we
    // don't surface them on the daily-challenges screen because the
    // screen wants the full *today's* catalog, not the user's history.
  }

  /// Fetch today's daily challenges from the backend and apply them
  /// to the in-memory list via [setChallengesFromBackend]. When the
  /// request fails (offline / 5xx) the in-memory list is left as-is
  /// — the screen continues to show whatever the previous successful
  /// refresh produced, or an empty state on a first-launch offline.
  Future<void> refreshChallenges() async {
    if (!ApiService().isAuthenticated) return;
    _isLoading = true;
    notifyListeners();
    try {
      final body = await ApiService().getTodaysChallengesRemote();
      if (body == null) return;
      final raw = body['challenges'];
      if (raw is! List) {
        AppLogger.warning(
          'DailyChallengeService.refreshChallenges: missing challenges list',
        );
        return;
      }
      final parsed = <DailyChallenge>[];
      for (final entry in raw) {
        if (entry is! Map<String, dynamic>) continue;
        try {
          parsed.add(DailyChallenge.fromJson(entry));
        } catch (e) {
          AppLogger.warning(
            'DailyChallengeService.refreshChallenges: skipping malformed entry: $e',
          );
        }
      }
      await setChallengesFromBackend(parsed);
    } catch (e) {
      AppLogger.error('DailyChallengeService.refreshChallenges errored', e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Entry point for the backend wiring: feed the freshly-fetched
  /// challenge list in, and mark any whose claim is already recorded
  /// in Drift as claimed so the UI doesn't ask the user to claim
  /// twice across reinstalls.
  Future<void> setChallengesFromBackend(
    List<DailyChallenge> fromBackend,
  ) async {
    // Reconcile each backend challenge against its local Drift row, which is
    // the offline-durable source of truth. currentProgress is monotonic so we
    // take MAX (client-ahead offline gains win); isCompleted / claimedReward
    // are absorbing-true. Without the MAX-merge a refresh would clobber
    // progress the client earned offline but hasn't pushed yet.
    final localById = await _loadTodaysLocalById();

    _challenges = [
      for (final c in fromBackend) _mergeWithLocal(c, localById[c.id]),
    ];
    _totalCount = _challenges.length;
    _completedCount = _challenges.where((c) => c.isCompleted).length;
    _allCompleted = _completedCount == _totalCount && _totalCount > 0;
    // The synthetic bonus row uses today's local-day-anchored id; if
    // it's already in Drift (this device claimed earlier OR another
    // device claimed and the cold-start sync pulled it in) the bonus
    // is locked.
    _bonusClaimedToday = localById[_todayBonusId()]?.rewardClaimed ?? false;
    _lastLoadDate = DateTime.now().toIso8601String().split('T')[0];

    // Persist the reconciled challenges to Drift so its rows reflect the
    // merged state (e.g. a backend-ahead value from another device lands
    // locally). enqueueSync: false — any client-ahead delta already carries
    // its own outbox row from updateProgress.
    for (final c in _challenges) {
      try {
        await _storageService.gameDao
            .upsertDailyChallenge(_toCompanion(c), enqueueSync: false);
      } catch (e) {
        AppLogger.error('DailyChallengeService: refresh persist failed', e);
      }
    }
    notifyListeners();
  }

  /// Today's local Drift challenge rows keyed by challenge id — the
  /// offline-durable source of truth used to reconcile a backend refresh.
  Future<Map<String, db.DailyChallenge>> _loadTodaysLocalById() async {
    try {
      final rows = await _storageService.gameDao.getTodaysChallenges();
      return {for (final r in rows) r.challengeId: r};
    } catch (e) {
      AppLogger.error('Error loading local challenges', e);
      return const {};
    }
  }

  /// Reconcile a backend challenge with its local Drift row: MAX on the
  /// monotonic progress (client-ahead wins), OR on the absorbing-true
  /// completed / claimed flags. Claimed implies completed.
  DailyChallenge _mergeWithLocal(
    DailyChallenge backend,
    db.DailyChallenge? local,
  ) {
    if (local == null) return backend;
    final mergedProgress = local.currentProgress > backend.currentProgress
        ? local.currentProgress
        : backend.currentProgress;
    final mergedClaimed = backend.claimedReward || local.rewardClaimed;
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

  /// Synthetic challenge id for today's all-complete bonus. Local-day
  /// anchored so a new day creates a new claim row even if the user
  /// completed yesterday's challenges. Stays stable across app launches
  /// within the same calendar day.
  static String _todayBonusId() {
    final today = DateTime.now();
    final y = today.year.toString().padLeft(4, '0');
    final m = today.month.toString().padLeft(2, '0');
    final d = today.day.toString().padLeft(2, '0');
    return 'all_complete_bonus_$y-$m-$d';
  }

  /// Auto-credit the all-complete bonus on the first claim that lands
  /// after every daily challenge is completed. Idempotent — the Drift
  /// upsert + the in-memory flag guarantee at-most-once per local day.
  Future<void> _tryAutoClaimAllCompleteBonus() async {
    if (!_allCompleted || _bonusClaimedToday) return;
    if (_totalCount == 0) return; // sanity: never bonus on an empty set
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final bonusId = _todayBonusId();

      // Drift gate + sync push in one shot. The existing
      // dailyChallengeClaim outbox dataType carries this row to the
      // backend's UserDailyChallengeClaims mirror table, so the
      // dashboard sees the bonus as a regular claimed row and other
      // devices pick it up on their next pull.
      await _storageService.gameDao.upsertDailyChallenge(
        db.DailyChallengesCompanion(
          challengeId: Value(bonusId),
          challengeType: const Value('bonus'),
          title: const Value('All Challenges Bonus'),
          description: const Value(
            'Completed every daily challenge today.',
          ),
          currentProgress: const Value(1),
          targetProgress: const Value(1),
          rewardCoins: const Value(allCompleteBonusCoins),
          isCompleted: const Value(true),
          rewardClaimed: const Value(true),
          challengeDate: Value(startOfDay),
          expiresAt: Value(endOfDay),
          completedAt: Value(today),
        ),
      );

      if (GetIt.I.isRegistered<CoinsCubit>()) {
        await GetIt.I<CoinsCubit>().earnCoins(
          CoinEarningSource.dailyChallenge,
          customAmount: allCompleteBonusCoins,
          itemName: 'All Challenges Bonus',
          metadata: {'bonus_id': bonusId},
        );
      }

      // Grant the dedicated all-complete bonus XP (not the per-challenge
      // 'daily_challenge' amount, which is far smaller). bonusXp == 100.
      if (GetIt.I.isRegistered<BattlePassCubit>()) {
        final cubit = GetIt.I<BattlePassCubit>();
        cubit.bufferXP(allCompleteBonusXp, source: 'all_complete_bonus');
        cubit.flushXP();
      }

      _bonusClaimedToday = true;
      AppLogger.info(
        'All-challenges bonus auto-claimed: +$allCompleteBonusCoins coins '
        '(bonusId=$bonusId)',
      );
    } catch (e) {
      AppLogger.error('Failed to auto-claim all-complete bonus', e);
    }
  }

  /// Update progress for a specific challenge type. Offline-first: the
  /// in-memory list is updated optimistically and the changed challenges
  /// are persisted to Drift (which enqueues a sync_outbox row), so the
  /// gain survives an app-kill / offline window and reaches the backend
  /// mirror via the SyncEngine.
  Future<void> updateProgress(
    ChallengeType type,
    int value, {
    String? gameMode,
  }) async {
    if (value <= 0) return;
    final changed = _updateLocalProgress(type, value, gameMode: gameMode);
    notifyListeners();
    await _persistProgress(changed);
  }

  /// Batched per-game progress update.
  Future<void> updateProgressBatch(
    List<({ChallengeType type, int value, String? gameMode})> updates,
  ) async {
    if (updates.isEmpty) return;
    final changed = <String, DailyChallenge>{};
    for (final update in updates) {
      if (update.value <= 0) continue;
      for (final c in _updateLocalProgress(update.type, update.value,
          gameMode: update.gameMode)) {
        changed[c.id] = c; // last state wins if updates touch the same one
      }
    }
    notifyListeners();
    await _persistProgress(changed.values);
  }

  /// Applies the delta to matching in-memory challenges and returns the
  /// ones that actually changed, so the caller can persist exactly those.
  List<DailyChallenge> _updateLocalProgress(ChallengeType type, int value,
      {String? gameMode}) {
    final changed = <DailyChallenge>[];
    for (int i = 0; i < _challenges.length; i++) {
      final challenge = _challenges[i];

      if (challenge.type != type) continue;
      if (challenge.isCompleted) continue;

      if (type == ChallengeType.gameMode &&
          challenge.requiredGameMode != null &&
          gameMode != null &&
          challenge.requiredGameMode!.toLowerCase() != gameMode.toLowerCase()) {
        continue;
      }

      int newProgress;
      if (type == ChallengeType.score || type == ChallengeType.survival) {
        // Take max value for score/survival — keep the user's actual peak
        // because "scored 230 against a 200 target" is a meaningful flex
        // worth preserving in the mirror.
        newProgress = value > challenge.currentProgress
            ? value
            : challenge.currentProgress;
      } else {
        // Cumulative challenges (games played, foods eaten, etc.) — cap at
        // target so the synced mirror doesn't end up with values like
        // "125 / 10" once the user keeps playing after the daily goal hits.
        // Overshoot has no semantic value here (challenge is done at first
        // crossing) and reads as a bug on the admin dashboard.
        final raw = challenge.currentProgress + value;
        newProgress =
            raw > challenge.targetValue ? challenge.targetValue : raw;
      }

      final isNowCompleted = newProgress >= challenge.targetValue;

      // Skip no-op updates (e.g. a lower score for a max-wins challenge) so
      // we don't churn the Drift row / sync outbox for nothing.
      if (newProgress == challenge.currentProgress &&
          isNowCompleted == challenge.isCompleted) {
        continue;
      }

      final updated = challenge.copyWith(
        currentProgress: newProgress,
        isCompleted: isNowCompleted,
      );
      _challenges[i] = updated;
      changed.add(updated);
    }

    _completedCount = _challenges.where((c) => c.isCompleted).length;
    _allCompleted = _completedCount == _totalCount && _totalCount > 0;
    return changed;
  }

  /// Persist changed challenges to Drift. upsertDailyChallenge enqueues a
  /// dailyChallengeClaim outbox row in the same transaction, so the
  /// SyncEngine drains it and pushes the snapshot when online. This is the
  /// offline-durable source of truth for in-progress challenges.
  Future<void> _persistProgress(Iterable<DailyChallenge> challenges) async {
    for (final c in challenges) {
      try {
        await _storageService.gameDao.upsertDailyChallenge(_toCompanion(c));
      } catch (e) {
        AppLogger.error(
          'DailyChallengeService: progress persist to Drift failed',
          e,
        );
      }
    }
  }

  /// Build a Drift companion from a challenge's current state. The day
  /// anchors (challengeDate / expiresAt) mirror [_persistClaim]; rewardClaimed
  /// and completedAt reflect the live challenge rather than being forced.
  db.DailyChallengesCompanion _toCompanion(DailyChallenge c) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return db.DailyChallengesCompanion(
      challengeId: Value(c.id),
      challengeType: Value(c.type.apiValue),
      title: Value(c.title),
      description: Value(c.description),
      currentProgress: Value(c.currentProgress),
      targetProgress: Value(c.targetValue),
      rewardCoins: Value(c.coinReward),
      isCompleted: Value(c.isCompleted),
      rewardClaimed: Value(c.claimedReward),
      challengeDate: Value(startOfDay),
      expiresAt: Value(endOfDay),
      completedAt: c.isCompleted ? Value(today) : const Value.absent(),
    );
  }

  /// Claim a single completed challenge. Writes the row to Drift (the
  /// only thing that *does* get persisted locally), credits the coin
  /// reward, and grants battle-pass XP.
  Future<bool> claimReward(String challengeId) async {
    final index = _challenges.indexWhere((c) => c.id == challengeId);
    if (index < 0) return false;

    final challenge = _challenges[index];
    if (!challenge.isCompleted || challenge.claimedReward) return false;

    _challenges[index] = challenge.copyWith(claimedReward: true);
    await _persistClaim(_challenges[index]);

    if (challenge.coinReward > 0 && GetIt.I.isRegistered<CoinsCubit>()) {
      await GetIt.I<CoinsCubit>().earnCoins(
        CoinEarningSource.dailyChallenge,
        customAmount: challenge.coinReward,
        itemName: challenge.title,
      );
    }

    _grantBattlePassXp(['daily_challenge']);

    // If this claim made the user all-complete (or they already were
    // and this is the first claim since), credit the bonus too.
    await _tryAutoClaimAllCompleteBonus();

    notifyListeners();
    return true;
  }

  /// Claim every unclaimed-but-completed challenge in one go.
  Future<int> claimAllRewards() async {
    final claimable = _challenges.where((c) => c.canClaim).toList();
    if (claimable.isEmpty) return 0;

    int totalClaimed = 0;
    for (final challenge in claimable) {
      final index = _challenges.indexWhere((c) => c.id == challenge.id);
      if (index < 0) continue;
      _challenges[index] = challenge.copyWith(claimedReward: true);
      await _persistClaim(_challenges[index]);
      totalClaimed += challenge.coinReward;
    }

    if (totalClaimed > 0 && GetIt.I.isRegistered<CoinsCubit>()) {
      await GetIt.I<CoinsCubit>().earnCoins(
        CoinEarningSource.dailyChallenge,
        customAmount: totalClaimed,
        itemName: 'Daily challenges',
      );
    }

    _grantBattlePassXp(
      List<String>.filled(claimable.length, 'daily_challenge'),
    );

    // Auto-claim the all-complete bonus if every challenge is done.
    await _tryAutoClaimAllCompleteBonus();

    notifyListeners();
    return totalClaimed;
  }

  Future<void> _persistClaim(DailyChallenge challenge) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      await _storageService.gameDao.upsertDailyChallenge(
        db.DailyChallengesCompanion(
          challengeId: Value(challenge.id),
          challengeType: Value(challenge.type.apiValue),
          title: Value(challenge.title),
          description: Value(challenge.description),
          currentProgress: Value(challenge.currentProgress),
          targetProgress: Value(challenge.targetValue),
          rewardCoins: Value(challenge.coinReward),
          isCompleted: Value(challenge.isCompleted),
          rewardClaimed: const Value(true),
          challengeDate: Value(startOfDay),
          expiresAt: Value(endOfDay),
          completedAt: Value(today),
        ),
      );
    } catch (e) {
      AppLogger.error('Error persisting claimed challenge to Drift', e);
    }
  }

  /// Buffer + flush battle-pass XP for one or more claim sources.
  /// Fire-and-forget: failure here must not roll back the user-visible claim.
  void _grantBattlePassXp(List<String> sources) {
    if (sources.isEmpty) return;
    if (!GetIt.I.isRegistered<BattlePassCubit>()) return;
    final cubit = GetIt.I<BattlePassCubit>();
    for (final source in sources) {
      final xp = BattlePassXpSource.getXpForAction(source);
      if (xp > 0) cubit.bufferXP(xp, source: source);
    }
    cubit.flushXP();
  }

  /// Legacy entry point. In the offline-first build "sync" = re-fetch
  /// from the backend, so this is a thin alias for [refreshChallenges].
  Future<void> syncWithBackend() async {
    await refreshChallenges();
  }

  /// True when the in-memory snapshot is stale and the screen should
  /// kick a refresh.
  bool get needsRefresh {
    final today = DateTime.now().toIso8601String().split('T')[0];
    return _lastLoadDate != today || _challenges.isEmpty;
  }

  DailyChallenge? getChallengeById(String id) {
    try {
      return _challenges.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Clear in-memory state. Doesn't touch Drift — claimed rows are
  /// historical and stay.
  Future<void> clearCache() async {
    _challenges = [];
    _completedCount = 0;
    _totalCount = 0;
    _allCompleted = false;
    _bonusClaimedToday = false;
    _lastLoadDate = null;
    notifyListeners();
  }
}
