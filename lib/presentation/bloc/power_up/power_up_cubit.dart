import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cosmo_strike_flutter_app/models/power_up.dart';
import 'package:cosmo_strike_flutter_app/models/premium_power_up.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// Pre-game power-up inventory state. Keys are snake_case identifiers
/// matching the legacy backend wire format (kept stable so existing
/// arm/consume logic in GameCubit continues to work). The `armed`
/// field holds the inventory key the user has chosen to pre-load
/// for their next game — consumed automatically when
/// GameCubit.startGame fires.
class PowerUpState extends Equatable {
  final Map<String, int> inventory;
  final String? armed;
  final bool loading;

  const PowerUpState({
    this.inventory = const {},
    this.armed,
    this.loading = false,
  });

  PowerUpState copyWith({
    Map<String, int>? inventory,
    String? armed,
    bool clearArmed = false,
    bool? loading,
  }) {
    return PowerUpState(
      inventory: inventory ?? this.inventory,
      armed: clearArmed ? null : (armed ?? this.armed),
      loading: loading ?? this.loading,
    );
  }

  int countFor(String type) => inventory[type] ?? 0;
  int get totalOwned =>
      inventory.values.fold(0, (sum, count) => sum + count);

  @override
  List<Object?> get props => [inventory, armed, loading];
}

/// Offline-first power-up inventory cubit. Persists inventory as a
/// JSON map in SharedPreferences; coin purchases go through
/// [CoinsCubit.spendCoins] so the existing coin-economy plumbing
/// (balance, transactions, animations) keeps working unchanged.
///
/// Bundle composition is hardcoded in [PowerUpBundle.availableBundles]
/// — the catalog lives in the app, not on a backend.
class PowerUpCubit extends Cubit<PowerUpState> {
  static const String _inventoryPrefsKey = 'power_up_inventory_v1';

  PowerUpCubit() : super(const PowerUpState());

