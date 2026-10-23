import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Tactical Gear — the store (credit-purchased / Strike Command-granted)
/// consumables armed before a run. Each member maps 1:1 to an inventory key
/// the game engine actually consumes (`ArmedLoadout.apply` in
/// lib/game/run_effects.dart).
///
/// MUST stay in lockstep with the backend's PowerUpCatalog.WorkingKeys
/// (ProductCatalog.cs): the same `gear_*` keys ride the credit-purchase
/// endpoints, the Strike Command grant (power_up_grant), and the server
/// inventory. Pre-3.2 snake_case keys (`speed_boost`, …) are still accepted
/// on read via [fromKey] / [normalizeKey].
enum PremiumPowerUpType {
  speedBoost('gear_afterburner', 'speed_boost'),
  invincibility('gear_aegis', 'invincibility'),
  scoreMultiplier('gear_bounty', 'score_multiplier'),
  slowMotion('gear_chrono', 'slow_motion'),
  teleport('gear_warp', 'teleport'),
  ghostMode('gear_cloak', 'ghost_mode'),
  magneticPickup('gear_lure', 'magnetic_pickup'),
  scoreShield('gear_laststand', 'score_shield');

  const PremiumPowerUpType(this.inventoryKey, this.legacyKey);

  /// The wire/inventory key — what PowerUpCubit stores, what the backend
  /// grants, and what ArmedLoadout.apply switches on.
  final String inventoryKey;

  /// Pre-3.2 inventory key, read-only (old Drift blobs / sync payloads).
  final String legacyKey;

  String get id => inventoryKey;

  /// Resolve a current or legacy inventory key; null when unknown.
  static PremiumPowerUpType? fromKey(String? key) {
    if (key == null) return null;
    for (final t in PremiumPowerUpType.values) {
      if (t.inventoryKey == key || t.legacyKey == key) return t;
    }
    // Defensive: old premium variants were folded into base keys upstream.
    if (key == 'mega_invincibility') return PremiumPowerUpType.invincibility;
    return null;
  }

  /// Canonical inventory key for [key] (unknown keys pass through untouched
  /// so a future item is never silently dropped).
  static String normalizeKey(String key) => fromKey(key)?.inventoryKey ?? key;

  /// Re-key an inventory / grant map onto canonical keys, summing counts
  /// when a legacy and a current key both appear.
  static Map<String, int> normalizeInventory(Map<String, int> raw) {
    final out = <String, int>{};
    raw.forEach((k, v) {
      if (v <= 0) return;
      final key = normalizeKey(k);
      out[key] = (out[key] ?? 0) + v;
    });
    return out;
  }

  String get displayName {
    switch (this) {
      case PremiumPowerUpType.speedBoost:
        return 'Afterburner';
      case PremiumPowerUpType.invincibility:
        return 'Aegis Shell';
      case PremiumPowerUpType.scoreMultiplier:
        return 'Bounty Amp';
      case PremiumPowerUpType.slowMotion:
        return 'Chrono Field';
      case PremiumPowerUpType.teleport:
        return 'Warp Escape';
      case PremiumPowerUpType.ghostMode:
        return 'Phase Cloak';
      case PremiumPowerUpType.magneticPickup:
        return 'Grav Lure';
      case PremiumPowerUpType.scoreShield:
        return 'Last Stand';
    }
  }

  /// What the gear ACTUALLY does in a run — matches ArmedLoadout.apply
  /// exactly; don't promise what the engine doesn't do.
  String get description {
    switch (this) {
      case PremiumPowerUpType.speedBoost:
        return 'Faster flying and firing for the first 15 seconds.';
      case PremiumPowerUpType.invincibility:
        return 'Launch with a shield plus 8s of invulnerability.';
      case PremiumPowerUpType.scoreMultiplier:
        return 'Double score for the first 30 seconds.';
      case PremiumPowerUpType.slowMotion:
        return 'Enemies and bullets crawl for 10 seconds.';
      case PremiumPowerUpType.teleport:
        return 'One charge: the first hit warps you home unharmed.';
      case PremiumPowerUpType.ghostMode:
        return 'Phase through enemies and bullets for 12 seconds.';
      case PremiumPowerUpType.magneticPickup:
        return 'Pickup orbs home toward you for 60 seconds.';
      case PremiumPowerUpType.scoreShield:
        return 'One charge: a lethal hit restores half hull instead.';
    }
  }

  /// Credit cost of a single unit. MUST match
  /// PurchasePowerUpWithCoinsCommandHandler.AllowedCosts on the backend.
  int get creditCost {
    switch (this) {
      case PremiumPowerUpType.speedBoost:
      case PremiumPowerUpType.slowMotion:
        return 500;
      case PremiumPowerUpType.scoreMultiplier:
        return 750;
      case PremiumPowerUpType.invincibility:
        return 1000;
      case PremiumPowerUpType.teleport:
        return 1200;
      case PremiumPowerUpType.magneticPickup:
        return 1250;
      case PremiumPowerUpType.ghostMode:
      case PremiumPowerUpType.scoreShield:
        return 1500;
    }
  }

