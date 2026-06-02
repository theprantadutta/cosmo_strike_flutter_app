import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cosmo_strike_flutter_app/data/daos/store_dao.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart' as db;
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

import 'coins_state.dart';

export 'coins_state.dart';

/// Cubit for managing in-game coin economy.
///
/// **Storage model (offline-first, single source of truth per data point):**
/// the coin balance and transaction history live in Drift — the `Coins`
/// and `CoinTransactions` tables, owned by [StoreDao]. The SyncEngine
/// pushes both to the backend through the `coin_balance` and
/// `coin_transaction` outbox dataTypes. This cubit is a *read* layer
/// over Drift: every mutation routes through StoreDao, and the cubit
/// subscribes to Drift's watch streams to keep state in lock-step with
/// the database. The dashboard's `UserCoinBalance.Balance` and the
/// Flutter UI therefore can never disagree, because they're both
/// downstream of the same Drift row.
///
/// **SharedPreferences usage** is limited strictly to device-only state
/// that never leaves the install:
///   * `daily_earnings` / `last_earning_reset` — anti-grind cap
///     (resets at UTC midnight; a fresh device gets a fresh cap by
///     design).
///
/// Daily login bonus state lived in SharedPreferences in an earlier
/// build (`daily_bonuses`, `last_daily_bonus_claim_date`) but is now
/// Drift-first via the `daily_bonus_state` singleton table — the
/// SyncEngine pushes it to the backend's DailyLoginBonus table, so the
/// gate is multi-device consistent. The legacy keys are cleared by a
/// one-shot migration in [initialize].
class CoinsCubit extends Cubit<CoinsState> {
  CoinsCubit() : super(CoinsState.initial());

  SharedPreferences? _prefs;

  StreamSubscription<db.Coin?>? _coinsRowWatch;
  StreamSubscription<List<db.CoinTransaction>>? _transactionsWatch;
  StreamSubscription<db.DailyBonusStateData?>? _dailyBonusWatch;

  /// Tracks the in-flight initialize() call so concurrent callers
  /// (notably AuthCubit._firePostAuthSyncs → syncWithBackend) await
  /// the same completion instead of either short-circuiting on the
  /// status guard or starting a second parallel init. Without this,
  /// syncWithBackend ran against state.balance = CoinBalance.initial
  /// (50) before initialize had a chance to load Drift, and the sync
  /// log misreported "local=50, server=N (synced)" while overwriting
  /// Drift with the server value.
  Completer<void>? _initCompleter;

  // Device-only SharedPreferences keys. Any synced state moved to Drift.
  static const String _dailyEarningsKey = 'daily_earnings';
  static const String _lastEarningResetKey = 'last_earning_reset';
  // Retired daily-bonus prefs keys — daily bonus is now Drift-first
  // (`daily_bonus_state` table). Kept as constants so the one-shot
  // migration in [initialize] can find and clean up the legacy values.
  static const String _legacyDailyBonusesKey = 'daily_bonuses';
  static const String _legacyLastBonusClaimDateKey = 'last_daily_bonus_claim_date';

  /// Retired SharedPreferences keys — the Drift-first refactor moves
  /// balance and transactions into Drift. Kept here so the one-shot
  /// migration in [initialize] can find any legacy data, fold it into
  /// Drift, and then remove the keys.
  static const String _legacyBalanceKey = 'coin_balance';
  static const String _legacyTransactionsKey = 'coin_transactions';

