import 'package:flutter/painting.dart';

import '../game_assets.dart';
import 'level_def.dart';

/// The four campaign biomes. Display names live in CampaignCatalog
/// (lib/utils/campaign_catalog.dart) so persistence/UI and gameplay can
/// never drift apart on naming.
abstract final class BiomeCatalog {
  static const asteroid = BiomeDef(
    id: 'asteroid',
    floorAsset: GameAssets.terrainAsteroidFloor,
    ceilingAsset: GameAssets.terrainAsteroidCeiling,
    floorHeight: 56,
    ceilingHeight: 48,
    bgColor: Color(0xFF05060F),
    starTint: Color(0xFF9DC6FF),
    obstacles: [
      ObstacleSpec(
        asset: GameAssets.obstacleAsteroidSmall,
        width: 40,
        height: 40,
        weight: 3,
        hp: 2,
        points: 25,
      ),
      ObstacleSpec(
        asset: GameAssets.obstacleAsteroidBig,
        width: 72,
        height: 72,
        weight: 2,
        hp: 5,
        points: 60,
      ),
    ],
  );

  static const city = BiomeDef(
    id: 'city',
    floorAsset: GameAssets.terrainCityFloor,
    floorHeight: 60,
    bgColor: Color(0xFF0A0613),
    starTint: Color(0xFFE2A8FF),
    obstacles: [
      // Drifting debris over the ruined skyline.
      ObstacleSpec(
        asset: GameAssets.obstacleAsteroidSmall,
        width: 40,
        height: 40,
        weight: 2,
        hp: 2,
        points: 25,
      ),
    ],
  );

  static const hive = BiomeDef(
    id: 'hive',
    floorAsset: GameAssets.terrainHiveFloor,
    ceilingAsset: GameAssets.terrainHiveCeiling,
    floorHeight: 56,
    ceilingHeight: 52,
    bgColor: Color(0xFF070D09),
    starTint: Color(0xFFA8FFC2),
    obstacles: [
      // Indestructible organic spikes riding the hive floor.
      ObstacleSpec(
        asset: GameAssets.obstacleSpikePlant,
        width: 48,
        height: 66,
        weight: 3,
        grounded: true,
      ),
      ObstacleSpec(
        asset: GameAssets.obstacleAsteroidSmall,
        width: 40,
        height: 40,
        weight: 1,
        hp: 2,
        points: 25,
      ),
    ],
  );

  static const crystal = BiomeDef(
    id: 'crystal',
    floorAsset: GameAssets.terrainCrystalFloor,
    floorHeight: 58,
    bgColor: Color(0xFF060B16),
    starTint: Color(0xFFB8E8FF),
    obstacles: [
      ObstacleSpec(
        asset: GameAssets.obstacleCrystal,
        width: 48,
        height: 66,
        weight: 3,
        grounded: true,
      ),
      ObstacleSpec(
        asset: GameAssets.obstacleAsteroidBig,
        width: 72,
        height: 72,
        weight: 1,
        hp: 5,
        points: 60,
      ),
    ],
  );

  static const Map<String, BiomeDef> _byId = {
    'asteroid': asteroid,
    'city': city,
    'hive': hive,
    'crystal': crystal,
  };

  static BiomeDef byId(String id) => _byId[id] ?? asteroid;
}

/// The 12 campaign levels — 4 biomes x 3 levels, difficulty ramping via
/// the per-level scalars. Adding level 13+ = appending one LevelDef here
/// (+ a name in CampaignCatalog.levelNames and a backend-safe stageId).
abstract final class LevelCatalog {
  static int get count => levels.length;

  static LevelDef byIndex(int index) =>
      levels[(index - 1).clamp(0, levels.length - 1)];