  IconData get icon {
    switch (this) {
      case PremiumPowerUpType.speedBoost:
        return Symbols.speed_rounded;
      case PremiumPowerUpType.invincibility:
        return Symbols.shield_rounded;
      case PremiumPowerUpType.scoreMultiplier:
        return Symbols.star_rounded;
      case PremiumPowerUpType.slowMotion:
        return Symbols.slow_motion_video_rounded;
      case PremiumPowerUpType.teleport:
        return Symbols.swap_calls_rounded;
      case PremiumPowerUpType.ghostMode:
        return Symbols.blur_on_rounded;
      case PremiumPowerUpType.magneticPickup:
        return Symbols.attractions_rounded;
      case PremiumPowerUpType.scoreShield:
        return Symbols.security_rounded;
    }
  }

  Color get color {
    switch (this) {
      case PremiumPowerUpType.speedBoost:
        return Colors.orange;
      case PremiumPowerUpType.invincibility:
        return Colors.amber;
      case PremiumPowerUpType.scoreMultiplier:
        return Colors.green;
      case PremiumPowerUpType.slowMotion:
        return Colors.indigo;
      case PremiumPowerUpType.teleport:
        return Colors.cyan;
      case PremiumPowerUpType.ghostMode:
        return Colors.grey;
      case PremiumPowerUpType.magneticPickup:
        return Colors.blueGrey;
      case PremiumPowerUpType.scoreShield:
        return Colors.teal;
    }
  }
}

/// Credit-purchased gear bundle. IDs, contents, counts, and prices MUST
/// match ProductCatalog.PowerUpBundles on the backend — the server
/// validates against its own catalog and rejects tampered requests.
class PowerUpBundle {
  final String id;
  final String name;
  final String description;

  /// Gear type → number of uses granted per purchase.
  final Map<PremiumPowerUpType, int> powerUps;
  final double originalPrice;
  final double bundlePrice;

  const PowerUpBundle({
    required this.id,
    required this.name,
    required this.description,
    required this.powerUps,
    required this.originalPrice,
    required this.bundlePrice,
  });

  double get savings => originalPrice - bundlePrice;
  double get savingsPercentage => (savings / originalPrice) * 100;

  /// Pre-3.2 bundle IDs → current IDs (credit-spend metadata / analytics).
  static const Map<String, String> legacyIds = {
    'mega_pack': 'gear_supply_crate',
    'tactical_pack': 'gear_tactical_case',
    'ultimate_pack': 'gear_arsenal',
  };

  static PowerUpBundle? byId(String id) {
    final key = legacyIds[id] ?? id;
    for (final b in availableBundles) {
      if (b.id == key) return b;
    }
    return null;
  }

  static const List<PowerUpBundle> availableBundles = [
    PowerUpBundle(
      id: 'gear_supply_crate',
      name: 'Supply Crate',
      description: 'Four of each core combat system',
      powerUps: {
        PremiumPowerUpType.speedBoost: 4,
        PremiumPowerUpType.invincibility: 4,
        PremiumPowerUpType.scoreMultiplier: 4,
        PremiumPowerUpType.slowMotion: 4,
      },
      originalPrice: 11000, // singles value (4 × 2,750)
      bundlePrice: 8000,
    ),
    PowerUpBundle(
      id: 'gear_tactical_case',
      name: 'Tactical Case',
      description: 'Three of each survival system for veteran pilots',
      powerUps: {
        PremiumPowerUpType.teleport: 3,
        PremiumPowerUpType.scoreShield: 3,
        PremiumPowerUpType.ghostMode: 3,
        PremiumPowerUpType.magneticPickup: 3,
      },
      originalPrice: 16350, // singles value (3 × 5,450)
      bundlePrice: 12000,
    ),
    PowerUpBundle(
      id: 'gear_arsenal',
      name: 'Full Arsenal',
      description: 'A deep stockpile of every piece of gear in the Armory',
      powerUps: {
        PremiumPowerUpType.speedBoost: 5,
        PremiumPowerUpType.invincibility: 5,
        PremiumPowerUpType.scoreMultiplier: 5,
        PremiumPowerUpType.slowMotion: 5,
        PremiumPowerUpType.teleport: 4,
        PremiumPowerUpType.scoreShield: 4,
        PremiumPowerUpType.ghostMode: 4,
        PremiumPowerUpType.magneticPickup: 4,
      },
      originalPrice: 35550, // 5×2,750 basics + 4×5,450 premiums
      bundlePrice: 25000,
    ),
  ];
}