  /// Initialize the coins cubit
  Future<void> initialize() async {
    if (state.status == CoinsStatus.ready) return;
    // Coalesce a concurrent call onto the existing init future. Both
    // main.dart's BlocProvider.create and syncWithBackend's eager
    // await can land here in the same frame; without this guard the
    // second caller would also pass the status check (state is
    // "loading", not "ready") and run the full migration/seed/load
    // sequence in parallel.
    final inFlight = _initCompleter;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<void>();
    _initCompleter = completer;

    emit(state.copyWith(status: CoinsStatus.loading));

    try {
      _prefs = await SharedPreferences.getInstance();

      // One-shot: any legacy SharedPreferences balance from the
      // dual-write era gets folded into Drift, then the retired keys
      // are cleared. After this runs once on a given install, Drift
      // is the sole owner of balance + transactions.
      await _migrateLegacySharedPreferencesToDrift();

      // The +50 starting bonus is NOT seeded here — that was a foot-gun
      // for returning users signing in on a fresh device, because the
      // seed would race the cloud restore and risk overwriting their
      // actual server balance. The seed now lives inside the SyncEngine's
      // brandNew branch (see [seedStartingBonus]), so it only fires for
      // users the backend just minted.

      // Drain the legacy SharedPreferences daily-bonus keys into the new
      // Drift singleton (one-shot per install). Runs BEFORE the initial
      // Drift seed so [_loadFromDrift] already sees the migrated row.
      await _migrateLegacyDailyBonusToDrift();
      await _loadFromDrift();
      await _loadDailyEarningsCap();
      _wireDriftWatches();

      emit(state.copyWith(status: CoinsStatus.ready));
      AppLogger.info(
        'CoinsCubit initialized (Drift-first). Balance: ${state.balance.total}',
      );

      // Backend reconcile is no longer fired here — AuthCubit triggers
      // syncWithBackend after the user is authenticated and the JWT is
      // valid (see AuthCubit._firePostAuthSyncs). Firing here would race
      // with auth and consistently 401 on first launch.
      completer.complete();
    } catch (e) {
      AppLogger.error('Error initializing CoinsCubit', e);
      emit(
        state.copyWith(status: CoinsStatus.error, errorMessage: e.toString()),
      );
      completer.complete(); // Surface to awaiters; sync will skip via the
      // status guard if init failed.
    }
  }

  /// Pull `User.Coins` from the backend and reconcile with local balance.
  ///
  /// Strategy: take max(local, server). When server is ahead, write the
  /// new balance via [StoreDao.applyCoinBalanceSnapshot] — which skips
  /// the outbox so the server's number doesn't echo back as a push.
  /// The watch stream re-emits and the UI updates. Local-ahead is
  /// preserved; the next outbox drain will push the missing delta.
  Future<void> syncWithBackend() async {
    try {
      // Block on initialize() so state.balance reflects Drift, not the
      // CoinBalance.initial seed. AuthCubit._firePostAuthSyncs fires
      // this method as soon as auth resolves, which can land seconds
      // before the BlocProvider's init has loaded from Drift. Without
      // this await, local=50 races server=N and the wrong branch wins:
      // applyCoinBalanceSnapshot would overwrite Drift's real value
      // with the server's, AND the log would lie about the "before"
      // balance.
      await initialize();
      if (state.status != CoinsStatus.ready) return;

      final apiService = ApiService();
      if (!apiService.isAuthenticated) return;

      final data = await apiService.getCurrentUser();
      if (data == null) return;

      final serverCoins = (data['coins'] as int?) ?? 0;
      final localTotal = state.balance.total;

      if (serverCoins == localTotal) {
        AppLogger.info(
          'Coin sync: local=$localTotal, server=$serverCoins (in sync)',
        );
      } else if (serverCoins < localTotal) {
        // Local ahead — keep it; the next outbox drain will push the
        // missing delta to the server. Don't overwrite local with a
        // smaller server number.
        AppLogger.info(
          'Coin sync: local=$localTotal, server=$serverCoins '
          '(kept local; server is behind by ${localTotal - serverCoins} — '
          'next sync drain will push)',
        );
      } else {
        // Server is ahead → adopt it. Snapshot-apply skips the outbox
        // (the value came FROM the server, no need to push it back) but
        // still bumps Drift's updatedAt so subsequent local mutations
        // win on the next sync. The watchCoinBalanceRow stream picks up
        // the write and re-emits state — no manual emit here.
        final delta = serverCoins - localTotal;
        await StorageService().storeDao.applyCoinBalanceSnapshot(
              balance: serverCoins,
            );
        AppLogger.info(
          'Coin sync: local=$localTotal, server=$serverCoins (synced +$delta)',
        );
      }

      // Always force-reconcile the backend's UserCoinBalance mirror table
      // with the Drift balance we just settled on. The dashboard reads
      // UserCoinBalance (the client-mirror), but /auth/me returned
      // User.Coins (the canonical ledger) — and those two server-side
      // records can drift apart when a historical /sync push set
      // UserCoinBalance to a value the gameplay/claim handlers never
      // bumped User.Coins up to. Pushing once after every sync
      // guarantees the dashboard always reflects the value Flutter is
      // showing. The outbox is idempotent per drain cycle, so this
      // costs at most one HTTP push per auth cycle.
      await StorageService().storeDao.enqueueCoinBalanceSync();
    } catch (e) {
      AppLogger.error('Error syncing coins with backend', e);
    }
  }

