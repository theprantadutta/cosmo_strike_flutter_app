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
      emit(PowerUpState(
        inventory: _parseInventory(decoded),
        loading: false,
      ));
    } catch (e) {
      AppLogger.error('Failed to load power-up inventory', e);
      emit(state.copyWith(loading: false));
    }
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
    for (final premium in bundle.powerUps) {
      final key = _inventoryKeyForPremium(premium);
      grants[key] = (grants[key] ?? 0) + 1;
    }
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

  /// Map the snake_case inventory key to the gameplay PowerUpType enum.
  /// Returns null for keys that aren't part of the basic-power-up set
  /// (e.g. premium-bundle items live in inventory but have no in-game
  /// trigger yet); callers should treat null as "ignore this key".
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

  /// Translate a premium power-up enum value to the inventory key the
  /// rest of the app uses. Mega-variants fold back into their basic
  /// counterparts so existing in-game activation handles them; the
  /// truly exclusive types use their enum name verbatim and are
  /// inert until gameplay logic is wired up.
  static String _inventoryKeyForPremium(PremiumPowerUpType type) {
    switch (type) {
      case PremiumPowerUpType.megaSpeedBoost:
        return 'speed_boost';
      case PremiumPowerUpType.megaInvincibility:
        return 'invincibility';
      case PremiumPowerUpType.megaScoreMultiplier:
        return 'score_multiplier';
      case PremiumPowerUpType.megaSlowMotion:
        return 'slow_motion';
      default:
        return type.name;
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
