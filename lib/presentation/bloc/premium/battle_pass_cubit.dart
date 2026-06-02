import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart' as db;
import 'package:cosmo_strike_flutter_app/models/battle_pass.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:get_it/get_it.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/progression_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

import 'battle_pass_state.dart';

export 'battle_pass_state.dart';

/// Cubit for managing battle pass progression
class BattlePassCubit extends Cubit<BattlePassState> {
  final StorageService _storageService;
  final PremiumCubit? _premiumCubit;
  final AnalyticsFacade _analytics;
  // Lifetime player progression runs in parallel to the battle pass. Every XP
  // grant funnels through bufferXP/flushXP, so forwarding here is the single
  // hook that feeds the player level from all the same events.
  final ProgressionService _progression;

  // Watches PremiumCubit so the moment a Pro purchase resolves we re-fetch
  // battle-pass progress and pick up the server-side HasPremium snapshot
  // (computed by BattlePassPremiumGate). Without this hook the BP screen
  // stays on a stale "Unlock with Pro" banner until the user manually
  // navigates away and back.
  StreamSubscription<PremiumState>? _premiumSub;
  bool _lastSeenHasPremium = false;

  /// Drift watch on the `battle_passes` table. Keeps the cubit's
  /// projected state in lock-step with writes from elsewhere — most
  /// importantly the first-sign-in snapshot apply, which lands cloud
  /// battle-pass progress AFTER this cubit's initialize() finished.
  /// Without the watch, tier / XP / claimed rewards stay at whatever
  /// the local row held at boot (typically the empty-table sample
  /// season) for the rest of the session.
  StreamSubscription<db.BattlePassesData?>? _battlePassWatch;
  // Tracks whether a Drift-driven reload is currently in flight so a
  // single emit doesn't race itself.
  bool _reloadingFromDrift = false;

  BattlePassCubit({
    required StorageService storageService,
    PremiumCubit? premiumCubit,
    required AnalyticsFacade analytics,
    required ProgressionService progressionService,
  }) : _storageService = storageService,
       _premiumCubit = premiumCubit,
       _analytics = analytics,
       _progression = progressionService,
       super(BattlePassState.initial());

  @override
  Future<void> close() {
    _premiumSub?.cancel();
    _battlePassWatch?.cancel();
    return super.close();
  }

