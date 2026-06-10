import 'package:flutter/painting.dart';

import '../game_assets.dart';
import 'formation.dart';
import 'level_def.dart';
import 'level_script.dart';

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

/// The 12 campaign levels — 4 biomes x 3 levels, each a choreographed
/// [LevelScript] ending in its boss. Adding level 13+ = appending one
/// LevelDef here (+ a name in CampaignCatalog.levelNames and a
/// backend-safe stageId).
///
/// NOTE: this is currently the MECHANICAL conversion of the old random
/// waves (loose streams + field-clear barriers — identical feel). The
/// creative re-author (real formations, set-pieces, terrain profiles)
/// replaces these scripts in the next overhaul step.
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
      script: LevelScript([
        FormationEvent(
            0.6, FormationSpec.stream(EnemyType.dart, count: 4, every: 0.9),
            countsAsSection: true),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.dart, count: 3, every: 0.8),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            2.4, FormationSpec.stream(EnemyType.wasp, count: 3, every: 0.7)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.wasp, count: 4, every: 0.6),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            2.4, FormationSpec.stream(EnemyType.mine, count: 2, every: 1.2)),
        BossEvent(),
      ]),
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
      script: LevelScript([
        FormationEvent(
            0.6, FormationSpec.stream(EnemyType.dart, count: 4, every: 0.7),
            countsAsSection: true),
        FormationEvent(2.8,
            FormationSpec.stream(EnemyType.chevron, count: 3, every: 0.5)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.drone, count: 3, every: 1.0),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            3.0, FormationSpec.stream(EnemyType.mine, count: 3, every: 1.0)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.wasp, count: 4, every: 0.6),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(2.4,
            FormationSpec.stream(EnemyType.kamikaze, count: 2, every: 1.4)),
        FormationEvent(1.0,
            FormationSpec.stream(EnemyType.chevron, count: 4, every: 0.45),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            1.8, FormationSpec.stream(EnemyType.drone, count: 3, every: 0.9)),
        BossEvent(),
      ]),
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
      script: LevelScript([
        FormationEvent(
            0.6, FormationSpec.stream(EnemyType.dart, count: 5, every: 0.55),
            countsAsSection: true),
        FormationEvent(
            2.75, FormationSpec.stream(EnemyType.mine, count: 3, every: 1.0)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.saucer, count: 3, every: 1.0),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            3.0, FormationSpec.stream(EnemyType.wasp, count: 4, every: 0.55)),
        FormationEvent(1.0,
            FormationSpec.stream(EnemyType.kamikaze, count: 3, every: 1.0),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            3.0, FormationSpec.stream(EnemyType.drone, count: 4, every: 0.8)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.beetle, count: 2, every: 1.6),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(3.2,
            FormationSpec.stream(EnemyType.chevron, count: 5, every: 0.4)),
        BossEvent(),
      ]),
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
      script: LevelScript([
        FormationEvent(
            0.6, FormationSpec.stream(EnemyType.wasp, count: 5, every: 0.55),
            countsAsSection: true),
        FormationEvent(2.75,
            FormationSpec.stream(EnemyType.crawler, count: 1, every: 1.0)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.drone, count: 4, every: 0.8),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(3.2,
            FormationSpec.stream(EnemyType.crawler, count: 2, every: 2.0)),
        FormationEvent(1.0,
            FormationSpec.stream(EnemyType.chevron, count: 5, every: 0.4),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            2.0, FormationSpec.stream(EnemyType.saucer, count: 3, every: 1.0)),
        BossEvent(),
      ]),
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
      script: LevelScript([
        FormationEvent(
            0.6, FormationSpec.stream(EnemyType.gunship, count: 1, every: 1.0),
            countsAsSection: true),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.dart, count: 5, every: 0.5)),
        FormationEvent(1.0,
            FormationSpec.stream(EnemyType.kamikaze, count: 4, every: 0.8),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            3.2, FormationSpec.stream(EnemyType.mine, count: 4, every: 0.8)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.crawler, count: 2, every: 1.6),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            3.2, FormationSpec.stream(EnemyType.saucer, count: 4, every: 0.8)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.beetle, count: 3, every: 1.2),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(3.6,
            FormationSpec.stream(EnemyType.chevron, count: 5, every: 0.4)),
        BossEvent(),
      ]),
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
      script: LevelScript([
        FormationEvent(
            0.6, FormationSpec.stream(EnemyType.gunship, count: 2, every: 2.0),
            countsAsSection: true),
        FormationEvent(
            4.0, FormationSpec.stream(EnemyType.wasp, count: 5, every: 0.5)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.drone, count: 5, every: 0.7),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(3.5,
            FormationSpec.stream(EnemyType.kamikaze, count: 3, every: 1.0)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.crawler, count: 3, every: 1.4),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            4.2, FormationSpec.stream(EnemyType.mine, count: 4, every: 0.8)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.beetle, count: 3, every: 1.2),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            3.6, FormationSpec.stream(EnemyType.saucer, count: 4, every: 0.7)),
        BossEvent(),
      ]),
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
      script: LevelScript([
        FormationEvent(
            0.6, FormationSpec.stream(EnemyType.wasp, count: 6, every: 0.45),
            countsAsSection: true),
        FormationEvent(
            2.7, FormationSpec.stream(EnemyType.mine, count: 3, every: 1.0)),
        FormationEvent(1.0,
            FormationSpec.stream(EnemyType.kamikaze, count: 4, every: 0.8),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(3.2,
            FormationSpec.stream(EnemyType.chevron, count: 5, every: 0.4)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.saucer, count: 4, every: 0.8),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            3.2, FormationSpec.stream(EnemyType.drone, count: 4, every: 0.7)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.beetle, count: 3, every: 1.2),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            3.6, FormationSpec.stream(EnemyType.wasp, count: 5, every: 0.5)),
        BossEvent(),
      ]),
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
      script: LevelScript([
        FormationEvent(
            0.6, FormationSpec.stream(EnemyType.gunship, count: 2, every: 2.0),
            countsAsSection: true),
        FormationEvent(4.0,
            FormationSpec.stream(EnemyType.kamikaze, count: 4, every: 0.7)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.mine, count: 6, every: 0.6),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            3.6, FormationSpec.stream(EnemyType.wasp, count: 5, every: 0.5)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.crawler, count: 3, every: 1.4),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            4.2, FormationSpec.stream(EnemyType.saucer, count: 4, every: 0.7)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.beetle, count: 4, every: 1.0),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(4.0,
            FormationSpec.stream(EnemyType.chevron, count: 6, every: 0.35)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.drone, count: 5, every: 0.6),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(3.0,
            FormationSpec.stream(EnemyType.kamikaze, count: 4, every: 0.7)),
        BossEvent(),
      ]),
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
      script: LevelScript([
        FormationEvent(
            0.6, FormationSpec.stream(EnemyType.wasp, count: 7, every: 0.4),
            countsAsSection: true),
        FormationEvent(
            2.8, FormationSpec.stream(EnemyType.mine, count: 4, every: 0.8)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.gunship, count: 2, every: 2.0),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            4.0, FormationSpec.stream(EnemyType.saucer, count: 5, every: 0.6)),
        FormationEvent(1.0,
            FormationSpec.stream(EnemyType.kamikaze, count: 5, every: 0.6),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(3.0,
            FormationSpec.stream(EnemyType.chevron, count: 6, every: 0.35)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.beetle, count: 4, every: 1.0),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(4.0,
            FormationSpec.stream(EnemyType.crawler, count: 3, every: 1.4)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.drone, count: 6, every: 0.5),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            3.0, FormationSpec.stream(EnemyType.wasp, count: 6, every: 0.45)),
        BossEvent(),
      ]),
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
      script: LevelScript([
        FormationEvent(
            0.6, FormationSpec.stream(EnemyType.dart, count: 6, every: 0.45),
            countsAsSection: true),
        FormationEvent(
            2.7, FormationSpec.stream(EnemyType.saucer, count: 4, every: 0.7)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.gunship, count: 3, every: 1.6),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            4.8, FormationSpec.stream(EnemyType.mine, count: 5, every: 0.6)),
        FormationEvent(1.0,
            FormationSpec.stream(EnemyType.kamikaze, count: 5, every: 0.6),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            3.0, FormationSpec.stream(EnemyType.beetle, count: 3, every: 1.2)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.crawler, count: 4, every: 1.2),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(4.8,
            FormationSpec.stream(EnemyType.chevron, count: 6, every: 0.35)),
        BossEvent(),
      ]),
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
      script: LevelScript([
        FormationEvent(
            0.6, FormationSpec.stream(EnemyType.wasp, count: 7, every: 0.4),
            countsAsSection: true),
        FormationEvent(2.8,
            FormationSpec.stream(EnemyType.gunship, count: 2, every: 1.8)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.mine, count: 6, every: 0.5),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(3.0,
            FormationSpec.stream(EnemyType.kamikaze, count: 5, every: 0.6)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.saucer, count: 5, every: 0.6),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            3.0, FormationSpec.stream(EnemyType.drone, count: 6, every: 0.5)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.beetle, count: 4, every: 1.0),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(4.0,
            FormationSpec.stream(EnemyType.crawler, count: 4, every: 1.2)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.chevron, count: 8, every: 0.3),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(2.4,
            FormationSpec.stream(EnemyType.gunship, count: 2, every: 1.8)),
        BossEvent(),
      ]),
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
      script: LevelScript([
        FormationEvent(
            0.6, FormationSpec.stream(EnemyType.dart, count: 7, every: 0.4),
            countsAsSection: true),
        FormationEvent(
            2.8, FormationSpec.stream(EnemyType.saucer, count: 5, every: 0.6)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.gunship, count: 3, every: 1.5),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(4.5,
            FormationSpec.stream(EnemyType.kamikaze, count: 6, every: 0.5)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.mine, count: 7, every: 0.45),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            3.15, FormationSpec.stream(EnemyType.wasp, count: 7, every: 0.4)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.beetle, count: 5, every: 0.9),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(4.5,
            FormationSpec.stream(EnemyType.crawler, count: 4, every: 1.2)),
        FormationEvent(
            1.0, FormationSpec.stream(EnemyType.chevron, count: 8, every: 0.3),
            countsAsSection: true, waitForFieldClear: true),
        FormationEvent(
            2.4, FormationSpec.stream(EnemyType.drone, count: 6, every: 0.5)),
        FormationEvent(3.0,
            FormationSpec.stream(EnemyType.kamikaze, count: 4, every: 0.6)),
        BossEvent(),
      ]),
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