  /// One-shot migration: fold any legacy SharedPreferences balance into
  /// Drift, then delete the retired keys. Safe to call on every launch
  /// — once the keys are gone the method is a no-op.
  Future<void> _migrateLegacySharedPreferencesToDrift() async {
    final prefs = _prefs;
    if (prefs == null) return;

    final legacyBalanceJson = prefs.getString(_legacyBalanceKey);
    if (legacyBalanceJson == null) {
      // Already migrated (or never had legacy data). Defensive cleanup
      // of the transactions key in case it was orphaned without the
      // balance key.
      if (prefs.containsKey(_legacyTransactionsKey)) {
        await prefs.remove(_legacyTransactionsKey);
      }
      return;
    }

    try {
      final storageService = StorageService();
      if (!storageService.isInitialized) return;

      final legacyBalance = CoinBalance.fromJson(
        json.decode(legacyBalanceJson),
      );
      final legacyTotal = legacyBalance.total;
      final driftRow = await storageService.storeDao.getCoinBalanceRow();
      final driftBalance = driftRow?.balance ?? 0;

      if (legacyTotal > driftBalance) {
        final delta = legacyTotal - driftBalance;
        AppLogger.info(
          'CoinsCubit: migrating legacy SharedPreferences balance to Drift '
          '(SP=$legacyTotal, Drift=$driftBalance, delta=+$delta). Outboxed '
          'as historical_backfill — next sync drain will reconcile backend.',
        );
        await storageService.storeDao.addCoins(
          delta,
          'historical_backfill',
          description: 'Reconcile of legacy SharedPreferences balance',
        );
      } else if (legacyTotal != driftBalance) {
        AppLogger.info(
          'CoinsCubit: legacy SharedPreferences balance ($legacyTotal) is '
          'behind Drift ($driftBalance) — no migration needed. Drift wins.',
        );
      }

      // Drop the retired keys regardless of delta direction — the
      // migration is complete and we don't want to read them again.
      await prefs.remove(_legacyBalanceKey);
      await prefs.remove(_legacyTransactionsKey);
    } catch (e) {
      AppLogger.warning(
        'CoinsCubit: legacy SharedPreferences migration failed (will retry '
        'on next launch since keys are still present): $e',
      );
    }
  }

  /// Credit the +50 welcome bonus through the canonical addCoins path
  /// so the gain rides the outbox and the backend's UserCoinBalance +
  /// users.Coins both reflect the seed via the next drain.
  ///
  /// Called from [SyncEngine.maybeRunFirstSignInPull]'s brandNew branch
  /// — only for users the backend just minted (isNewUser == true).
  /// Idempotent: skipped if Drift already shows any prior activity, so
  /// double-invocation can't double-credit.
  Future<void> seedStartingBonus() async {
    final storageService = StorageService();
    if (!storageService.isInitialized) return;
    final row = await storageService.storeDao.getCoinBalanceRow();
    if (row == null) return;
    if (row.balance > 0 || row.totalEarned > 0) {
      AppLogger.info(
        'CoinsCubit.seedStartingBonus skipped — Drift not virgin '
        '(balance=${row.balance}, totalEarned=${row.totalEarned})',
      );
      return;
    }

    AppLogger.info('CoinsCubit: seeding +50 starting bonus for brand-new user');
    await storageService.storeDao.addCoins(
      50,
      'starting_bonus',
      description: 'Welcome bonus for new players',
    );
  }

  /// Hydrate state.balance + state.transactions from Drift.
  Future<void> _loadFromDrift() async {
    final storageService = StorageService();
    if (!storageService.isInitialized) return;

    final row = await storageService.storeDao.getCoinBalanceRow();
    final txns = await storageService.storeDao.getCoinTransactions(limit: 200);
    // Seed daily-bonus state synchronously so the home-screen gate is
    // correct on the very first frame. The watch stream wired in
    // [_wireDriftWatches] will emit the same value moments later (and
    // every subsequent change), but blocking here avoids a window
    // where state.dailyBonusLastClaimUtcMs is null even though Drift
    // already holds a row.
    final bonusRow = await storageService.storeDao.getDailyBonusRow();

    final balance = _balanceFromRow(row);
    final transactions = txns.map(_modelFromDriftTxn).toList();

    emit(state.copyWith(
      balance: balance,
      transactions: transactions,
      dailyBonuses: _dailyBonusesFromRow(bonusRow),
      dailyBonusLastClaimUtcMs: bonusRow?.lastClaimUtcMs,
      dailyBonusLastClaimTzOffsetMinutes: bonusRow?.lastClaimTzOffsetMinutes,
      dailyBonusCurrentStreak: bonusRow?.currentStreak ?? 0,
    ));
  }