  /// Initialize battle pass state — always load local first (instant), then background refresh
  Future<void> initialize() async {
    if (state.status == BattlePassStatus.ready) return;

    emit(state.copyWith(status: BattlePassStatus.loading));

    try {
      // Always load local first — instant
      await _loadFromLocalStorage();
      _syncBattlePassToPremium();

      AppLogger.info(
        'BattlePassCubit initialized from local storage. Active: ${state.isActive}, Tier: ${state.currentTier}',
      );

      // Watch Pro status — when it flips on (post-IAP verification) we
      // flip isActive locally so the premium-pass UI unlocks immediately.
      _watchPremiumCubit();
      _wireDriftWatch();
    } catch (e) {
      AppLogger.error('Error initializing BattlePassCubit', e);
      emit(
        state.copyWith(
          status: BattlePassStatus.error,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  /// Subscribe to PremiumCubit so a Pro purchase (or restore) flips
  /// `state.isActive` to true locally. In the offline-first build the
  /// premium-pass entitlement is the *only* signal for `isActive` —
  /// there's no separate backend snapshot.
  void _watchPremiumCubit() {
    final premium = _premiumCubit;
    if (premium == null) return;
    final realPremium = premium.state.hasPremium;
    _lastSeenHasPremium = realPremium;
    // Reconcile isActive to the REAL Pro entitlement in BOTH directions. The
    // old code only flipped it false→true, so a NON-Pro user whose isActive had
    // been left true (stale Drift row, a past trial, or a snapshot) stayed
    // "active" forever. That let a free user SEE premium reward chips and claim
    // them locally — the claim then reverts (the server / a reload correctly
    // rejects a premium claim from a non-premium account), producing the
    // claim→toast→reappear loop. Forcing the match hides premium claim UI from
    // free users entirely (isActive=false → isValid=false → no premium chips).
    if (realPremium != state.isActive) {
      emit(state.copyWith(isActive: realPremium));
      unawaited(_saveState());
      _syncBattlePassToPremium();
    }
    _premiumSub = premium.stream.listen((premiumState) {
      final nowPro = premiumState.hasPremium;
      if (nowPro != _lastSeenHasPremium) {
        emit(state.copyWith(isActive: nowPro));
        unawaited(_saveState());
        _syncBattlePassToPremium();
      }
      _lastSeenHasPremium = nowPro;
    });
  }

  /// Subscribe to the `battle_passes` Drift table so any write
  /// (snapshot apply on first sign-in, sync restore, server XP-grant
  /// echo) reactively re-projects into [state]. Emits immediately
  /// with the current row on subscribe, which is fine — that's the
  /// same data [_loadFromLocalStorage] just read.
  void _wireDriftWatch() {
    _battlePassWatch?.cancel();
    _battlePassWatch =
        _storageService.storeDao.watchCurrentBattlePass().listen((_) {
      if (_reloadingFromDrift) return;
      _reloadingFromDrift = true;
      _loadFromLocalStorage()
          .then((_) => _syncBattlePassToPremium())
          .catchError((Object e) {
            AppLogger.error('BattlePass Drift-watch reload failed', e);
          })
          .whenComplete(() => _reloadingFromDrift = false);
    });
  }

  /// Load from local storage (the only source in the offline-first build).
  Future<void> _loadFromLocalStorage() async {
    // Load cached season separately
    BattlePassSeason? season;
    try {
      final seasonJson = await _storageService.getCachedSeasonJson();
      if (seasonJson != null) {
        season = BattlePassSeason.fromJson(json.decode(seasonJson));
      }
    } catch (e) {
      AppLogger.error('Failed to parse cached season', e);
    }
    // Fallback to sample season if no cached season
    season ??= BattlePassSeason.createSampleSeason();

    final battlePassData = await _storageService.getBattlePassData();

    if (battlePassData != null) {
      final data = json.decode(battlePassData);
      emit(
        state.copyWith(
          status: BattlePassStatus.ready,
          isActive: data['is_active'] ?? false,
          currentTier: data['current_tier'] ?? 0,
          currentXP: data['current_xp'] ?? 0,
          xpForNextTier: data['xp_for_next_tier'] ?? 100,
          expiryDate: data['expiry_date'] != null
              ? DateTime.tryParse(data['expiry_date'])
              : null,
          claimedFreeTiers:
              (data['claimed_free_tiers'] as List<dynamic>?)
                  ?.map((e) => e as int)
                  .toSet() ??
              {},
          claimedPremiumTiers:
              (data['claimed_premium_tiers'] as List<dynamic>?)
                  ?.map((e) => e as int)
                  .toSet() ??
              {},
          seasonName: data['season_name'] ?? 'Season 1',
          season: season,
        ),
      );
    } else {
      // No cached data at all — use sample season as fallback
      emit(state.copyWith(
        status: BattlePassStatus.ready,
        season: season,
      ));
    }
  }

  /// Reload local state. Backend refresh path was removed in the
  /// offline-first refactor.
  Future<void> refresh() async {
    await _loadFromLocalStorage();
  }

  Future<void> _saveState() async {
    final data = {
      'is_active': state.isActive,
      'current_tier': state.currentTier,
      'current_xp': state.currentXP,
      'xp_for_next_tier': state.xpForNextTier,
      'expiry_date': state.expiryDate?.toIso8601String(),
      'claimed_free_tiers': state.claimedFreeTiers.toList(),
      'claimed_premium_tiers': state.claimedPremiumTiers.toList(),
      'season_name': state.seasonName,
    };
    await _storageService.setBattlePassData(json.encode(data));

    // Cache season separately
    if (state.season != null) {
      await _storageService.setCachedSeasonJson(
        json.encode(state.season!.toJson()),
      );
    }
  }

  // ==================== XP Buffering ====================
  // Buffer XP locally during gameplay, then flush once at game end.

  int _bufferedXP = 0;
  final List<String> _bufferedSources = [];

  /// Buffer XP locally without any API call. Call [flushXP] once at game end.
  void bufferXP(int xp, {String source = 'gameplay'}) {
    if (xp <= 0) return;
    // Feed lifetime player progression FIRST, before the battle-pass max-tier
    // gate below — player level is lifetime and must keep accruing even once
    // the season pass is capped (or when no season is loaded).
    _progression.bufferXp(xp, source: source);

    if (state.currentTier >= state.maxTier) return;
    _bufferedXP += xp;
    if (!_bufferedSources.contains(source)) {
      _bufferedSources.add(source);
    }
  }

  /// Flush all buffered XP in a single API call, then clear the buffer.
  Future<void> flushXP() async {
    // Always flush lifetime progression, even when there's no battle-pass XP
    // to flush (e.g. the season is maxed out).
    await _progression.flushXp();

    if (_bufferedXP <= 0) return;

    final totalXP = _bufferedXP;
    final combinedSource = _bufferedSources.join(',');

    // Clear buffer immediately to avoid double-flush
    _bufferedXP = 0;
    _bufferedSources.clear();

    await addXP(totalXP, source: combinedSource);
  }

  /// Add XP to the battle pass. Local-only in the offline-first build —
  /// tier-up math runs against the locally cached season's curve.
  Future<void> addXP(int xp, {String source = 'gameplay'}) async {
    if (state.currentTier >= state.maxTier) return;

    var newXP = state.currentXP + xp;
    final oldTier = state.currentTier;
    var newTier = state.currentTier;
    var xpForNext = state.xpForNextTier;

    while (newXP >= xpForNext && newTier < state.maxTier) {
      newXP -= xpForNext;
      newTier++;
      xpForNext = state.xpRequiredForTier(newTier);
    }

    emit(
      state.copyWith(
        currentXP: newXP,
        currentTier: newTier,
        xpForNextTier: xpForNext,
      ),
    );
    await _saveState();
    _syncBattlePassToPremium();
    if (newTier > oldTier) {
      _analytics.trackBattlePassTierReached(newTier);
    }

    AppLogger.info(
      'Added $xp XP locally ($source). New tier: $newTier, XP: $newXP/$xpForNext',
    );
  }

  /// Grant the actual item for a claimed reward via PremiumCubit
  void _grantRewardItem(BattlePassReward? reward) {
    if (reward == null || _premiumCubit == null) return;

    switch (reward.type) {
      case BattlePassRewardType.tournamentEntry:
        _premiumCubit.addTournamentEntry(
          reward.itemId ?? 'bronze',
          count: reward.quantity,
        );
        break;
      case BattlePassRewardType.skin:
        if (reward.itemId != null) {
          _premiumCubit.unlockSkin(reward.itemId!);
        }
        break;
      case BattlePassRewardType.trail:
        if (reward.itemId != null) {
          _premiumCubit.unlockTrail(reward.itemId!);
        }
        break;
      case BattlePassRewardType.powerUp:
        if (reward.itemId != null) {
          _premiumCubit.unlockPowerUp(reward.itemId!);
        }
        break;
      case BattlePassRewardType.coins:
        // Credit coins locally via CoinsCubit. Backend used to grant
        // these atomically with the claim; offline-first does it here.
        if (GetIt.I.isRegistered<CoinsCubit>()) {
          unawaited(GetIt.I<CoinsCubit>().earnCoins(
            CoinEarningSource.battlePassReward,
            customAmount: reward.quantity,
            itemName: reward.name,
          ));
        }
        break;
      case BattlePassRewardType.theme:
        // Theme unlocks require a GameTheme enum value, not a string id.
        // The local-season generator only emits cosmetic/coin rewards
        // for now, so this branch is dormant; if a season ever issues
        // a theme reward, hand the unlock off to the store flow.
        break;
      case BattlePassRewardType.xp:
        // XP rewards (e.g. "XP Boost" / "Mega XP") grant battle-pass XP so the
        // pass visibly advances when claimed. Run after this microtask so it
        // layers onto the just-emitted claimed-tiers state instead of racing
        // it. Quantities are small (15–25) relative to tier costs, so this
        // can't runaway-unlock tiers.
        unawaited(addXP(reward.quantity, source: 'battle_pass_reward'));
        break;
      case BattlePassRewardType.title:
      case BattlePassRewardType.avatar:
      case BattlePassRewardType.special:
        // Cosmetic / metadata-only — the reward record itself is
        // enough; no separate inventory bump needed.
        break;
    }
    AppLogger.info('Granted reward item: ${reward.type.name} (${reward.itemId})');
  }

  /// Claim a free-tier reward locally.
  Future<bool> claimFreeReward(int tier) async {
    if (tier > state.currentTier) return false;
    if (state.claimedFreeTiers.contains(tier)) return false;

    final updatedClaimed = {...state.claimedFreeTiers, tier};
    emit(state.copyWith(claimedFreeTiers: updatedClaimed));
    await _saveState();

    final season = state.season;
    if (season != null && tier >= 1 && tier <= season.levels.length) {
      final reward = season.levels[tier - 1].freeReward;
      _grantRewardItem(reward);
      _analytics.trackBattlePassRewardClaimed(
        tier: tier,
        rewardType: reward?.type.name ?? 'free',
      );
    }

    AppLogger.info('Claimed free reward for tier $tier');
    return true;
  }

  /// Claim a premium-tier reward locally. Gated on the user owning
  /// the premium pass — [PremiumCubit.hasPremium] is the source of
  /// truth, mirrored into [state.isActive] via [_watchPremiumCubit].
  Future<bool> claimPremiumReward(int tier) async {
    if (!state.isValid) return false;
    if (tier > state.currentTier) return false;
    if (state.claimedPremiumTiers.contains(tier)) return false;

    final updatedClaimed = {...state.claimedPremiumTiers, tier};
    emit(state.copyWith(claimedPremiumTiers: updatedClaimed));
    await _saveState();

    final season = state.season;
    if (season != null && tier >= 1 && tier <= season.levels.length) {
      final reward = season.levels[tier - 1].premiumReward;
      _grantRewardItem(reward);
      _analytics.trackBattlePassRewardClaimed(
        tier: tier,
        rewardType: reward?.type.name ?? 'premium',
      );
    }

    AppLogger.info('Claimed premium reward for tier $tier');
    return true;
  }

  /// Reset battle pass (for new season)
  Future<void> reset() async {
    emit(BattlePassState.initial().copyWith(status: BattlePassStatus.ready));
    await _saveState();
    _syncBattlePassToPremium();
    AppLogger.info('Battle pass reset for new season');
  }

  /// Push current battle pass status to PremiumCubit
  void _syncBattlePassToPremium() {
    _premiumCubit?.syncBattlePassStatus(
      isActive: state.isActive,
      tier: state.currentTier,
    );
  }

  /// Clear error
  void clearError() {
    emit(state.copyWith(clearError: true));
  }
}
