import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';

part 'store_dao.g.dart';

const _uuid = Uuid();

@DriftAccessor(
    tables: [Coins, CoinTransactions, PremiumStatus, UnlockedItems, BattlePasses, PurchaseHistory, DailyBonusState])
class StoreDao extends DatabaseAccessor<AppDatabase> with _$StoreDaoMixin {
  StoreDao(super.db);

  // ==================== Coins ====================

  /// Watch coin balance for reactive UI
  Stream<int> watchCoinBalance() =>
      (select(coins)..where((t) => t.id.equals(1)))
          .watchSingleOrNull()
          .map((c) => c?.balance ?? 0);

  /// Watch the full singleton coins row — used by CoinsCubit so the
  /// breakdown (balance + totalEarned + totalSpent + lastUpdated) stays
  /// in lock-step with Drift writes. Snapshot-apply, addCoins, and
  /// spendCoins all flow through here, which keeps the cubit's emitted
  /// state synchronous with Drift even when the mutation didn't come
  /// from the cubit itself.
  Stream<Coin?> watchCoinBalanceRow() =>
      (select(coins)..where((t) => t.id.equals(1))).watchSingleOrNull();

  /// Watch the most-recent N coin transactions. CoinsCubit consumes
  /// this stream so the transactions list re-renders whenever a new
  /// row lands (regardless of which DAO method inserted it).
  Stream<List<CoinTransaction>> watchCoinTransactions({int limit = 200}) =>
      (select(coinTransactions)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(limit))
          .watch();