  Future<void> loadInventory() async {
    emit(state.copyWith(loading: true));
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_inventoryPrefsKey);
      if (raw == null || raw.isEmpty) {
        emit(state.copyWith(inventory: const {}, loading: false));
        return;
      }
      final decoded = jsonDecode(raw);
      var inventory = _parseInventory(decoded);
      // One-shot legacy migration: fold snake-classic keys (camelCase /
      // mega variants / dead types) into the 8 working keys. Idempotent,
      // so no version bump is needed; persists only when something folded.
      final migrated = _migrateLegacyKeys(inventory);
      if (migrated != null) {
        inventory = migrated;
        await _persistInventory(inventory);
        AppLogger.info('Power-up inventory migrated to working keys');
      }
      emit(PowerUpState(
        inventory: inventory,
        loading: false,
      ));
    } catch (e) {
      AppLogger.error('Failed to load power-up inventory', e);
      emit(state.copyWith(loading: false));
    }
  }

  /// Legacy → working key fold. MUST stay in lockstep with the backend's
  /// PowerUpCatalog.LegacyKeyMap (ProductCatalog.cs). The six keys with
  /// no gameplay at all convert 1:1 into score_multiplier as goodwill.
  /// Returns null when nothing needed folding.
  static const Map<String, String> _legacyKeyMap = {
    'megaSpeedBoost': 'speed_boost',
    'megaInvincibility': 'invincibility',
    'mega_invincibility': 'invincibility',
    'megaScoreMultiplier': 'score_multiplier',
    'megaSlowMotion': 'slow_motion',
    'ghostMode': 'ghost_mode',
    'scoreShield': 'score_shield',
    'magneticFood': 'magnetic_pickup',
    'sizeReducer': 'score_multiplier',
    'comboMultiplier': 'score_multiplier',
    'timeWarp': 'score_multiplier',
    'doubleTrouble': 'score_multiplier',
    'luckyCharm': 'score_multiplier',
    'powerSurge': 'score_multiplier',
  };

  static Map<String, int>? _migrateLegacyKeys(Map<String, int> inventory) {
    var changed = false;
    final result = <String, int>{};
    inventory.forEach((key, count) {
      final target = _legacyKeyMap[key] ?? key;
      if (target != key) changed = true;
      result[target] = (result[target] ?? 0) + count;
    });
    return changed ? result : null;
  }

  /// Buy one use of a basic power-up. Local-only: spends coins via
  /// [CoinsCubit] and bumps the inventory map by 1. Returns the new
  /// coin balance on success or null if the user couldn't afford it.
  Future<int?> purchaseWithCoins(String powerUpType, int coinCost) async {
    final coins = GetIt.I<CoinsCubit>();
    final ok = await coins.spendCoins(
      coinCost,
      CoinSpendingCategory.powerUps,
      itemName: powerUpType,
    );
    if (!ok) return null;
    await _grantToInventory({powerUpType: 1});
    return coins.state.balance.total;
  }

  /// Spend coins on a power-up bundle. Bundle contents are looked up
  /// from [PowerUpBundle.availableBundles] — no network. Returns the
  /// new coin balance, or null if the bundle was unknown or the user
  /// couldn't afford it.
  Future<int?> purchaseBundleWithCoins(String bundleId) async {
    final bundle = PowerUpBundle.availableBundles
        .where((b) => b.id == bundleId)
        .cast<PowerUpBundle?>()
        .firstWhere((_) => true, orElse: () => null);
    if (bundle == null) {
      AppLogger.warning('Unknown power-up bundle: $bundleId');
      return null;
    }

    final coins = GetIt.I<CoinsCubit>();
    final ok = await coins.spendCoins(
      bundle.bundlePrice.toInt(),
      CoinSpendingCategory.powerUps,
      itemName: bundle.name,
      metadata: {'bundleId': bundleId},
    );
    if (!ok) return null;

    final grants = <String, int>{};
    bundle.powerUps.forEach((type, count) {
      grants[type.inventoryKey] = (grants[type.inventoryKey] ?? 0) + count;
    });
    await _grantToInventory(grants);
    return coins.state.balance.total;
  }

  /// Grant one free basic power-up (a Speed Boost) — used by the rewarded-ad
  /// "watch for a free power-up" placement. Inventory is device-only
  /// (SharedPreferences), so there's no sync row to enqueue.
  Future<void> grantFreePowerUp() => _grantToInventory(const {'speed_boost': 1});

  /// Decrement one use of a power-up. Called by the pre-game
  /// activation flow at the moment the power-up activates in-game.
  /// Also clears the armed slot — once a power-up is used the user
  /// must re-arm if they want another one on their next game.
  Future<bool> consume(String powerUpType) async {
    if (state.countFor(powerUpType) <= 0) return false;
    final next = Map<String, int>.from(state.inventory);
    final remaining = (next[powerUpType] ?? 0) - 1;
    if (remaining <= 0) {
      next.remove(powerUpType);
    } else {
      next[powerUpType] = remaining;
    }
    emit(state.copyWith(inventory: next, clearArmed: true));
    await _persistInventory(next);
    return true;
  }

  void arm(String powerUpType) {
    if (state.countFor(powerUpType) <= 0) {
      AppLogger.warning('Attempted to arm power-up not in inventory: $powerUpType');
      return;
    }
    if (state.armed == powerUpType) return;
    emit(state.copyWith(armed: powerUpType));
  }

  void unarm() {
    if (state.armed == null) return;
    emit(state.copyWith(clearArmed: true));
  }

  /// Map the snake_case inventory key to the legacy gameplay PowerUpType
  /// enum (the 4 basics). The other 4 working keys (teleport, ghost_mode,
  /// magnetic_pickup, score_shield) are applied by ArmedLoadout.apply in
  /// the Flame game directly; callers should treat null as "not a basic".
  static PowerUpType? typeFromInventoryKey(String key) {
    switch (key) {
      case 'speed_boost':
        return PowerUpType.speedBoost;
      case 'invincibility':
        return PowerUpType.invincibility;
      case 'score_multiplier':
        return PowerUpType.scoreMultiplier;
      case 'slow_motion':
        return PowerUpType.slowMotion;
      default:
        return null;
    }
  }

  /// Public single-key grant — battle-pass rewards and other earn paths.
  Future<void> grant(String powerUpKey, int count) =>
      _grantToInventory({powerUpKey: count});

  /// SP key: ids of server power-up grants already applied on this device.
  static const String _appliedGrantsPrefsKey = 'applied_power_up_grant_ids_v1';

  /// Apply a server-delivered power-up grant (the Pro subscription's
  /// per-period bundle) exactly once per [grantId]. Inventory persists
  /// BEFORE the id is recorded — a crash between the two risks one
  /// duplicate grant, which beats silently losing one. Returns true when
  /// the grant was applied (false = already applied earlier).
  Future<bool> applyServerGrant(String grantId, Map<String, int> grant) async {
    if (grantId.isEmpty || grant.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final applied = prefs.getStringList(_appliedGrantsPrefsKey) ?? <String>[];
      if (applied.contains(grantId)) return false;
      await _grantToInventory(grant);
      applied.add(grantId);
      // Cap the ledger — one entry per subscription period, two dozen
      // covers two years of monthly renewals.
      while (applied.length > 24) {
        applied.removeAt(0);
      }
      await prefs.setStringList(_appliedGrantsPrefsKey, applied);
      return true;
    } catch (e) {
      AppLogger.error('Failed to apply server power-up grant $grantId', e);
      return false;
    }
  }

  Future<void> _grantToInventory(Map<String, int> grants) async {
    if (grants.isEmpty) return;
    final next = Map<String, int>.from(state.inventory);
    grants.forEach((key, delta) {
      next[key] = (next[key] ?? 0) + delta;
    });
    emit(state.copyWith(inventory: next));
    await _persistInventory(next);
  }

  Future<void> _persistInventory(Map<String, int> inventory) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_inventoryPrefsKey, jsonEncode(inventory));
    } catch (e) {
      AppLogger.error('Failed to persist power-up inventory', e);
    }
  }

  Map<String, int> _parseInventory(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((key, value) {
      if (key is String && value is int && value > 0) {
        out[key] = value;
      }
    });
    return out;
  }
}