  static const List<LevelDef> levels = [
    // ============ ASTEROID BELT (1-3) ============
    LevelDef(
      index: 1,
      biomeId: 'asteroid',
      hpScale: 1.0,
      speedScale: 1.0,
      scoreScale: 1.0,
      obstaclesPerTenSeconds: 1.5,
      waves: [
        WaveDef([
          WaveEntry(EnemyType.dart, count: 4, spawnInterval: 0.9),
        ]),
        WaveDef([
          WaveEntry(EnemyType.dart, count: 3, spawnInterval: 0.8),
          WaveEntry(EnemyType.wasp, count: 3, spawnInterval: 0.7),
        ]),
        WaveDef([
          WaveEntry(EnemyType.wasp, count: 4, spawnInterval: 0.6),
          WaveEntry(EnemyType.mine, count: 2, spawnInterval: 1.2),
        ]),
      ],
      boss: BossDef(
        type: BossType.dreadnought,
        baseHp: 60,
        attackInterval: 2.2,
        bulletSpeed: 180,
        sprayCount: 8,
        aimedCount: 2,
      ),
    ),
    LevelDef(
      index: 2,
      biomeId: 'asteroid',
      hpScale: 1.1,
      speedScale: 1.05,
      scoreScale: 1.1,
      obstaclesPerTenSeconds: 2.5,
      waves: [
        WaveDef([
          WaveEntry(EnemyType.dart, count: 4, spawnInterval: 0.7),
          WaveEntry(EnemyType.chevron, count: 3, spawnInterval: 0.5),
        ]),
        WaveDef([
          WaveEntry(EnemyType.drone, count: 3, spawnInterval: 1.0),
          WaveEntry(EnemyType.mine, count: 3, spawnInterval: 1.0),
        ]),
        WaveDef([
          WaveEntry(EnemyType.wasp, count: 4, spawnInterval: 0.6),
          WaveEntry(EnemyType.kamikaze, count: 2, spawnInterval: 1.4),
        ]),
        WaveDef([
          WaveEntry(EnemyType.chevron, count: 4, spawnInterval: 0.45),
          WaveEntry(EnemyType.drone, count: 3, spawnInterval: 0.9),
        ]),
      ],
      boss: BossDef(
        type: BossType.warMachine,
        baseHp: 80,
        attackInterval: 2.0,
        bulletSpeed: 200,
        sprayCount: 10,
        aimedCount: 3,
      ),
    ),
    LevelDef(
      index: 3,
      biomeId: 'asteroid',
      hpScale: 1.2,
      speedScale: 1.1,
      fireRateScale: 1.1,
      scoreScale: 1.2,
      obstaclesPerTenSeconds: 3.5,
      waves: [
        WaveDef([
          WaveEntry(EnemyType.dart, count: 5, spawnInterval: 0.55),
          WaveEntry(EnemyType.mine, count: 3, spawnInterval: 1.0),
        ]),
        WaveDef([
          WaveEntry(EnemyType.saucer, count: 3, spawnInterval: 1.0),
          WaveEntry(EnemyType.wasp, count: 4, spawnInterval: 0.55),
        ]),
        WaveDef([
          WaveEntry(EnemyType.kamikaze, count: 3, spawnInterval: 1.0),
          WaveEntry(EnemyType.drone, count: 4, spawnInterval: 0.8),
        ]),
        WaveDef([
          WaveEntry(EnemyType.beetle, count: 2, spawnInterval: 1.6),
          WaveEntry(EnemyType.chevron, count: 5, spawnInterval: 0.4),
        ]),
      ],
      boss: BossDef(
        type: BossType.dreadnought,
        baseHp: 120,
        attackInterval: 1.8,
        bulletSpeed: 220,
        sprayCount: 12,
        aimedCount: 3,
      ),
    ),

    // ============ NEON RUINS (4-6) ============
    LevelDef(
      index: 4,
      biomeId: 'city',
      hpScale: 1.3,
      speedScale: 1.15,
      fireRateScale: 1.1,
      scoreScale: 1.3,
      obstaclesPerTenSeconds: 2,
      waves: [
        WaveDef([
          WaveEntry(EnemyType.wasp, count: 5, spawnInterval: 0.55),
          WaveEntry(EnemyType.crawler, count: 1, spawnInterval: 1.0),
        ]),
        WaveDef([
          WaveEntry(EnemyType.drone, count: 4, spawnInterval: 0.8),
          WaveEntry(EnemyType.crawler, count: 2, spawnInterval: 2.0),
        ]),
        WaveDef([
          WaveEntry(EnemyType.chevron, count: 5, spawnInterval: 0.4),
          WaveEntry(EnemyType.saucer, count: 3, spawnInterval: 1.0),
        ]),
      ],
      boss: BossDef(
        type: BossType.warMachine,
        baseHp: 150,
        attackInterval: 1.8,
        bulletSpeed: 230,
        sprayCount: 12,
        aimedCount: 3,
      ),
    ),
    LevelDef(
      index: 5,
      biomeId: 'city',
      hpScale: 1.4,
      speedScale: 1.2,
      fireRateScale: 1.15,
      scoreScale: 1.4,
      obstaclesPerTenSeconds: 2.5,
      waves: [
        WaveDef([
          WaveEntry(EnemyType.gunship, count: 1, spawnInterval: 1.0),
          WaveEntry(EnemyType.dart, count: 5, spawnInterval: 0.5),
        ]),
        WaveDef([
          WaveEntry(EnemyType.kamikaze, count: 4, spawnInterval: 0.8),
          WaveEntry(EnemyType.mine, count: 4, spawnInterval: 0.8),
        ]),
        WaveDef([
          WaveEntry(EnemyType.crawler, count: 2, spawnInterval: 1.6),
          WaveEntry(EnemyType.saucer, count: 4, spawnInterval: 0.8),
        ]),
        WaveDef([
          WaveEntry(EnemyType.beetle, count: 3, spawnInterval: 1.2),
          WaveEntry(EnemyType.chevron, count: 5, spawnInterval: 0.4),
        ]),
      ],
      boss: BossDef(
        type: BossType.mothership,
        baseHp: 180,
        attackInterval: 1.9,
        bulletSpeed: 230,
        sprayCount: 12,
        aimedCount: 3,
        spawnsAdds: true,
      ),
    ),
    LevelDef(
      index: 6,
      biomeId: 'city',
      hpScale: 1.5,
      speedScale: 1.25,
      fireRateScale: 1.2,
      scoreScale: 1.5,
      obstaclesPerTenSeconds: 3,
      waves: [
        WaveDef([
          WaveEntry(EnemyType.gunship, count: 2, spawnInterval: 2.0),
          WaveEntry(EnemyType.wasp, count: 5, spawnInterval: 0.5),
        ]),
        WaveDef([
          WaveEntry(EnemyType.drone, count: 5, spawnInterval: 0.7),
          WaveEntry(EnemyType.kamikaze, count: 3, spawnInterval: 1.0),
        ]),
        WaveDef([
          WaveEntry(EnemyType.crawler, count: 3, spawnInterval: 1.4),
          WaveEntry(EnemyType.mine, count: 4, spawnInterval: 0.8),
        ]),
        WaveDef([
          WaveEntry(EnemyType.beetle, count: 3, spawnInterval: 1.2),
          WaveEntry(EnemyType.saucer, count: 4, spawnInterval: 0.7),
        ]),
      ],
      boss: BossDef(
        type: BossType.warMachine,
        baseHp: 220,
        attackInterval: 1.6,
        bulletSpeed: 250,
        sprayCount: 14,
        aimedCount: 3,
      ),
    ),

    // ============ HIVE NEBULA (7-9) ============
    LevelDef(
      index: 7,
      biomeId: 'hive',
      hpScale: 1.7,
      speedScale: 1.3,
      fireRateScale: 1.25,
      scoreScale: 1.7,
      obstaclesPerTenSeconds: 3,
      waves: [
        WaveDef([
          WaveEntry(EnemyType.wasp, count: 6, spawnInterval: 0.45),
          WaveEntry(EnemyType.mine, count: 3, spawnInterval: 1.0),
        ]),
        WaveDef([
          WaveEntry(EnemyType.kamikaze, count: 4, spawnInterval: 0.8),
          WaveEntry(EnemyType.chevron, count: 5, spawnInterval: 0.4),
        ]),
        WaveDef([
          WaveEntry(EnemyType.saucer, count: 4, spawnInterval: 0.8),
          WaveEntry(EnemyType.drone, count: 4, spawnInterval: 0.7),
        ]),
        WaveDef([
          WaveEntry(EnemyType.beetle, count: 3, spawnInterval: 1.2),
          WaveEntry(EnemyType.wasp, count: 5, spawnInterval: 0.5),
        ]),
      ],
      boss: BossDef(
        type: BossType.hiveQueen,
        baseHp: 260,
        attackInterval: 1.8,
        bulletSpeed: 240,
        sprayCount: 12,
        aimedCount: 3,
        spawnsAdds: true,
      ),
    ),
    LevelDef(
      index: 8,
      biomeId: 'hive',
      hpScale: 1.9,
      speedScale: 1.35,
      fireRateScale: 1.3,
      scoreScale: 1.9,
      obstaclesPerTenSeconds: 3.5,
      waves: [
        WaveDef([
          WaveEntry(EnemyType.gunship, count: 2, spawnInterval: 2.0),
          WaveEntry(EnemyType.kamikaze, count: 4, spawnInterval: 0.7),
        ]),
        WaveDef([
          WaveEntry(EnemyType.mine, count: 6, spawnInterval: 0.6),
          WaveEntry(EnemyType.wasp, count: 5, spawnInterval: 0.5),
        ]),
        WaveDef([
          WaveEntry(EnemyType.crawler, count: 3, spawnInterval: 1.4),
          WaveEntry(EnemyType.saucer, count: 4, spawnInterval: 0.7),
        ]),
        WaveDef([
          WaveEntry(EnemyType.beetle, count: 4, spawnInterval: 1.0),
          WaveEntry(EnemyType.chevron, count: 6, spawnInterval: 0.35),
        ]),
        WaveDef([
          WaveEntry(EnemyType.drone, count: 5, spawnInterval: 0.6),
          WaveEntry(EnemyType.kamikaze, count: 4, spawnInterval: 0.7),
        ]),
      ],
      boss: BossDef(
        type: BossType.hiveQueen,
        baseHp: 320,
        attackInterval: 1.6,
        bulletSpeed: 250,
        sprayCount: 14,
        aimedCount: 4,
        spawnsAdds: true,
      ),
    ),
    LevelDef(
      index: 9,
      biomeId: 'hive',
      hpScale: 2.1,
      speedScale: 1.4,
      fireRateScale: 1.35,
      scoreScale: 2.1,
      obstaclesPerTenSeconds: 4,
      waves: [
        WaveDef([
          WaveEntry(EnemyType.wasp, count: 7, spawnInterval: 0.4),
          WaveEntry(EnemyType.mine, count: 4, spawnInterval: 0.8),
        ]),
        WaveDef([
          WaveEntry(EnemyType.gunship, count: 2, spawnInterval: 2.0),
          WaveEntry(EnemyType.saucer, count: 5, spawnInterval: 0.6),
        ]),
        WaveDef([
          WaveEntry(EnemyType.kamikaze, count: 5, spawnInterval: 0.6),
          WaveEntry(EnemyType.chevron, count: 6, spawnInterval: 0.35),
        ]),
        WaveDef([
          WaveEntry(EnemyType.beetle, count: 4, spawnInterval: 1.0),
          WaveEntry(EnemyType.crawler, count: 3, spawnInterval: 1.4),
        ]),
        WaveDef([
          WaveEntry(EnemyType.drone, count: 6, spawnInterval: 0.5),
          WaveEntry(EnemyType.wasp, count: 6, spawnInterval: 0.45),
        ]),
      ],
      boss: BossDef(
        type: BossType.hiveQueen,
        baseHp: 380,
        attackInterval: 1.5,
        bulletSpeed: 260,
        sprayCount: 16,
        aimedCount: 4,
        spawnsAdds: true,
      ),
    ),

    // ============ CRYSTAL EXPANSE (10-12) ============
    LevelDef(
      index: 10,
      biomeId: 'crystal',
      hpScale: 2.3,
      speedScale: 1.45,
      fireRateScale: 1.4,
      scoreScale: 2.3,
      obstaclesPerTenSeconds: 3.5,
      waves: [
        WaveDef([
          WaveEntry(EnemyType.dart, count: 6, spawnInterval: 0.45),
          WaveEntry(EnemyType.saucer, count: 4, spawnInterval: 0.7),
        ]),
        WaveDef([
          WaveEntry(EnemyType.gunship, count: 3, spawnInterval: 1.6),
          WaveEntry(EnemyType.mine, count: 5, spawnInterval: 0.6),
        ]),
        WaveDef([
          WaveEntry(EnemyType.kamikaze, count: 5, spawnInterval: 0.6),
          WaveEntry(EnemyType.beetle, count: 3, spawnInterval: 1.2),
        ]),
        WaveDef([
          WaveEntry(EnemyType.crawler, count: 4, spawnInterval: 1.2),
          WaveEntry(EnemyType.chevron, count: 6, spawnInterval: 0.35),
        ]),
      ],
      boss: BossDef(
        type: BossType.leviathan,
        baseHp: 440,
        attackInterval: 1.6,
        bulletSpeed: 260,
        sprayCount: 14,
        aimedCount: 4,
      ),
    ),
    LevelDef(
      index: 11,
      biomeId: 'crystal',
      hpScale: 2.45,
      speedScale: 1.5,
      fireRateScale: 1.45,
      scoreScale: 2.45,
      obstaclesPerTenSeconds: 4,
      waves: [
        WaveDef([
          WaveEntry(EnemyType.wasp, count: 7, spawnInterval: 0.4),
          WaveEntry(EnemyType.gunship, count: 2, spawnInterval: 1.8),
        ]),
        WaveDef([
          WaveEntry(EnemyType.mine, count: 6, spawnInterval: 0.5),
          WaveEntry(EnemyType.kamikaze, count: 5, spawnInterval: 0.6),
        ]),
        WaveDef([
          WaveEntry(EnemyType.saucer, count: 5, spawnInterval: 0.6),
          WaveEntry(EnemyType.drone, count: 6, spawnInterval: 0.5),
        ]),
        WaveDef([
          WaveEntry(EnemyType.beetle, count: 4, spawnInterval: 1.0),
          WaveEntry(EnemyType.crawler, count: 4, spawnInterval: 1.2),
        ]),
        WaveDef([
          WaveEntry(EnemyType.chevron, count: 8, spawnInterval: 0.3),
          WaveEntry(EnemyType.gunship, count: 2, spawnInterval: 1.8),
        ]),
      ],
      boss: BossDef(
        type: BossType.mothership,
        baseHp: 500,
        attackInterval: 1.5,
        bulletSpeed: 270,
        sprayCount: 16,
        aimedCount: 4,
        spawnsAdds: true,
      ),
    ),
    LevelDef(
      index: 12,
      biomeId: 'crystal',
      hpScale: 2.6,
      speedScale: 1.5,
      fireRateScale: 1.5,
      scoreScale: 2.6,
      obstaclesPerTenSeconds: 4.5,
      waves: [
        WaveDef([
          WaveEntry(EnemyType.dart, count: 7, spawnInterval: 0.4),
          WaveEntry(EnemyType.saucer, count: 5, spawnInterval: 0.6),
        ]),
        WaveDef([
          WaveEntry(EnemyType.gunship, count: 3, spawnInterval: 1.5),
          WaveEntry(EnemyType.kamikaze, count: 6, spawnInterval: 0.5),
        ]),
        WaveDef([
          WaveEntry(EnemyType.mine, count: 7, spawnInterval: 0.45),
          WaveEntry(EnemyType.wasp, count: 7, spawnInterval: 0.4),
        ]),
        WaveDef([
          WaveEntry(EnemyType.beetle, count: 5, spawnInterval: 0.9),
          WaveEntry(EnemyType.crawler, count: 4, spawnInterval: 1.2),
        ]),
        WaveDef([
          WaveEntry(EnemyType.chevron, count: 8, spawnInterval: 0.3),
          WaveEntry(EnemyType.drone, count: 6, spawnInterval: 0.5),
          WaveEntry(EnemyType.kamikaze, count: 4, spawnInterval: 0.6),
        ]),
      ],
      boss: BossDef(
        type: BossType.mothership,
        baseHp: 600,
        attackInterval: 1.35,
        bulletSpeed: 280,
        sprayCount: 18,
        aimedCount: 5,
        spawnsAdds: true,
      ),
    ),
  ];
}
