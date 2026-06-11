import 'package:flutter/material.dart';

/// The premium (coin-purchased / Pro-granted) power-up catalog for Cosmo
/// Strike. Each member maps 1:1 to an inventory key the game engine
/// actually consumes (`ArmedLoadout.apply` in lib/game/run_effects.dart) —
/// the earlier catalog was inherited from a different title and sold
/// camelCase keys with no gameplay behind them.
///
/// MUST stay in lockstep with the backend's PowerUpCatalog.WorkingKeys
/// (ProductCatalog.cs): the same snake_case keys ride the coin-purchase
/// endpoints, the Pro grant (power_up_grant), and the server inventory.
enum PremiumPowerUpType {
  speedBoost('speed_boost'),
  invincibility('invincibility'),
  scoreMultiplier('score_multiplier'),
  slowMotion('slow_motion'),
  teleport('teleport'),
  ghostMode('ghost_mode'),
  magneticPickup('magnetic_pickup'),
  scoreShield('score_shield');

  const PremiumPowerUpType(this.inventoryKey);

  /// The snake_case wire/inventory key — what PowerUpCubit stores, what
  /// the backend grants, and what ArmedLoadout.apply switches on.
  final String inventoryKey;

  String get id => inventoryKey;

  String get displayName {
    switch (this) {
      case PremiumPowerUpType.speedBoost:
        return 'Speed Boost';
      case PremiumPowerUpType.invincibility:
        return 'Invincibility';
      case PremiumPowerUpType.scoreMultiplier:
        return 'Score Multiplier';
      case PremiumPowerUpType.slowMotion:
        return 'Slow Motion';
      case PremiumPowerUpType.teleport:
        return 'Warp Escape';
      case PremiumPowerUpType.ghostMode:
        return 'Ghost Mode';
      case PremiumPowerUpType.magneticPickup:
        return 'Orb Magnet';
      case PremiumPowerUpType.scoreShield:
        return 'Last Stand';
    }
  }

  /// What the power-up ACTUALLY does in a run — matches
  /// ArmedLoadout.apply exactly; don't promise what the engine doesn't do.
  String get description {
    switch (this) {
      case PremiumPowerUpType.speedBoost:
        return 'Start with overcharged engines: faster flying and firing '
            'for 15 seconds';
      case PremiumPowerUpType.invincibility:
        return 'Launch with a shield up plus 8 seconds of invulnerability';
      case PremiumPowerUpType.scoreMultiplier:
        return 'Double score for the first 30 seconds of the run';
      case PremiumPowerUpType.slowMotion:
        return 'Enemies and bullets crawl for the first 10 seconds';
      case PremiumPowerUpType.teleport:
        return 'One warp-escape charge: the first hit is negated and your '
            'ship warps back to spawn';
      case PremiumPowerUpType.ghostMode:
        return 'Phase through enemies and their bullets for 12 seconds';
      case PremiumPowerUpType.magneticPickup:
        return 'Power-up orbs home toward your ship for a full 60 seconds';
      case PremiumPowerUpType.scoreShield:
        return 'One last-stand charge: a lethal hit restores half health '
            'instead of costing a ship';
    }
  }

  String get icon {
    switch (this) {
      case PremiumPowerUpType.speedBoost:
        return '🚀';
      case PremiumPowerUpType.invincibility:
        return '🛡️';
      case PremiumPowerUpType.scoreMultiplier:
        return '💎';
      case PremiumPowerUpType.slowMotion:
        return '🕰️';
      case PremiumPowerUpType.teleport:
        return '⚡';
      case PremiumPowerUpType.ghostMode:
        return '👻';
      case PremiumPowerUpType.magneticPickup:
        return '🧲';
      case PremiumPowerUpType.scoreShield:
        return '🔰';
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

/// Coin-purchased power-up bundle. IDs, contents, counts, and prices MUST
/// match ProductCatalog.PowerUpBundles on the backend — the server
/// validates against its own catalog and rejects tampered requests.
class PowerUpBundle {
  final String id;
  final String name;
  final String description;

  /// Power-up type → number of uses granted per purchase.
  final Map<PremiumPowerUpType, int> powerUps;
  final double originalPrice;
  final double bundlePrice;
  final String icon;

  const PowerUpBundle({
    required this.id,
    required this.name,
    required this.description,
    required this.powerUps,
    required this.originalPrice,
    required this.bundlePrice,
    required this.icon,
  });

  double get savings => originalPrice - bundlePrice;
  double get savingsPercentage => (savings / originalPrice) * 100;

  static const List<PowerUpBundle> availableBundles = [
    PowerUpBundle(
      id: 'mega_pack',
      name: 'Combat Power Pack',
      description: 'Four of each core combat boost',
      powerUps: {
        PremiumPowerUpType.speedBoost: 4,
        PremiumPowerUpType.invincibility: 4,
        PremiumPowerUpType.scoreMultiplier: 4,
        PremiumPowerUpType.slowMotion: 4,
      },
      originalPrice: 11000, // singles value (4 × 2,750)
      bundlePrice: 8000,
      icon: '⚡',
    ),
    PowerUpBundle(
      id: 'tactical_pack',
      name: 'Tactical Power Pack',
      description: 'Three of each survival trick for skilled pilots',
      powerUps: {
        PremiumPowerUpType.teleport: 3,
        PremiumPowerUpType.scoreShield: 3,
        PremiumPowerUpType.ghostMode: 3,
        PremiumPowerUpType.magneticPickup: 3,
      },
      originalPrice: 16350, // singles value (3 × 5,450)
      bundlePrice: 12000,
      icon: '🎯',
    ),
    PowerUpBundle(
      id: 'ultimate_pack',
      name: 'Ultimate Power Pack',
      description: 'A deep stockpile of every power-up in the armory',
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
      icon: '👑',
    ),
  ];
}
