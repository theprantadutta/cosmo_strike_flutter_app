import 'dart:math' as math;

/// The upgrade draft: after every level clear the player picks 1 of 3
/// upgrades that stack for the rest of the run (reset when it ends).
/// Pure Dart (no Flame/Flutter) so the rules are unit-tested.
enum UpgradeId {
  twinCannon,
  wideSpread,
  rapidServos,
  piercingRounds,
  heavyRounds,
  wingman,
  shieldRegen,
  magnetField,
  grazeField,
  overcharge,
  siphon,
  chainLink,
  missileRack,
  hullPlating,
}

enum UpgradeRarity { common, rare, epic }

class UpgradeDef {
  const UpgradeDef({
    required this.id,
    required this.name,
    required this.blurb,
    required this.maxStacks,
    this.rarity = UpgradeRarity.common,
    this.category = 'Weapon',
  });

  final UpgradeId id;
  final String name;

  /// One-line effect, written for ONE stack.
  final String blurb;
  final int maxStacks;
  final UpgradeRarity rarity;
  final String category;

  /// Draft weight: rarer picks show up less often.
  int get weight => switch (rarity) {
        UpgradeRarity.common => 10,
        UpgradeRarity.rare => 6,
        UpgradeRarity.epic => 3,
      };
}

class UpgradeCatalog {
  UpgradeCatalog._();

  static const List<UpgradeDef> all = [
    UpgradeDef(
        id: UpgradeId.twinCannon,
        name: 'Twin Cannon',
        blurb: '+1 parallel cannon shot',
        maxStacks: 2),
    UpgradeDef(
        id: UpgradeId.wideSpread,
        name: 'Wide Spread',
        blurb: 'Fire two angled side shots',
        maxStacks: 2),
    UpgradeDef(
        id: UpgradeId.rapidServos,
        name: 'Rapid Servos',
        blurb: '+15% fire rate',
        maxStacks: 3),
    UpgradeDef(
        id: UpgradeId.piercingRounds,
        name: 'Piercing Rounds',
        blurb: 'Shots pass through +1 enemy',
        maxStacks: 2,
        rarity: UpgradeRarity.rare),
    UpgradeDef(
        id: UpgradeId.heavyRounds,
        name: 'Heavy Rounds',
        blurb: '+1 damage on every shot',
        maxStacks: 2,
        rarity: UpgradeRarity.epic),
    UpgradeDef(
        id: UpgradeId.wingman,
        name: 'Wingman Drone',
        blurb: 'A drone flies with you and fires',
        maxStacks: 2,
        rarity: UpgradeRarity.rare),
    UpgradeDef(
        id: UpgradeId.shieldRegen,
        name: 'Shield Regen',
        blurb: 'Start every level with a shield',
        maxStacks: 1,
        category: 'Defense'),
    UpgradeDef(
        id: UpgradeId.hullPlating,
        name: 'Hull Plating',
        blurb: 'Take 20% less damage',
        maxStacks: 2,
        category: 'Defense'),
    UpgradeDef(
        id: UpgradeId.magnetField,
        name: 'Magnet Field',
        blurb: 'Pull in power-ups from range',
        maxStacks: 2,
        category: 'Utility'),
    UpgradeDef(
        id: UpgradeId.missileRack,
        name: 'Missile Rack',
        blurb: '+2 missiles at the start of every level',
        maxStacks: 3,
        category: 'Utility'),
    UpgradeDef(
        id: UpgradeId.grazeField,
        name: 'Graze Field',
        blurb: '+30% graze range',
        maxStacks: 2,
        category: 'Overdrive'),
    UpgradeDef(
        id: UpgradeId.siphon,
        name: 'Siphon',
        blurb: 'Grazes charge Overdrive 30% faster',
        maxStacks: 2,
        category: 'Overdrive'),
    UpgradeDef(
        id: UpgradeId.overcharge,
        name: 'Overcharge',
        blurb: '+2s Overdrive duration',
        maxStacks: 2,
        rarity: UpgradeRarity.rare,
        category: 'Overdrive'),
    UpgradeDef(
        id: UpgradeId.chainLink,
        name: 'Chain Link',
        blurb: 'Combos last +1s longer',
        maxStacks: 2,
        category: 'Score'),
  ];

  static UpgradeDef byId(UpgradeId id) => all.firstWhere((u) => u.id == id);
}

/// Stacks owned this run + the derived numbers gameplay reads.
class RunUpgrades {
  final Map<UpgradeId, int> _stacks = {};

  int stacks(UpgradeId id) => _stacks[id] ?? 0;
  bool get isEmpty => _stacks.isEmpty;

  /// Picks in the order taken (for the game-over build summary).
  final List<UpgradeId> history = [];

  bool canTake(UpgradeId id) => stacks(id) < UpgradeCatalog.byId(id).maxStacks;

  void take(UpgradeId id) {
    if (!canTake(id)) return;
    _stacks[id] = stacks(id) + 1;
    history.add(id);
  }

  /// Stack an upgrade that came with the ship frame (not a draft pick, so it
  /// stays out of [history]); still counts toward the draft cap.
  void grant(UpgradeId id) {
    if (!canTake(id)) return;
    _stacks[id] = stacks(id) + 1;
  }

  void clear() {
    _stacks.clear();
    history.clear();
  }

  /// Up to [count] distinct, not-yet-maxed upgrades, weighted by rarity.
  List<UpgradeDef> draft(math.Random rng, {int count = 3}) {
    final pool = UpgradeCatalog.all.where((u) => canTake(u.id)).toList();
    final picks = <UpgradeDef>[];
    while (picks.length < count && pool.isNotEmpty) {
      final total = pool.fold<int>(0, (a, u) => a + u.weight);
      var roll = rng.nextInt(total);
      for (final u in pool) {
        roll -= u.weight;
        if (roll < 0) {
          picks.add(u);
          pool.remove(u);
          break;
        }
      }
    }
    return picks;
  }

  // ---- derived stats ----

  int get extraParallelShots => stacks(UpgradeId.twinCannon);
  int get sideShotPairs => stacks(UpgradeId.wideSpread);
  double get fireCooldownScale => math.pow(0.85, stacks(UpgradeId.rapidServos)).toDouble();
  int get pierce => stacks(UpgradeId.piercingRounds);
  int get bonusDamage => stacks(UpgradeId.heavyRounds);
  int get wingmen => stacks(UpgradeId.wingman);
  bool get shieldEachLevel => stacks(UpgradeId.shieldRegen) > 0;
  double get damageTakenScale => math.pow(0.8, stacks(UpgradeId.hullPlating)).toDouble();

  /// Always-on magnet radius in px (0 = none).
  double get magnetRadius => switch (stacks(UpgradeId.magnetField)) {
        0 => 0,
        1 => 170,
        _ => 260,
      };
  int get missilesPerLevel => stacks(UpgradeId.missileRack) * 2;
  double get grazeRangeScale => 1 + 0.3 * stacks(UpgradeId.grazeField);
  double get grazeChargeScale => 1 + 0.3 * stacks(UpgradeId.siphon);
  double get overdriveBonusSeconds => 2.0 * stacks(UpgradeId.overcharge);
  double get chainWindowBonus => 1.0 * stacks(UpgradeId.chainLink);
}