  /// Subscribe to Drift watches so any later write (snapshot apply,
  /// spend, debug reset, sync-engine restore) propagates into state
  /// without a manual refresh.
  void _wireDriftWatches() {
    final storageService = StorageService();
    if (!storageService.isInitialized) return;

    _coinsRowWatch?.cancel();
    _transactionsWatch?.cancel();
    _dailyBonusWatch?.cancel();

    _coinsRowWatch = storageService.storeDao.watchCoinBalanceRow().listen(
      (row) {
        final newBalance = _balanceFromRow(row);
        if (newBalance == state.balance) return;
        emit(state.copyWith(balance: newBalance));
      },
    );

    _transactionsWatch =
        storageService.storeDao.watchCoinTransactions(limit: 200).listen(
      (rows) {
        final modelTxns = rows.map(_modelFromDriftTxn).toList();
        emit(state.copyWith(transactions: modelTxns));
      },
    );

    _dailyBonusWatch =
        storageService.storeDao.watchDailyBonusRow().listen(
      (row) {
        emit(state.copyWith(
          dailyBonuses: _dailyBonusesFromRow(row),
          dailyBonusLastClaimUtcMs: row?.lastClaimUtcMs,
          dailyBonusLastClaimTzOffsetMinutes: row?.lastClaimTzOffsetMinutes,
          dailyBonusCurrentStreak: row?.currentStreak ?? 0,
        ));
      },
    );
  }

  /// Project the Drift singleton into the 7-day cycle list used by the
  /// popup grid. Each day picks up `isCollected` + `collectedAt` from
  /// `weeklyClaimsJson` (a `{ "1": "<utcIso>", ... }` map written by
  /// the DAO). The 7-day reward template (coins + bonusItem) is the
  /// authoritative client-side economy table — backend rewards mirror
  /// it via `EconomyConstants.WeeklyLoginRewards`.
  List<DailyLoginBonus> _dailyBonusesFromRow(db.DailyBonusStateData? row) {
    final template = DailyLoginBonus.getWeeklyBonuses();
    if (row == null) return template;
    Map<String, dynamic> claimedMap;
    try {
      claimedMap = json.decode(row.weeklyClaimsJson) as Map<String, dynamic>;
    } catch (_) {
      claimedMap = const <String, dynamic>{};
    }
    return template.map((bonus) {
      final raw = claimedMap[bonus.day.toString()];
      if (raw is! String) return bonus;
      DateTime? collectedAt;
      try {
        collectedAt = DateTime.parse(raw);
      } catch (_) {
        collectedAt = null;
      }
      return bonus.copyWith(
        isCollected: true,
        collectedAt: collectedAt,
      );
    }).toList();
  }

  /// Build a [CoinBalance] from a Drift `Coins` row. Drift's `totalEarned`
  /// accumulates all credits (gameplay + purchases) so the model's
  /// separate `purchased` field is dropped to 0 — `earned` already
  /// represents lifetime gain. The `lifetime` derived getter and
  /// `spendingRatio` stay correct under this mapping.
  CoinBalance _balanceFromRow(db.Coin? row) {
    if (row == null) {
      return CoinBalance(
        total: 0,
        earned: 0,
        spent: 0,
        purchased: 0,
        lastUpdated: DateTime.now(),
      );
    }
    return CoinBalance(
      total: row.balance,
      earned: row.totalEarned,
      spent: row.totalSpent,
      purchased: 0,
      lastUpdated: row.lastUpdated,
    );
  }

  /// Convert a Drift `CoinTransactions` row into the in-memory display
  /// model. Sign convention: Drift stores spends as negative amounts
  /// (see [StoreDao.spendCoins]). The model's `isEarned` flag captures
  /// the direction explicitly, and `amount` is normalized to positive.
  CoinTransaction _modelFromDriftTxn(db.CoinTransaction txn) {
    final isEarned = txn.type == 'earned' || txn.amount > 0;
    final source = txn.source;

    CoinEarningSource? earningSource;
    CoinSpendingCategory? spendingCategory;
    if (isEarned) {
      earningSource = CoinEarningSource.values.firstWhere(
        (s) => s.name == source,
        orElse: () => CoinEarningSource.gameCompleted,
      );
    } else {
      spendingCategory = CoinSpendingCategory.values.firstWhere(
        (c) => c.name == source,
        orElse: () => CoinSpendingCategory.powerUps,
      );
    }

    return CoinTransaction(
      id: 'drift_${txn.id}',
      amount: txn.amount.abs(),
      isEarned: isEarned,
      earningSource: earningSource,
      spendingCategory: spendingCategory,
      itemName: txn.description,
      timestamp: txn.createdAt,
      metadata: const {},
    );
  }

