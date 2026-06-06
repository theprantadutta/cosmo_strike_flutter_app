import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../components/enemy.dart' show EnemyPattern;
import '../game_assets.dart';

/// How an enemy type shoots. `none` types threaten by contact only.
enum EnemyFireStyle { none, straight, aimed, burst3 }

/// The ten enemy archetypes, mapped 1:1 onto the sprite set. Per-type base
/// stats live in [EnemyTypeStats]; level scalars multiply on top.
enum EnemyType {
  dart,
  wasp,
  drone,
  mine,
  beetle,
  chevron,
  kamikaze,
  gunship,
  crawler,
  saucer,
}

extension EnemyTypeStats on EnemyType {
  String get asset => switch (this) {
        EnemyType.dart => GameAssets.enemyDart,
        EnemyType.wasp => GameAssets.enemyWasp,
        EnemyType.drone => GameAssets.enemyDrone,
        EnemyType.mine => GameAssets.enemyMineSheet,
        EnemyType.beetle => GameAssets.enemyBeetle,
        EnemyType.chevron => GameAssets.enemyChevron,
        EnemyType.kamikaze => GameAssets.enemyKamikaze,
        EnemyType.gunship => GameAssets.enemyGunship,
        EnemyType.crawler => GameAssets.enemyCrawler,
        EnemyType.saucer => GameAssets.enemySaucer,
      };

  /// Logical in-game size (aspect-true to the source art).
  Vector2 get logicalSize => switch (this) {
        EnemyType.dart => Vector2(38, 38),
        EnemyType.wasp => Vector2(38, 38),
        EnemyType.drone => Vector2(36, 36),
        EnemyType.mine => Vector2(34, 34),
        EnemyType.beetle => Vector2(50, 50),
        EnemyType.chevron => Vector2(30, 30),
        EnemyType.kamikaze => Vector2(38, 38),
        EnemyType.gunship => Vector2(54, 54),
        EnemyType.crawler => Vector2(52, 42),
        EnemyType.saucer => Vector2(46, 46),
      };

  int get baseHp => switch (this) {
        EnemyType.dart || EnemyType.wasp || EnemyType.chevron => 1,
        EnemyType.kamikaze => 1,
        EnemyType.drone || EnemyType.mine => 2,
        EnemyType.saucer => 3,
        EnemyType.beetle => 4,
        EnemyType.crawler => 5,
        EnemyType.gunship => 6,
      };

  double get baseSpeed => switch (this) {
        EnemyType.dart => 130,
        EnemyType.wasp => 110,
        EnemyType.drone => 90,
        EnemyType.mine => 55,
        EnemyType.beetle => 70,
        EnemyType.chevron => 150,
        EnemyType.kamikaze => 150,
        EnemyType.gunship => 60,
        EnemyType.crawler => 60,
        EnemyType.saucer => 85,
      };

  EnemyFireStyle get fireStyle => switch (this) {
        EnemyType.mine || EnemyType.chevron || EnemyType.kamikaze =>
          EnemyFireStyle.none,
        EnemyType.dart || EnemyType.wasp || EnemyType.beetle =>
          EnemyFireStyle.straight,
        EnemyType.drone || EnemyType.crawler || EnemyType.saucer =>
          EnemyFireStyle.aimed,
        EnemyType.gunship => EnemyFireStyle.burst3,
      };

  /// Damage dealt to the player on contact (health is 0..1).
  double get contactDamage => switch (this) {
        EnemyType.mine || EnemyType.kamikaze => 0.5,
        EnemyType.beetle || EnemyType.gunship || EnemyType.crawler => 0.4,
        _ => 0.34,
      };

  int get basePoints => switch (this) {
        EnemyType.mine => 80,
        EnemyType.chevron => 90,
        EnemyType.dart => 100,
        EnemyType.wasp => 110,
        EnemyType.drone => 120,
        EnemyType.kamikaze => 130,
        EnemyType.saucer => 150,
        EnemyType.beetle => 160,
        EnemyType.crawler => 180,
        EnemyType.gunship => 200,
      };

  EnemyPattern get defaultPattern => switch (this) {
        EnemyType.dart || EnemyType.drone || EnemyType.beetle =>
          EnemyPattern.straight,
        EnemyType.mine || EnemyType.crawler => EnemyPattern.straight,
        EnemyType.wasp || EnemyType.chevron || EnemyType.saucer =>
          EnemyPattern.sine,
        EnemyType.kamikaze => EnemyPattern.dive,
        EnemyType.gunship => EnemyPattern.tracking,
      };

