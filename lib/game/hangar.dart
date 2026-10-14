import 'dart:math' as math;

import 'run_upgrades.dart';

/// Permanent progression: Hangar upgrades bought with coins (they persist
/// across runs) and ship frames unlocked by campaign milestones. Pure Dart so
/// the rules are unit-tested; persistence lives in HangarService.

enum HangarStat { hull, cannons, capacitor, arsenal, tractor }

class HangarStatDef {
  const HangarStatDef(this.stat, this.name, this.perLevel);
  final HangarStat stat;
  final String name;

  /// Effect text for ONE level.
  final String perLevel;
}

class HangarCatalog {
  HangarCatalog._();

  static const int maxLevel = 5;

  /// Coin price of reaching level 1..5.
  static const List<int> costs = [150, 350, 700, 1200, 2000];

  static int costForNext(int currentLevel) =>
      currentLevel >= maxLevel ? 0 : costs[currentLevel];

  static const List<HangarStatDef> stats = [
    HangarStatDef(HangarStat.hull, 'Reinforced Hull', '-6% damage taken'),
    HangarStatDef(HangarStat.cannons, 'Cannon Tuning', '+4% fire rate'),
    HangarStatDef(HangarStat.capacitor, 'Overdrive Capacitor', 'Grazes charge Overdrive 8% faster'),
    HangarStatDef(HangarStat.arsenal, 'Missile Bay', '+1 missile at the start of every run'),
    HangarStatDef(HangarStat.tractor, 'Tractor Beam', '+40 range always-on power-up magnet'),
  ];

  static HangarStatDef byStat(HangarStat s) => stats.firstWhere((d) => d.stat == s);

  /// Synced unlocked-item id for owning [level] of [stat] (≤ 100 chars).
  static String itemId(HangarStat stat, int level) => 'hangar_${stat.name}_$level';

  /// Parse owned item ids back into the highest level per stat.
  static Map<HangarStat, int> levelsFrom(Iterable<String> itemIds) {
    final out = <HangarStat, int>{};
    for (final id in itemIds) {
      final parts = id.split('_');
      if (parts.length != 3 || parts[0] != 'hangar') continue;
      final stat = HangarStat.values.where((s) => s.name == parts[1]).firstOrNull;
      final lvl = int.tryParse(parts[2]);
      if (stat == null || lvl == null) continue;
      out[stat] = math.max(out[stat] ?? 0, lvl.clamp(0, maxLevel));
    }
    return out;
  }
}

/// A ship frame: a playstyle with starting upgrades + trade-offs, unlocked
/// by clearing a campaign level.
class ShipFrame {
  const ShipFrame({
    required this.id,
    required this.name,
    required this.tagline,
    required this.unlockLevel,
    this.startingUpgrades = const [],
    this.fireCooldownScale = 1,
    this.damageTakenScale = 1,
  });

  final String id;
  final String name;
  final String tagline;

  /// Clear this campaign level to unlock (0 = always owned).
  final int unlockLevel;
  final List<UpgradeId> startingUpgrades;
  final double fireCooldownScale;
  final double damageTakenScale;

  static const striker = ShipFrame(
    id: 'striker',
    name: 'Striker',
    tagline: 'Balanced. No strengths, no weaknesses.',
    unlockLevel: 0,
  );

  static const all = [
    striker,
    ShipFrame(
      id: 'lancer',
      name: 'Lancer',
      tagline: 'Piercing shots, slower trigger.',
      unlockLevel: 3,
      startingUpgrades: [UpgradeId.piercingRounds],
      fireCooldownScale: 1.15,
    ),
    ShipFrame(
      id: 'tempest',
      name: 'Tempest',
      tagline: 'Wide spread from launch, thinner hull.',
      unlockLevel: 6,
      startingUpgrades: [UpgradeId.wideSpread],
      damageTakenScale: 1.1,
    ),
    ShipFrame(
      id: 'bulwark',
      name: 'Bulwark',
      tagline: 'Shield every level and plating, heavy trigger.',
      unlockLevel: 9,
      startingUpgrades: [UpgradeId.shieldRegen, UpgradeId.hullPlating],
      fireCooldownScale: 1.12,
    ),
    ShipFrame(
      id: 'phantom',
      name: 'Phantom',
      tagline: 'Born to graze: huge Overdrive gain, fragile.',
      unlockLevel: 12,
      startingUpgrades: [UpgradeId.siphon, UpgradeId.siphon, UpgradeId.grazeField],
      damageTakenScale: 1.2,
    ),
  ];

  static ShipFrame byId(String id) => all.firstWhere((f) => f.id == id, orElse: () => striker);

  bool ownedWith(int highestClearedLevel) => highestClearedLevel >= unlockLevel;
}

/// Everything permanent the game applies at run start.
class HangarLoadout {
  const HangarLoadout({this.levels = const {}, this.frame = ShipFrame.striker});

  final Map<HangarStat, int> levels;
  final ShipFrame frame;

  int level(HangarStat s) => levels[s] ?? 0;

  double get damageTakenScale =>
      math.pow(0.94, level(HangarStat.hull)).toDouble() * frame.damageTakenScale;
  double get fireCooldownScale =>
      math.pow(0.96, level(HangarStat.cannons)).toDouble() * frame.fireCooldownScale;
  double get grazeChargeScale => 1 + 0.08 * level(HangarStat.capacitor);
  int get startMissiles => level(HangarStat.arsenal);
  double get magnetRadius => level(HangarStat.tractor) == 0 ? 0 : 60.0 + 40 * level(HangarStat.tractor);
}