  /// Load the device-only anti-grind daily cap from prefs and reset it
  /// if the UTC date has rolled. Daily-bonus state is no longer loaded
  /// here — that's Drift-backed and lands via [_wireDriftWatches].
  Future<void> _loadDailyEarningsCap() async {
    final prefs = _prefs;
    if (prefs == null) return;

    try {
      final dailyEarnings = prefs.getInt(_dailyEarningsKey) ?? 0;
      final lastResetStr = prefs.getString(_lastEarningResetKey);
      DateTime lastEarningReset = DateTime.now().toUtc();
      if (lastResetStr != null) {
        lastEarningReset = DateTime.parse(lastResetStr);
      }

      // Check if we need to reset daily earnings (new UTC day)
      final now = DateTime.now().toUtc();
      final resetDate = DateTime.utc(
        lastEarningReset.year,
        lastEarningReset.month,
        lastEarningReset.day,
      );
      final today = DateTime.utc(now.year, now.month, now.day);
      final shouldReset = today.isAfter(resetDate);

      emit(
        state.copyWith(
          dailyEarnings: shouldReset ? 0 : dailyEarnings,
          lastEarningReset: shouldReset ? now : lastEarningReset,
        ),
      );

      if (shouldReset) {
        await _saveDailyCapData();
      }
    } catch (e) {
      AppLogger.error('Error loading device-only coin state', e);
    }
  }

  /// One-shot migration: if the legacy daily-bonus prefs keys exist and
  /// the new Drift `daily_bonus_state` row is empty, seed Drift from
  /// the prefs values so a user mid-week doesn't get re-prompted on
  /// the day they upgrade. Then delete the legacy keys.
  ///
  /// Seeding heuristics:
  ///   * `last_daily_bonus_claim_date` (YYYY-MM-DD local) becomes
  ///     `lastClaimUtcMs` at noon-UTC of that day (no streak math —
  ///     we don't know the actual instant). The current device tz is
  ///     used as `lastClaimTzOffsetMinutes`.
  ///   * `daily_bonuses` (JSON list with `is_collected` / `collected_at`
  ///     per day) is folded into `weeklyClaimsJson` and the count of
  ///     collected entries becomes the seed for `currentStreak`. Best
  ///     effort — the next online sync will reconcile with the server's
  ///     authoritative `DailyLoginBonus` record.
  Future<void> _migrateLegacyDailyBonusToDrift() async {
    final prefs = _prefs;
    if (prefs == null) return;

    final hasLegacyClaimDate =
        prefs.containsKey(_legacyLastBonusClaimDateKey);
    final hasLegacyBonuses = prefs.containsKey(_legacyDailyBonusesKey);
    if (!hasLegacyClaimDate && !hasLegacyBonuses) return;

    try {
      final storageService = StorageService();
      if (!storageService.isInitialized) return;

      final existing = await storageService.storeDao.getDailyBonusRow();
      if (existing == null) {
        int? lastClaimUtcMs;
        int? lastClaimTzOffsetMinutes;
        final lastClaimDate = prefs.getString(_legacyLastBonusClaimDateKey);
        if (lastClaimDate != null && lastClaimDate.length == 10) {
          try {
            // Treat the legacy date as user-local; pin to noon-UTC so
            // the day stays stable across reasonable tz offsets.
            final parsedDate = DateTime.parse('${lastClaimDate}T12:00:00Z');
            lastClaimUtcMs = parsedDate.millisecondsSinceEpoch;
            lastClaimTzOffsetMinutes =
                DateTime.now().timeZoneOffset.inMinutes;
          } catch (_) {
            // Malformed legacy value — ignore.
          }
        }

        int currentStreak = 0;
        final weeklyClaimsJson = <String, dynamic>{};
        final bonusesJson = prefs.getStringList(_legacyDailyBonusesKey) ?? [];
        if (bonusesJson.isNotEmpty) {
          for (final entry in bonusesJson) {
            try {
              final map = json.decode(entry) as Map<String, dynamic>;
              final day = map['day'];
              final isCollected = map['is_collected'] == true;
              final collectedAt = map['collected_at'];
              if (isCollected && day is int) {
                currentStreak++;
                weeklyClaimsJson[day.toString()] =
                    collectedAt ?? DateTime.now().toUtc().toIso8601String();
              }
            } catch (_) {
              // Skip malformed entries.
            }
          }
        }

        if (lastClaimUtcMs != null || weeklyClaimsJson.isNotEmpty) {
          await storageService.storeDao.applyDailyBonusSnapshot(
            lastClaimUtcMs: lastClaimUtcMs,
            lastClaimTzOffsetMinutes: lastClaimTzOffsetMinutes,
            currentStreak: currentStreak,
            totalClaims: currentStreak,
            weeklyClaimsJson: json.encode(weeklyClaimsJson),
          );
          AppLogger.info(
            'Migrated legacy daily-bonus prefs into Drift '
            '(streak=$currentStreak, lastClaimUtcMs=$lastClaimUtcMs)',
          );
        }
      }

      // Always clear the legacy keys after the migration attempt so the
      // next launch doesn't try to migrate again (idempotent + small).
      await prefs.remove(_legacyDailyBonusesKey);
      await prefs.remove(_legacyLastBonusClaimDateKey);
    } catch (e) {
      AppLogger.error('Daily-bonus legacy prefs migration failed', e);
    }
  }