  /// Get current coin balance
  Future<int> getCoinBalance() async {
    final coin = await (select(coins)..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    return coin?.balance ?? 0;
  }

  /// Get the full singleton coins row. Used by SyncEngine to read the
  /// authentic `updatedAt` (rather than stamping `now` at dispatch
  /// time, which would break server-side last-write-wins).
  Future<Coin?> getCoinBalanceRow() =>
      (select(coins)..where((t) => t.id.equals(1))).getSingleOrNull();

  /// Force-enqueue a coin_balance sync outbox row so the next drain
  /// pushes the current Drift balance up to the backend's
  /// UserCoinBalance mirror table (which is what the admin dashboard
  /// reads).
  ///
  /// Why this exists: the backend has TWO coin records per user — the
  /// canonical `users.Coins` ledger (mutated by gameplay/claim handlers
  /// via raw SQL UPDATEs) and the `UserCoinBalance` client-mirror table
  /// (mutated by /sync/coin-balance pushes). When a client push has
  /// historically set UserCoinBalance to a value that users.Coins never
  /// caught up to (because the corresponding gain never landed in a
  /// server-side ledger transaction), the two diverge. /auth/me returns
  /// users.Coins, the dashboard shows UserCoinBalance. Calling this
  /// after CoinsCubit.syncWithBackend reconciles its in-memory state
  /// with /auth/me ensures the next drain re-pushes the new
  /// authoritative value to UserCoinBalance, eliminating the
  /// "Flutter says 13856 / Dashboard says 14656" class of bugs.
  Future<void> enqueueCoinBalanceSync() async {
    await attachedDatabase.enqueueSyncOutbox(
      dataType: SyncDataType.coinBalance,
      entityKey: 'coin_balance:1',
    );
  }

  /// Sum of coins earned since [since], excluding [excludeSources].
  /// Drives the anti-grind daily cap from the synced transaction ledger
  /// (instead of a device-only prefs counter), so clearing app data or
  /// winding the clock back doesn't reset it — a cloud restore brings
  /// the day's ledger rows back with it.
  Future<int> earnedCoinsSince(
    DateTime since, {
    List<String> excludeSources = const [],
  }) async {
    final sum = coinTransactions.amount.sum();
    Expression<bool> where = coinTransactions.type.equals('earned') &
        coinTransactions.createdAt.isBiggerOrEqualValue(since);
    if (excludeSources.isNotEmpty) {
      where = where & coinTransactions.source.isNotIn(excludeSources);
    }
    final query = selectOnly(coinTransactions)
      ..addColumns([sum])
      ..where(where);
    final row = await query.getSingle();
    return row.read(sum) ?? 0;
  }

  /// Sum of coins earned from one [source] since [since] — drives the
  /// per-source daily ceilings.
  Future<int> earnedCoinsFromSourceSince(String source, DateTime since) async {
    final sum = coinTransactions.amount.sum();
    final query = selectOnly(coinTransactions)
      ..addColumns([sum])
      ..where(coinTransactions.type.equals('earned') &
          coinTransactions.source.equals(source) &
          coinTransactions.createdAt.isBiggerOrEqualValue(since));
    final row = await query.getSingle();
    return row.read(sum) ?? 0;
  }

  /// Add coins (from game, achievement, etc.). Bumps balance, appends
  /// a transaction record, and enqueues both rows for sync inside a
  /// single Drift transaction.
  Future<void> addCoins(int amount, String source, {String? description}) async {
    final current = await (select(coins)..where((t) => t.id.equals(1)))
        .getSingleOrNull();

    if (current == null) return;

    final newBalance = current.balance + amount;
    final newTotalEarned = current.totalEarned + amount;
    final now = DateTime.now();

    await transaction(() async {
      await (update(coins)..where((t) => t.id.equals(1))).write(CoinsCompanion(
        balance: Value(newBalance),
        totalEarned: Value(newTotalEarned),
        lastUpdated: Value(now),
        updatedAt: Value(now),
      ));

      await into(coinTransactions).insert(CoinTransactionsCompanion.insert(
        amount: amount,
        type: 'earned',
        source: source,
        description: Value(description),
        updatedAt: Value(now),
      ));

      // Mint a stable, clock-skew-safe idempotency key client-side.
      // Stored in the outbox payload so retries keep the same key.
      final idempotencyKey = _uuid.v4();
      final txnKey = 'coin_transaction:$idempotencyKey';
      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.coinBalance,
        entityKey: 'coin_balance:1',
      );
      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.coinTransaction,
        entityKey: txnKey,
        payload: {
          'amount': amount,
          'type': 'earned',
          'source': source,
          'description': description,
          'created_at': now.toUtc().toIso8601String(),
          'idempotency_key': idempotencyKey,
        },
      );
    });
  }

  /// Spend coins. Mirrors [addCoins] but with the opposite sign.
  Future<bool> spendCoins(int amount, String source, {String? description}) async {
    final current = await (select(coins)..where((t) => t.id.equals(1)))
        .getSingleOrNull();

    if (current == null || current.balance < amount) return false;

    final newBalance = current.balance - amount;
    final newTotalSpent = current.totalSpent + amount;
    final now = DateTime.now();

    await transaction(() async {
      await (update(coins)..where((t) => t.id.equals(1))).write(CoinsCompanion(
        balance: Value(newBalance),
        totalSpent: Value(newTotalSpent),
        lastUpdated: Value(now),
        updatedAt: Value(now),
      ));

      await into(coinTransactions).insert(CoinTransactionsCompanion.insert(
        amount: -amount,
        type: 'spent',
        source: source,
        description: Value(description),
        updatedAt: Value(now),
      ));

      final idempotencyKey = _uuid.v4();
      final txnKey = 'coin_transaction:$idempotencyKey';
      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.coinBalance,
        entityKey: 'coin_balance:1',
      );
      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.coinTransaction,
        entityKey: txnKey,
        payload: {
          'amount': -amount,
          'type': 'spent',
          'source': source,
          'description': description,
          // Snake-case + UTC to match the backend's SnakeCaseLower
          // JSON policy. The previous camelCase / local-time payload
          // bound to DateTime.MinValue server-side, which made every
          // spend share idempotency_key="0" so the server silently
          // dropped every spend after the first.
          'created_at': now.toUtc().toIso8601String(),
          'idempotency_key': idempotencyKey,
        },
      );
    });

    return true;
  }

  /// Set coin balance directly. Used by the first-sign-in pull when
  /// the cloud's authoritative balance comes down. [enqueueSync]
  /// defaults true; set false when hydrating from server data.
  Future<void> setCoinBalance(int balance, {bool enqueueSync = true}) async {
    final now = DateTime.now();
    await transaction(() async {
      await (update(coins)..where((t) => t.id.equals(1))).write(CoinsCompanion(
        balance: Value(balance),
        lastUpdated: Value(now),
        updatedAt: Value(now),
      ));
      if (enqueueSync) {
        await attachedDatabase.enqueueSyncOutbox(
          dataType: SyncDataType.coinBalance,
          entityKey: 'coin_balance:1',
        );
      }
    });
  }

  /// Get coin transaction history
  Future<List<CoinTransaction>> getCoinTransactions({int limit = 50}) async {
    return (select(coinTransactions)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  // ==================== Premium Status ====================

  /// Watch premium status
  Stream<PremiumStatusData?> watchPremiumStatus() =>
      (select(premiumStatus)..where((t) => t.id.equals(1))).watchSingleOrNull();

  /// Get premium status
  Future<PremiumStatusData?> getPremiumStatus() =>
      (select(premiumStatus)..where((t) => t.id.equals(1))).getSingleOrNull();

  /// Check if premium is active
  Future<bool> isPremiumActive() async {
    final status = await getPremiumStatus();
    if (status == null) return false;

    if (!status.isPremiumActive) return false;

    if (status.premiumExpirationDate != null &&
        DateTime.now().isAfter(status.premiumExpirationDate!)) {
      // Premium expired — flip the flag through the canonical setter
      // so the outbox row gets queued.
      await setPremiumActive(false);
      return false;
    }

    return true;
  }

  /// Apply a partial update to the singleton premium-status row + bump
  /// timestamps + enqueue an outbox row.
  Future<void> _writePremiumStatus(
    PremiumStatusCompanion patch, {
    bool enqueueSync = true,
  }) async {
    final now = DateTime.now();
    await transaction(() async {
      await (update(premiumStatus)..where((t) => t.id.equals(1))).write(
        patch.copyWith(
          lastUpdated: Value(now),
          updatedAt: Value(now),
        ),
      );
      if (enqueueSync) {
        await attachedDatabase.enqueueSyncOutbox(
          dataType: SyncDataType.premiumStatus,
          entityKey: 'premium_status:1',
        );
      }
    });
  }

  /// Set premium active
  Future<void> setPremiumActive(bool active, {DateTime? expirationDate}) =>
      _writePremiumStatus(PremiumStatusCompanion(
        isPremiumActive: Value(active),
        premiumExpirationDate: Value(expirationDate),
      ));

  /// Cloud-snapshot apply path for premium status. Robust against the
  /// singleton row not yet existing — uses insertOnConflictUpdate so
  /// init-order regressions can't silently swallow the snapshot
  /// section.
  Future<void> applyPremiumStatusSnapshot(PremiumStatusCompanion patch) async {
    final now = DateTime.now();
    await into(premiumStatus).insertOnConflictUpdate(
      patch.copyWith(
        id: const Value(1),
        lastUpdated: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Cloud-snapshot apply path for coin balance. Same insert-or-update
  /// robustness as [applyPremiumStatusSnapshot].
  Future<void> applyCoinBalanceSnapshot({
    required int balance,
    int? totalEarned,
    int? totalSpent,
    DateTime? updatedAt,
  }) async {
    final ts = updatedAt ?? DateTime.now();
    await into(coins).insertOnConflictUpdate(
      CoinsCompanion(
        id: const Value(1),
        balance: Value(balance),
        totalEarned:
            totalEarned == null ? const Value.absent() : Value(totalEarned),
        totalSpent:
            totalSpent == null ? const Value.absent() : Value(totalSpent),
        lastUpdated: Value(ts),
        updatedAt: Value(ts),
      ),
    );
  }

  /// Get premium expiration date as string
  Future<String?> getPremiumExpirationDate() async {
    final status = await getPremiumStatus();
    return status?.premiumExpirationDate?.toIso8601String();
  }

  /// Set trial data
  Future<void> setTrialData({
    required bool isOnTrial,
    DateTime? trialStartDate,
    DateTime? trialEndDate,
  }) =>
      _writePremiumStatus(PremiumStatusCompanion(
        isOnTrial: Value(isOnTrial),
        trialStartDate: Value(trialStartDate),
        trialEndDate: Value(trialEndDate),
      ));

  /// Get trial data
  Future<Map<String, dynamic>> getTrialData() async {
    final status = await getPremiumStatus();
    return {
      'isOnTrial': status?.isOnTrial ?? false,
      'trialStartDate': status?.trialStartDate?.toIso8601String(),
      'trialEndDate': status?.trialEndDate?.toIso8601String(),
    };
  }

  /// Set tournament entries
  Future<void> setTournamentEntries({
    required int bronze,
    required int silver,
    required int gold,
  }) =>
      _writePremiumStatus(PremiumStatusCompanion(
        bronzeTournamentEntries: Value(bronze),
        silverTournamentEntries: Value(silver),
        goldTournamentEntries: Value(gold),
      ));

  /// Get tournament entries
  Future<Map<String, int>> getTournamentEntries() async {
    final status = await getPremiumStatus();
    return {
      'bronze': status?.bronzeTournamentEntries ?? 0,
      'silver': status?.silverTournamentEntries ?? 0,
      'gold': status?.goldTournamentEntries ?? 0,
    };
  }

  // ==================== Unlocked Items ====================

  /// Get unlocked items by type
  Future<List<String>> getUnlockedItemsByType(String itemType) async {
    final items = await (select(unlockedItems)
          ..where((t) => t.itemType.equals(itemType)))
        .get();
    return items.map((i) => i.itemId).toList();
  }

  /// Check if item is unlocked
  Future<bool> isItemUnlocked(String itemId, String itemType) async {
    final item = await (select(unlockedItems)
          ..where(
              (t) => t.itemId.equals(itemId) & t.itemType.equals(itemType)))
        .getSingleOrNull();
    return item != null;
  }

  /// Unlock an item. Idempotent — insertOrIgnore avoids creating
  /// duplicate rows for the same (itemId, itemType) pair. The outbox
  /// row is enqueued unconditionally; the sync engine handles
  /// dedup at the backend.
  Future<void> unlockItem(String itemId, String itemType,
      {String? unlockedBy, bool enqueueSync = true}) async {
    final now = DateTime.now();
    await transaction(() async {
      await into(unlockedItems).insert(
        UnlockedItemsCompanion.insert(
          itemId: itemId,
          itemType: itemType,
          unlockedBy: Value(unlockedBy ?? 'purchase'),
          updatedAt: Value(now),
        ),
        mode: InsertMode.insertOrIgnore,
      );
      if (enqueueSync) {
        await attachedDatabase.enqueueSyncOutbox(
          dataType: SyncDataType.unlockedItem,
          entityKey: 'unlocked_item:$itemType:$itemId',
          payload: {
            'item_id': itemId,
            'item_type': itemType,
            'unlocked_by': unlockedBy ?? 'purchase',
            'unlocked_at': now.toUtc().toIso8601String(),
          },
        );
      }
    });
  }

  /// Replace all items for a given type — wipes the local set then
  /// re-inserts. Use ONLY for cases that need replace semantics like a
  /// one-shot id migration. For the "mirror what the server says I
  /// own" case, prefer [applyUnlockedItemsFromServer] instead: it
  /// merges without deleting and skips the outbox enqueue so the
  /// server's data doesn't bounce straight back as a push.
  Future<void> setUnlockedItems(
    String itemType,
    List<String> itemIds, {
    bool enqueueSync = true,
  }) async {
    await transaction(() async {
      await (delete(unlockedItems)..where((t) => t.itemType.equals(itemType)))
          .go();
      for (final itemId in itemIds) {
        await unlockItem(itemId, itemType, enqueueSync: enqueueSync);
      }
    });
  }

  /// Server-entitlement apply path. Adds any items the server says we
  /// own that we don't already have locally, without deleting anything
  /// (UnlockedItems is append-only on the wire — the server has no
  /// "revoke" semantic, so divergence between server views and local
  /// state should be resolved by union, not subtraction). Skips the
  /// outbox enqueue: the data came from the server, so echoing it back
  /// is pure bandwidth waste.
  Future<void> applyUnlockedItemsFromServer(
    String itemType,
    List<String> itemIds,
  ) async {
    if (itemIds.isEmpty) return;
    await transaction(() async {
      for (final itemId in itemIds) {
        await unlockItem(itemId, itemType, enqueueSync: false);
      }
    });
  }

  // Convenience methods for specific item types
  Future<List<String>> getUnlockedThemes() => getUnlockedItemsByType('theme');
  Future<List<String>> getUnlockedSkins() => getUnlockedItemsByType('skin');
  Future<List<String>> getUnlockedTrails() => getUnlockedItemsByType('trail');
  Future<List<String>> getUnlockedPowerUps() => getUnlockedItemsByType('powerup');
  Future<List<String>> getUnlockedBoardSizes() => getUnlockedItemsByType('board_size');
  Future<List<String>> getUnlockedGameModes() => getUnlockedItemsByType('game_mode');
  Future<List<String>> getUnlockedBundles() => getUnlockedItemsByType('bundle');

  Future<void> setUnlockedThemes(List<String> ids) => setUnlockedItems('theme', ids);
  Future<void> setUnlockedSkins(List<String> ids) => setUnlockedItems('skin', ids);
  Future<void> setUnlockedTrails(List<String> ids) => setUnlockedItems('trail', ids);
  Future<void> setUnlockedPowerUps(List<String> ids) => setUnlockedItems('powerup', ids);
  Future<void> setUnlockedBoardSizes(List<String> ids) => setUnlockedItems('board_size', ids);
  Future<void> setUnlockedGameModes(List<String> ids) => setUnlockedItems('game_mode', ids);
  Future<void> setUnlockedBundles(List<String> ids) => setUnlockedItems('bundle', ids);

  // Server-apply variants — use these in the `_applyBackendEntitlements`
  // path so server data doesn't echo back as a push and local items
  // unknown to the server (e.g., achievement-rewarded) survive the
  // refresh.
  Future<void> applyUnlockedThemesFromServer(List<String> ids) =>
      applyUnlockedItemsFromServer('theme', ids);
  Future<void> applyUnlockedSkinsFromServer(List<String> ids) =>
      applyUnlockedItemsFromServer('skin', ids);
  Future<void> applyUnlockedTrailsFromServer(List<String> ids) =>
      applyUnlockedItemsFromServer('trail', ids);
  Future<void> applyUnlockedBundlesFromServer(List<String> ids) =>
      applyUnlockedItemsFromServer('bundle', ids);

  // ==================== Battle Pass ====================

  /// Watch battle pass
  Stream<BattlePassesData?> watchBattlePass(String seasonId) =>
      (select(battlePasses)..where((t) => t.seasonId.equals(seasonId)))
          .watchSingleOrNull();

  /// Get battle pass
  Future<BattlePassesData?> getBattlePass(String seasonId) =>
      (select(battlePasses)..where((t) => t.seasonId.equals(seasonId)))
          .getSingleOrNull();

  /// Batch fetch — used by SyncEngine drain so multiple season ids
  /// resolve in one query instead of N round-trips.
  Future<List<BattlePassesData>> getBattlePassesBySeasonIds(
    Set<String> seasonIds,
  ) {
    if (seasonIds.isEmpty) return Future.value(<BattlePassesData>[]);
    return (select(battlePasses)..where((t) => t.seasonId.isIn(seasonIds)))
        .get();
  }

  /// Get current battle pass (any season). Returns the NEWEST row — the table's
  /// PK is an autoincrement id, so the most-recently-written row carries the
  /// latest state. (Historically the table accumulated duplicate rows; ordering
  /// by id desc guarantees reads reflect the latest save even if strays exist.)
  Future<BattlePassesData?> getCurrentBattlePass() =>
      (select(battlePasses)
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(1))
          .getSingleOrNull();

  /// Watch the current battle pass row regardless of seasonId. Used by
  /// BattlePassCubit to react to writes (snapshot apply, sync restore)
  /// without knowing the active season id up front. When the table is
  /// empty (fresh install pre-restore) emits null. Mirrors
  /// [getCurrentBattlePass] — newest row wins.
  Stream<BattlePassesData?> watchCurrentBattlePass() =>
      (select(battlePasses)
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(1))
          .watchSingleOrNull();

  /// Save battle pass data. [enqueueSync] defaults true.
  Future<void> saveBattlePass(
    BattlePassesCompanion pass, {
    bool enqueueSync = true,
  }) async {
    final now = DateTime.now();
    final stamped = pass.copyWith(
      lastUpdated: Value(now),
      updatedAt: Value(now),
    );
    final seasonId = stamped.seasonId.present ? stamped.seasonId.value : null;
    await transaction(() async {
      // The BattlePasses PK is an autoincrement `id` and `seasonId` has NO
      // unique constraint, so insertOnConflictUpdate never finds a conflict —
      // it INSERTS A NEW ROW on every save. Duplicate rows then pile up and a
      // stale one gets read back, so claims (and XP) appear to revert a second
      // after they're made. Upsert by seasonId manually instead: update the
      // existing row in place, prune any leftover duplicates from the old
      // insert-happy behaviour, and only insert when no row exists yet.
      if (seasonId != null) {
        final rows = await (select(battlePasses)
              ..where((t) => t.seasonId.equals(seasonId)))
            .get();
        if (rows.isEmpty) {
          await into(battlePasses).insert(stamped);
        } else {
          await (update(battlePasses)
                ..where((t) => t.id.equals(rows.first.id)))
              .write(stamped);
          if (rows.length > 1) {
            final dupeIds = rows.skip(1).map((r) => r.id).toList();
            await (delete(battlePasses)..where((t) => t.id.isIn(dupeIds))).go();
          }
        }
        if (enqueueSync) {
          await attachedDatabase.enqueueSyncOutbox(
            dataType: SyncDataType.battlePass,
            entityKey: 'battle_pass:$seasonId',
          );
        }
      } else {
        await into(battlePasses).insertOnConflictUpdate(stamped);
      }
    });
  }

  /// Decode the [claimedRewards] text column into the
  /// `{"free": [...], "premium": [...]}` split that BattlePassCubit
  /// expects. Tolerates legacy rows where the column holds a flat
  /// JSON array (everything is treated as a free-tier claim in that
  /// case — the cubit re-saves with the structured shape on the next
  /// claim).
  static Map<String, List<int>> decodeClaimedRewards(String raw) {
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) {
        return {
          'free': (decoded['free'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toList() ??
              <int>[],
          'premium': (decoded['premium'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toList() ??
              <int>[],
        };
      }
      if (decoded is List) {
        return {
          'free': decoded.map((e) => (e as num).toInt()).toList(),
          'premium': <int>[],
        };
      }
    } catch (_) {
      // Malformed payload — fall through to empty defaults.
    }
    return {'free': <int>[], 'premium': <int>[]};
  }

  /// Read battle pass as a snake_case JSON blob matching the keys
  /// BattlePassCubit writes/reads. Returns null when no row exists.
  Future<String?> getBattlePassData() async {
    final pass = await getCurrentBattlePass();
    if (pass == null) return null;

    final split = decodeClaimedRewards(pass.claimedRewards);

    return json.encode({
      'season_id': pass.seasonId,
      'current_tier': pass.currentTier,
      'current_xp': pass.currentXp,
      'xp_for_next_tier': pass.xpForNextTier,
      'is_active': pass.isPremiumPass,
      'expiry_date': pass.seasonEndDate?.toIso8601String(),
      'claimed_free_tiers': split['free'],
      'claimed_premium_tiers': split['premium'],
      // Preserved for the cubit's display layer; the Drift schema
      // doesn't have a column for it so the cubit's own copy on
      // disk (via setBattlePassData below) is the source of truth.
      'season_name': null,
      'season_start_date': pass.seasonStartDate?.toIso8601String(),
      'season_end_date': pass.seasonEndDate?.toIso8601String(),
    });
  }

  /// Persist battle pass state from the cubit's snake_case JSON blob.
  /// [enqueueSync] defaults to true so local saves ride the SyncEngine
  /// drain; the first-sign-in restore caller passes false.
  Future<void> setBattlePassData(
    String? jsonData, {
    bool enqueueSync = true,
  }) async {
    if (jsonData == null) {
      await delete(battlePasses).go();
      return;
    }

    final data = json.decode(jsonData) as Map<String, dynamic>;

    // Encode free/premium split into the single claimedRewards text
    // column. SyncEngine's wire mapping unions these into List<int>
    // when sending to the backend (the wire schema is flat).
    final claimedFree = (data['claimed_free_tiers'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        <int>[];
    final claimedPremium = (data['claimed_premium_tiers'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        <int>[];
    final claimedJson = json.encode({
      'free': claimedFree,
      'premium': claimedPremium,
    });

    final expiry = data['expiry_date'] as String?;
    final seasonStart = data['season_start_date'] as String?;
    final seasonEnd = data['season_end_date'] as String? ?? expiry;

    // Pin to the EXISTING row's seasonId when one is present. BattlePassCubit
    // doesn't carry a stable seasonId, so deriving it from its display label
    // (season_name) can disagree with the seasonId the cloud snapshot wrote —
    // producing a SECOND row. getCurrentBattlePass() (limit 1) then reads the
    // other row, so a just-saved claim looks like it reverted (the claimed
    // reward chip vanishes then reappears). Reusing the current row's id keeps
    // every read and write on the same single row.
    final existing = await getCurrentBattlePass();
    final resolvedSeasonId = existing?.seasonId ??
        (data['season_id'] as String?) ??
        (data['season_name'] as String?) ??
        'default';

    await saveBattlePass(
      BattlePassesCompanion(
        seasonId: Value(resolvedSeasonId),
        currentTier: Value((data['current_tier'] as int?) ?? 0),
        currentXp: Value((data['current_xp'] as int?) ?? 0),
        xpForNextTier: Value((data['xp_for_next_tier'] as int?) ?? 100),
        isPremiumPass: Value((data['is_active'] as bool?) ?? false),
        claimedRewards: Value(claimedJson),
        seasonStartDate: seasonStart != null
            ? Value(DateTime.tryParse(seasonStart))
            : const Value.absent(),
        seasonEndDate: seasonEnd != null
            ? Value(DateTime.tryParse(seasonEnd))
            : const Value.absent(),
      ),
      enqueueSync: enqueueSync,
    );
  }

  // ==================== Purchase History ====================
  // PurchaseHistory is not synced — the server is already the source
  // of truth via the IAP receipt-verification path.

  /// Add purchase to history
  Future<void> addPurchase(PurchaseHistoryCompanion purchase) async {
    await into(purchaseHistory).insert(purchase);
  }

  /// Get purchase history
  Future<List<PurchaseHistoryData>> getPurchaseHistory() =>
      (select(purchaseHistory)
            ..orderBy([(t) => OrderingTerm.desc(t.purchasedAt)]))
          .get();

  /// Get purchase history as JSON list
  Future<List<String>> getPurchaseHistoryJson() async {
    final purchases = await getPurchaseHistory();
    return purchases
        .map((p) => json.encode({
              'purchaseId': p.purchaseId,
              'productId': p.productId,
              'transactionId': p.transactionId,
              'amount': p.amount,
              'currency': p.currency,
              'status': p.status,
              'purchasedAt': p.purchasedAt.toIso8601String(),
            }))
        .toList();
  }

  /// Add purchase from JSON
  Future<void> addPurchaseFromJson(String purchaseJson) async {
    final data = json.decode(purchaseJson) as Map<String, dynamic>;
    await addPurchase(PurchaseHistoryCompanion.insert(
      purchaseId: data['purchaseId'] ?? '',
      productId: data['productId'] ?? '',
      transactionId: Value(data['transactionId']),
      amount: data['amount'] ?? 0,
      currency: Value(data['currency'] ?? 'USD'),
      status: data['status'] ?? 'completed',
      receiptData: Value(data['receiptData']),
    ));
  }

  // ==================== Daily Login Bonus ====================

  /// Watch the singleton daily_bonus_state row. CoinsCubit subscribes to
  /// this stream so the popup gate stays in lock-step with Drift writes
  /// (claim-today on this device, or a cold-start sync pull from
  /// another device).
  Stream<DailyBonusStateData?> watchDailyBonusRow() =>
      (select(dailyBonusState)..where((t) => t.id.equals(1)))
          .watchSingleOrNull();

  /// Read the daily_bonus_state row. Used by the SyncEngine to read
  /// the latest snapshot at drain time and by CoinsCubit's seed path.
  Future<DailyBonusStateData?> getDailyBonusRow() =>
      (select(dailyBonusState)..where((t) => t.id.equals(1)))
          .getSingleOrNull();

  /// Apply a server snapshot to the local daily_bonus_state row. Used
  /// by SyncEngine on cold-start pull so a multi-device user's other
  /// devices see the canonical claim state before the home screen
  /// renders. Skips the outbox enqueue — the value came FROM the
  /// server, no need to push it back.
  Future<void> applyDailyBonusSnapshot({
    required int? lastClaimUtcMs,
    required int? lastClaimTzOffsetMinutes,
    required int currentStreak,
    required int totalClaims,
    required String weeklyClaimsJson,
  }) async {
    final now = DateTime.now();
    final existing = await getDailyBonusRow();
    if (existing == null) {
      await into(dailyBonusState).insert(DailyBonusStateCompanion.insert(
        lastClaimUtcMs: Value(lastClaimUtcMs),
        lastClaimTzOffsetMinutes: Value(lastClaimTzOffsetMinutes),
        currentStreak: Value(currentStreak),
        totalClaims: Value(totalClaims),
        weeklyClaimsJson: Value(weeklyClaimsJson),
        updatedAt: Value(now),
      ));
    } else {
      await (update(dailyBonusState)..where((t) => t.id.equals(1)))
          .write(DailyBonusStateCompanion(
        lastClaimUtcMs: Value(lastClaimUtcMs),
        lastClaimTzOffsetMinutes: Value(lastClaimTzOffsetMinutes),
        currentStreak: Value(currentStreak),
        totalClaims: Value(totalClaims),
        weeklyClaimsJson: Value(weeklyClaimsJson),
        updatedAt: Value(now),
      ));
    }
  }

  /// Attempt to claim today's daily login bonus. Returns a result that
  /// the caller (CoinsCubit) maps to the reward grant + UI dismissal.
  ///
  /// All math is in the user's local-tz day:
  ///   userLocalDay(utc, tzMin) = (utc + tzMin minutes).date
  ///
  /// The tz offset at claim time is snapshotted into the row so a
  /// future cold-start can replay the same boundary even if the
  /// device's tz has changed since.
  Future<DailyBonusClaimOutcome> claimDailyBonusToday() async {
    final nowUtc = DateTime.now().toUtc();
    final tzOffsetMin = DateTime.now().timeZoneOffset.inMinutes;

    DailyBonusClaimOutcome? outcome;
    await transaction(() async {
      final row = await (select(dailyBonusState)..where((t) => t.id.equals(1)))
          .getSingleOrNull();

      final todayLocal = _userLocalDay(nowUtc, tzOffsetMin);

      String? lastLocal;
      if (row?.lastClaimUtcMs != null) {
        final lastUtc = DateTime.fromMillisecondsSinceEpoch(
          row!.lastClaimUtcMs!,
          isUtc: true,
        );
        lastLocal = _userLocalDay(lastUtc, row.lastClaimTzOffsetMinutes ?? 0);
      }

      if (lastLocal == todayLocal) {
        outcome = const DailyBonusClaimOutcome.alreadyClaimedToday();
        return;
      }

      final yesterdayLocal = _addDaysToIsoDate(todayLocal, -1);
      final isStreakContinuation = lastLocal == yesterdayLocal;
      final newStreak = isStreakContinuation ? (row?.currentStreak ?? 0) + 1 : 1;
      final currentDay = ((newStreak - 1) % 7) + 1;

      // Update the weekly-claims map. If the new streak landed on day 1
      // (start of a fresh cycle — either a streak reset OR a cycle wrap),
      // start over with a clean map. Otherwise carry forward the existing
      // entries and add today's.
      final priorMap = row?.weeklyClaimsJson == null
          ? <String, dynamic>{}
          : (json.decode(row!.weeklyClaimsJson) as Map<String, dynamic>);
      final Map<String, dynamic> newMap =
          currentDay == 1 ? <String, dynamic>{} : Map.of(priorMap);
      newMap[currentDay.toString()] = nowUtc.toIso8601String();
      final newMapJson = json.encode(newMap);

      final nowEpochMs = nowUtc.millisecondsSinceEpoch;
      final newTotalClaims = (row?.totalClaims ?? 0) + 1;
      final now = DateTime.now();

      if (row == null) {
        await into(dailyBonusState).insert(DailyBonusStateCompanion.insert(
          lastClaimUtcMs: Value(nowEpochMs),
          lastClaimTzOffsetMinutes: Value(tzOffsetMin),
          currentStreak: Value(newStreak),
          totalClaims: Value(newTotalClaims),
          weeklyClaimsJson: Value(newMapJson),
          updatedAt: Value(now),
        ));
      } else {
        await (update(dailyBonusState)..where((t) => t.id.equals(1)))
            .write(DailyBonusStateCompanion(
          lastClaimUtcMs: Value(nowEpochMs),
          lastClaimTzOffsetMinutes: Value(tzOffsetMin),
          currentStreak: Value(newStreak),
          totalClaims: Value(newTotalClaims),
          weeklyClaimsJson: Value(newMapJson),
          updatedAt: Value(now),
        ));
      }

      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.dailyBonusClaim,
        entityKey: 'daily_bonus_claim:1',
      );

      outcome = DailyBonusClaimOutcome.claimed(
        currentDay: currentDay,
        newStreak: newStreak,
        claimedAtUtc: nowUtc,
      );
    });

    return outcome ?? const DailyBonusClaimOutcome.alreadyClaimedToday();
  }

  /// Shared math contract — kept identical to the server's
  /// SyncDailyBonusCommandHandler.UserLocalDay().
  static String _userLocalDay(DateTime utc, int tzOffsetMinutes) {
    final local = utc.add(Duration(minutes: tzOffsetMinutes));
    return local.toIso8601String().substring(0, 10);
  }

  /// Add/subtract a calendar day from a YYYY-MM-DD string. Used to
  /// derive yesterday's local date without round-tripping through a
  /// DateTime — keeps the math purely string-anchored to the same day
  /// the gate compares.
  static String _addDaysToIsoDate(String isoDate, int days) {
    final dt = DateTime.parse(isoDate);
    return dt.add(Duration(days: days)).toIso8601String().substring(0, 10);
  }
}

/// Result of [StoreDao.claimDailyBonusToday]. Either the row was bumped
/// and an outbox entry was enqueued, or today's claim was already in
/// the row and we no-op'd.
sealed class DailyBonusClaimOutcome {
  const DailyBonusClaimOutcome();

  const factory DailyBonusClaimOutcome.alreadyClaimedToday() =
      DailyBonusAlreadyClaimedToday;
  const factory DailyBonusClaimOutcome.claimed({
    required int currentDay,
    required int newStreak,
    required DateTime claimedAtUtc,
  }) = DailyBonusClaimed;
}

class DailyBonusAlreadyClaimedToday extends DailyBonusClaimOutcome {
  const DailyBonusAlreadyClaimedToday();
}

class DailyBonusClaimed extends DailyBonusClaimOutcome {
  final int currentDay;
  final int newStreak;
  final DateTime claimedAtUtc;
  const DailyBonusClaimed({
    required this.currentDay,
    required this.newStreak,
    required this.claimedAtUtc,
  });
}