  /// Ground units ride the floor strip instead of flying.
  bool get floorLocked => this == EnemyType.crawler;
}

/// The five boss archetypes, mapped onto the 512x384 sprites.
enum BossType { dreadnought, hiveQueen, warMachine, leviathan, mothership }

extension BossTypeAsset on BossType {
  String get asset => switch (this) {
        BossType.dreadnought => GameAssets.bossDreadnought,
        BossType.hiveQueen => GameAssets.bossHiveQueen,
        BossType.warMachine => GameAssets.bossWarMachine,
        BossType.leviathan => GameAssets.bossLeviathan,
        BossType.mothership => GameAssets.bossMothership,
      };
}

/// One obstacle archetype a biome can spawn (drifting asteroid or a
/// grounded hazard riding the floor strip).
class ObstacleSpec {
  final String asset;
  final double width;
  final double height;
  final double weight;

  /// Grounded hazards sit on the floor; others drift through open space.
  final bool grounded;

  /// 0 = indestructible scenery hazard; otherwise shootable.
  final int hp;

  /// Points for destroying it (when hp > 0).
  final int points;

  const ObstacleSpec({
    required this.asset,
    required this.width,
    required this.height,
    this.weight = 1,
    this.grounded = false,
    this.hp = 0,
    this.points = 0,
  });
}

/// Visual + hazard identity of a stretch of the campaign.
class BiomeDef {
  final String id;
  final String floorAsset;
  final String? ceilingAsset; // null = open sky
  final double floorHeight; // logical px
  final double ceilingHeight; // 0 when no ceiling
  final List<ObstacleSpec> obstacles;

  /// Deep-space base color behind the starfield for this biome.
  final Color bgColor;

  /// Subtle tint applied to the starfield dots.
  final Color starTint;

  const BiomeDef({
    required this.id,
    required this.floorAsset,
    this.ceilingAsset,
    this.floorHeight = 56,
    this.ceilingHeight = 0,
    this.obstacles = const [],
    required this.bgColor,
    required this.starTint,
  });

  bool get hasCeiling => ceilingAsset != null;
}

/// One scripted spawn group inside a wave: [count] ships of [type] entering
/// every [spawnInterval] seconds inside the vertical band
/// [yBand0]..[yBand1] (fractions of the open playfield).
class WaveEntry {
  final EnemyType type;
  final EnemyPattern? pattern; // null → the type's default pattern
  final int count;
  final double spawnInterval;
  final double yBand0;
  final double yBand1;

  const WaveEntry(
    this.type, {
    this.pattern,
    required this.count,
    this.spawnInterval = 0.55,
    this.yBand0 = 0.1,
    this.yBand1 = 0.9,
  });
}

/// A wave is its entries run back-to-back; the wave completes when all
/// entries have spawned AND no enemy remains alive.
class WaveDef {
  final List<WaveEntry> entries;
  const WaveDef(this.entries);

  int get totalCount => entries.fold(0, (sum, e) => sum + e.count);
}

/// Boss parameters for one level. The same [BossType] reappears across the
/// campaign with scaled stats and attack pacing.
class BossDef {
  final BossType type;
  final int baseHp;
  final double attackInterval;
  final double bulletSpeed;
  final int sprayCount;
  final int aimedCount;

  /// hiveQueen / mothership spawn escort minions at hp thresholds.
  final bool spawnsAdds;

  const BossDef({
    required this.type,
    required this.baseHp,
    this.attackInterval = 1.8,
    this.bulletSpeed = 220,
    this.sprayCount = 12,
    this.aimedCount = 3,
    this.spawnsAdds = false,
  });
}

/// One campaign level: a biome, 3-5 scripted waves, a boss, and difficulty
/// scalars. Pure data — adding a level is appending one of these to the
/// LevelCatalog.
class LevelDef {
  final int index; // 1-based campaign level number
  final String biomeId;
  final List<WaveDef> waves;
  final BossDef boss;
  final double hpScale;
  final double speedScale;
  final double fireRateScale;
  final double scoreScale;

  /// Average obstacle spawns per 10 seconds of play.
  final double obstaclesPerTenSeconds;

  const LevelDef({
    required this.index,
    required this.biomeId,
    required this.waves,
    required this.boss,
    this.hpScale = 1,
    this.speedScale = 1,
    this.fireRateScale = 1,
    this.scoreScale = 1,
    this.obstaclesPerTenSeconds = 2,
  });
}