  Future<void> _saveDailyCapData() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setInt(_dailyEarningsKey, state.dailyEarnings);
    await prefs.setString(
      _lastEarningResetKey,
      state.lastEarningReset.toIso8601String(),
    );
  }

  /// Check if earning would exceed daily cap
  bool _wouldExceedDailyCap(int amount) {
    return state.dailyEarnings + amount > state.dailyEarningCap;
  }

  /// Reset daily earnings if needed (called at midnight UTC)
  void _checkAndResetDailyEarnings() {
    final now = DateTime.now().toUtc();
    final lastReset = state.lastEarningReset;
    final resetDate =
        DateTime.utc(lastReset.year, lastReset.month, lastReset.day);
    final today = DateTime.utc(now.year, now.month, now.day);

    if (today.isAfter(resetDate)) {
      emit(state.copyWith(
        dailyEarnings: 0,
        lastEarningReset: now,
      ));
      AppLogger.info('Daily earnings reset at midnight UTC');
    }
  }

  /// Update premium multiplier based on subscription status
  void updatePremiumMultiplier(bool hasPremium, bool hasBattlePass) {
    double multiplier;
    bool premiumBonus = hasPremium || hasBattlePass;

    if (hasPremium && hasBattlePass) {
      multiplier = 1.75; // Pro + Battle Pass
    } else if (hasPremium) {
      multiplier = 1.5; // Pro only
    } else if (hasBattlePass) {
      multiplier = 1.25; // Battle Pass only
    } else {
      multiplier = 1.0; // Free tier
    }

    emit(
      state.copyWith(
        earningMultiplier: multiplier,
        hasPremiumBonus: premiumBonus,
      ),
    );

    AppLogger.info('Updated coin earning multiplier to ${multiplier}x');
  }

  /// Earn coins from a specific source
  Future<bool> earnCoins(
    CoinEarningSource source, {
    int? customAmount,
    String? itemName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      _checkAndResetDailyEarnings();

      final baseAmount = customAmount ?? source.getBaseAmount();
      if (baseAmount <= 0) return true;

      final multipliedAmount = (baseAmount * state.earningMultiplier).round();

      // Cap-exempt sources: purchases (paid IAP, never grindable) and the
      // daily login bonus (a once-per-day engagement claim, not a grind
      // vector). If gameplay maxed out the cap earlier in the day, the
      // user should still get their daily bonus on first launch.
      final bypassesCap = source == CoinEarningSource.purchase ||
          source == CoinEarningSource.dailyLogin;
      if (!bypassesCap && _wouldExceedDailyCap(multipliedAmount)) {
        final cappedAmount = state.remainingDailyEarnings;
        if (cappedAmount <= 0) {
          AppLogger.info('Daily earning cap reached, no coins awarded');
          return false;
        }
        return _processEarning(source, cappedAmount, itemName, metadata,
            wasCapped: true);
      }

      return _processEarning(source, multipliedAmount, itemName, metadata);
    } catch (e) {
      AppLogger.error('Error earning coins', e);
      return false;
    }
  }

  Future<bool> _processEarning(
    CoinEarningSource source,
    int amount,
    String? itemName,
    Map<String, dynamic>? metadata, {
    bool wasCapped = false,
  }) async {
    // Drift is the source of truth — writing here updates the balance
    // row + appends a CoinTransactions row + enqueues both for sync,
    // all inside a single transaction. The watch streams will re-emit
    // the new balance and the appended transaction, but we also pull a
    // fresh row synchronously below so any caller that snapshots
    // state.balance.earned before/after this call (see
    // GameCubit._earnAndTrack) observes the delta without waiting on
    // the async stream emission.
    try {
      await StorageService().storeDao.addCoins(
            amount,
            source.name,
            description: itemName,
          );
    } catch (e) {
      AppLogger.error(
        'CoinsCubit: addCoins failed for +$amount from ${source.name}',
        e,
      );
      return false;
    }

    // Synchronous state refresh from Drift — keeps the
    // "earnedBefore / earnedAfter" pattern in GameCubit working
    // regardless of when the watch stream fires.
    await _refreshBalanceFromDrift();

    // Daily cap counter is device-only. Cap-bypassing sources also don't
    // count toward the cap (consistent with the bypass check above).
    final countsTowardCap = source != CoinEarningSource.purchase &&
        source != CoinEarningSource.dailyLogin;
    if (countsTowardCap) {
      emit(state.copyWith(dailyEarnings: state.dailyEarnings + amount));
      await _saveDailyCapData();
    }

    AppLogger.info(
      'Earned $amount coins from ${source.displayName}'
      '${wasCapped ? ' (capped)' : ''}'
      '${metadata == null || metadata.isEmpty ? '' : ' meta=${metadata.keys.join(",")}'}',
    );
    return true;
  }

  /// Set the coin balance to a server-authoritative value. Used after a
  /// backend mutation (e.g. coin-purchased power-up) returns the new
  /// total. The snapshot-apply path skips the outbox because the value
  /// came from the server.
  Future<void> setServerBalance(int serverTotal) async {
    if (state.balance.total == serverTotal) return;
    await StorageService().storeDao.applyCoinBalanceSnapshot(
          balance: serverTotal,
        );
    // watchCoinBalanceRow fires and triggers the state refresh.
  }

  /// Spend coins on an item
  Future<bool> spendCoins(
    int amount,
    CoinSpendingCategory category, {
    String? itemName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      if (state.balance.total < amount) {
        AppLogger.warning(
          'Insufficient coins: need $amount, have ${state.balance.total}',
        );
        return false;
      }

      final ok = await StorageService().storeDao.spendCoins(
            amount,
            category.name,
            description: itemName,
          );
      if (!ok) {
        AppLogger.warning('StoreDao.spendCoins refused — balance race');
        return false;
      }

      await _refreshBalanceFromDrift();

      AppLogger.info(
        'Spent $amount coins on ${category.displayName}'
        '${itemName != null ? ': $itemName' : ''}'
        '${metadata == null || metadata.isEmpty ? '' : ' meta=${metadata.keys.join(",")}'}',
      );
      return true;
    } catch (e) {
      AppLogger.error('Error spending coins', e);
      return false;
    }
  }

  /// Purchase coins with real money. Routes through the same Drift +
  /// outbox path as gameplay earnings, tagged with source='purchase'
  /// so the backend's coin ledger reflects the IAP credit.
  Future<bool> purchaseCoins(
    CoinPurchaseOption option,
    String transactionId,
  ) async {
    try {
      final totalCoins = option.totalCoins;
      final description =
          '${option.name} (txn: $transactionId, base: ${option.coins}, '
          'bonus: ${option.bonusCoins}, price: \$${option.price})';

      await StorageService().storeDao.addCoins(
            totalCoins,
            'purchase',
            description: description,
          );

      await _refreshBalanceFromDrift();

      AppLogger.info('Purchased $totalCoins coins via ${option.name}');
      return true;
    } catch (e) {
      AppLogger.error('Error purchasing coins', e);
      return false;
    }
  }

  Future<void> _refreshBalanceFromDrift() async {
    final storageService = StorageService();
    if (!storageService.isInitialized) return;
    final row = await storageService.storeDao.getCoinBalanceRow();
    final newBalance = _balanceFromRow(row);
    if (newBalance == state.balance) return;
    emit(state.copyWith(balance: newBalance));
  }

  /// Collect today's daily login bonus.
  ///
  /// Flow:
  ///   1. Call [StoreDao.claimDailyBonusToday] — the gate + atomic
  ///      Drift write + outbox enqueue, all in one transaction. This
  ///      is the only place the daily-bonus row is mutated.
  ///   2. If already claimed today, return false. The watch stream
  ///      doesn't emit (no row change) so the UI doesn't churn.
  ///   3. Otherwise, look up the reward for the new currentDay from
  ///      the local economy table and grant it via [earnCoins] — which
  ///      itself writes Drift + enqueues the coin_balance sync outbox.
  Future<bool> collectDailyBonus() async {
    try {
      final storageService = StorageService();
      if (!storageService.isInitialized) {
        AppLogger.warning(
          'Storage not initialized; cannot claim daily bonus yet',
        );
        return false;
      }

      final outcome = await storageService.storeDao.claimDailyBonusToday();

      switch (outcome) {
        case DailyBonusAlreadyClaimedToday _:
          AppLogger.info('Daily bonus already claimed today (Drift gate)');
          return false;
        case DailyBonusClaimed claimed:
          final templates = DailyLoginBonus.getWeeklyBonuses();
          final idx = claimed.currentDay - 1;
          if (idx < 0 || idx >= templates.length) {
            AppLogger.warning(
              'Daily bonus claim landed on out-of-range day '
              '${claimed.currentDay}; skipping coin grant',
            );
            return true;
          }
          final reward = templates[idx];
          final granted = await earnCoins(
            CoinEarningSource.dailyLogin,
            customAmount: reward.coins,
            itemName: 'Day ${reward.day} Bonus',
            metadata: {
              'day': reward.day,
              'bonus_item': reward.bonusItem,
              'streak': claimed.newStreak,
            },
          );
          if (!granted) {
            AppLogger.warning(
              'Daily bonus row updated but coin grant failed for day '
              '${reward.day}',
            );
          }
          AppLogger.info(
            'Collected daily bonus: day=${reward.day} '
            '(streak=${claimed.newStreak}) → ${reward.coins} coins',
          );
          return true;
      }
    } catch (e) {
      AppLogger.error('Error collecting daily bonus', e);
      return false;
    }
  }

  /// Get coins earned from a specific source today
  int getCoinsEarnedToday(CoinEarningSource source) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    return state.transactions
        .where(
          (t) =>
              t.isEarned &&
              t.earningSource == source &&
              t.timestamp.isAfter(startOfDay),
        )
        .fold(0, (sum, t) => sum + t.amount);
  }

  /// Get spending by category this week
  Map<CoinSpendingCategory, int> getWeeklySpending() {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));

    final weeklyTransactions = state.transactions.where(
      (t) => !t.isEarned && t.timestamp.isAfter(weekAgo),
    );

    final spending = <CoinSpendingCategory, int>{};

    for (final transaction in weeklyTransactions) {
      if (transaction.spendingCategory != null) {
        spending[transaction.spendingCategory!] =
            (spending[transaction.spendingCategory!] ?? 0) + transaction.amount;
      }
    }

    return spending;
  }

  /// Reset daily bonuses for a new week. Now a Drift-side operation —
  /// clears the singleton row so the next claim seeds a fresh cycle.
  Future<void> resetDailyBonuses() async {
    try {
      final storageService = StorageService();
      if (!storageService.isInitialized) return;
      await storageService.storeDao.applyDailyBonusSnapshot(
        lastClaimUtcMs: null,
        lastClaimTzOffsetMinutes: null,
        currentStreak: 0,
        totalClaims: 0,
        weeklyClaimsJson: '{}',
      );
      AppLogger.info('Daily bonuses reset for new week');
    } catch (e) {
      AppLogger.error('Error resetting daily bonuses', e);
    }
  }

  /// Debug: Add coins (for testing)
  Future<void> debugAddCoins(int amount) async {
    if (amount <= 0) return;
    await earnCoins(
      CoinEarningSource.gameCompleted,
      customAmount: amount,
      itemName: 'Debug Addition',
      metadata: {'debug': true},
    );
  }

  /// Debug: Reset balance (for testing). Wipes Drift balance + the
  /// device-only daily cap counter. Transactions are not retroactively
  /// erased because the backend still has them on the ledger.
  Future<void> debugResetBalance() async {
    try {
      await StorageService().storeDao.applyCoinBalanceSnapshot(balance: 0);
      await _refreshBalanceFromDrift();
      emit(state.copyWith(dailyEarnings: 0));
      await _saveDailyCapData();
      AppLogger.info('Coin balance reset to 0 (debug)');
    } catch (e) {
      AppLogger.error('Error resetting coin balance', e);
    }
  }

  /// Whether the daily bonus was already claimed today, in the user's
  /// local-tz day. Delegates to [CoinsState.wasDailyBonusClaimedToday]
  /// which reads the Drift-backed `lastClaimUtcMs` / `tzOffsetMinutes`
  /// fields. Pure read — no prefs, no side effects.
  bool get wasDailyBonusClaimedToday => state.wasDailyBonusClaimedToday;

  /// Check if user can afford a purchase
  bool canAfford(int amount) => state.balance.total >= amount;

  /// Get current balance
  int get balance => state.balance.total;

  /// Clear error message
  void clearError() {
    emit(state.copyWith(clearError: true));
  }

  @override
  Future<void> close() async {
    await _coinsRowWatch?.cancel();
    await _transactionsWatch?.cancel();
    await _dailyBonusWatch?.cancel();
    return super.close();
  }
}
