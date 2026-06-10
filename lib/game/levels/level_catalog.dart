import 'package:flutter/painting.dart';

import '../components/power_up.dart' show PowerUpKind;
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

/// The 12 campaign levels — 4 biomes x 3 levels, each a hand-authored
/// choreography following the intensity curve: STATEMENT (one readable
/// formation introducing the level's idea) → ESCALATION → SET-PIECE
/// (corridor squeeze / canyon chase / ambush) → BREATHER (+ guaranteed
/// drop) → PRE-BOSS CLIMAX → BOSS. Each level teaches ONE new thing.
/// Adding level 13+ = appending one LevelDef here (+ a name in
/// CampaignCatalog.levelNames and a backend-safe stageId).
abstract final class LevelCatalog {
  static int get count => levels.length;

  static LevelDef byIndex(int index) =>
      levels[(index - 1).clamp(0, levels.length - 1)];

  static const List<LevelDef> levels = [
    // ===================== ASTEROID BELT (1-3) =====================
    // L1 teaches: formations are units (wipe them!) + threading a wall.
    LevelDef(
      index: 1,
      biomeId: 'asteroid',
      hpScale: 1.0,
      speedScale: 1.0,
      scoreScale: 1.0,
      obstaclesPerTenSeconds: 1.5,
      script: LevelScript([
        FormationEvent(
            0.8,
            FormationSpec(
                shape: FormationShape.vWedge, type: EnemyType.dart, count: 5),
            countsAsSection: true),
        FormationEvent(4.5,
            FormationSpec.stream(EnemyType.wasp, count: 3, every: 0.7)),
        FormationEvent(
            1.2,
            FormationSpec(
                shape: FormationShape.wallWithGap,
                type: EnemyType.dart,
                count: 7,
                gap01: 0.5,
                wipeDrop: PowerUpKind.shield),
            countsAsSection: true,
            waitForFieldClear: true),
        DropEvent(2.5, PowerUpKind.weapon),
        FormationEvent(
            2.0,
            FormationSpec(
                shape: FormationShape.vWedge,
                type: EnemyType.wasp,
                count: 5,
                y01: 0.35),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(3.5,
            FormationSpec.stream(EnemyType.mine, count: 2, every: 1.2)),
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
    // L2 teaches: snake chains weave + column dives drop from above.
    LevelDef(
      index: 2,
      biomeId: 'asteroid',
      hpScale: 1.1,
      speedScale: 1.05,
      scoreScale: 1.1,
      obstaclesPerTenSeconds: 2.5,
      script: LevelScript([
        FormationEvent(
            0.8,
            FormationSpec(
                shape: FormationShape.snakeChain,
                type: EnemyType.wasp,
                count: 6),
            countsAsSection: true),
        FormationEvent(4.0,
            FormationSpec.stream(EnemyType.dart, count: 4, every: 0.7)),
        FormationEvent(
            1.2,
            FormationSpec(
                shape: FormationShape.columnDive,
                type: EnemyType.chevron,
                count: 5,
                y01: 0.4),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(
            3.0,
            FormationSpec(
                shape: FormationShape.vWedge,
                type: EnemyType.dart,
                count: 5,
                y01: 0.65)),
        SetPieceEvent(1.5,
            duration: 8,
            banner: 'ASTEROID DRIFT',
            floorScale: 1.9,
            ceilScale: 1.9,
            mineRainPerSecond: 0.35),
        DropEvent(3.0, PowerUpKind.shield, y01: 0.5),
        FormationEvent(
            6.0,
            FormationSpec(
                shape: FormationShape.snakeChain,
                type: EnemyType.chevron,
                count: 7,
                y01: 0.5),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(
            2.5,
            FormationSpec(
                shape: FormationShape.columnDive,
                type: EnemyType.drone,
                count: 4,
                y01: 0.6)),
        BossEvent(),
      ]),
      boss: BossDef(
        type: BossType.dreadnought,
        baseHp: 85,
        attackInterval: 2.0,
        bulletSpeed: 200,
        sprayCount: 10,
        aimedCount: 3,
      ),
    ),
    // L3 teaches: pincers, the rear AMBUSH, and the canyon chase.
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
            0.8,
            FormationSpec(
                shape: FormationShape.vWedge, type: EnemyType.dart, count: 5),
            countsAsSection: true),
        FormationEvent(
            3.5,
            FormationSpec(
                shape: FormationShape.snakeChain,
                type: EnemyType.wasp,
                count: 6)),
        FormationEvent(
            1.2,
            FormationSpec(
                shape: FormationShape.pincer,
                type: EnemyType.chevron,
                count: 6),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(3.0,
            FormationSpec.stream(EnemyType.drone, count: 4, every: 0.8)),
        FormationEvent(
            2.0,
            FormationSpec(
                shape: FormationShape.ambushRear,
                type: EnemyType.chevron,
                count: 4,
                y01: 0.55,
                wipeDrop: PowerUpKind.x2),
            countsAsSection: true),
        DropEvent(1.5, PowerUpKind.missiles, y01: 0.35),
        SetPieceEvent(1.5,
            duration: 12,
            banner: 'CANYON RUN',
            floorScale: 3.2,
            ceilScale: 3.0,
            scrollScale: 1.8,
            mineRainPerSecond: 0.7,
            waitForFieldClear: true),
        FormationEvent(
            13.0,
            FormationSpec(
                shape: FormationShape.pincer,
                type: EnemyType.wasp,
                count: 8,
                wipeDrop: PowerUpKind.shield),
            countsAsSection: true),
        FormationEvent(
            2.5,
            FormationSpec(
                shape: FormationShape.vWedge,
                type: EnemyType.beetle,
                count: 3)),
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

    // ===================== NEON RUINS (4-6) =====================
    // L4 teaches: floor turrets — the ground itself shoots back.
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
            0.8,
            FormationSpec(
                shape: FormationShape.vWedge, type: EnemyType.wasp, count: 5),
            countsAsSection: true),
        FormationEvent(3.0,
            FormationSpec.stream(EnemyType.turret, count: 2, every: 2.6)),
        FormationEvent(
            1.2,
            FormationSpec(
                shape: FormationShape.snakeChain,
                type: EnemyType.drone,
                count: 5),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(3.0,
            FormationSpec.stream(EnemyType.crawler, count: 2, every: 2.0)),
        FormationEvent(2.0,
            FormationSpec.stream(EnemyType.turret, count: 2, every: 2.6)),
        DropEvent(2.0, PowerUpKind.weapon),
        FormationEvent(
            2.0,
            FormationSpec(
                shape: FormationShape.columnDive,
                type: EnemyType.chevron,
                count: 6),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(2.5,
            FormationSpec.stream(EnemyType.saucer, count: 3, every: 1.0)),
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
    // L5 teaches: escort convoys — break the guards to reach the tank.
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
            0.8,
            FormationSpec(
                shape: FormationShape.escortConvoy,
                type: EnemyType.saucer,
                secondaryType: EnemyType.beetle,
                count: 5,
                wipeBonus: 350),
            countsAsSection: true),
        FormationEvent(4.0,
            FormationSpec.stream(EnemyType.dart, count: 5, every: 0.5)),
        FormationEvent(
            1.2,
            FormationSpec(
                shape: FormationShape.escortConvoy,
                type: EnemyType.wasp,
                secondaryType: EnemyType.gunship,
                count: 5,
                y01: 0.4,
                wipeBonus: 400,
                wipeDrop: PowerUpKind.missiles),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(3.0,
            FormationSpec.stream(EnemyType.turret, count: 2, every: 2.4)),
        SetPieceEvent(2.0,
            duration: 9,
            banner: 'ROOFTOP PRESSURE',
            floorScale: 2.8,
            scrollScale: 1.4,
            mineRainPerSecond: 0.4),
        DropEvent(3.0, PowerUpKind.x2),
        FormationEvent(
            7.0,
            FormationSpec(
                shape: FormationShape.pincer,
                type: EnemyType.kamikaze,
                count: 6),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(
            2.5,
            FormationSpec(
                shape: FormationShape.escortConvoy,
                type: EnemyType.wasp,
                secondaryType: EnemyType.beetle,
                count: 5,
                y01: 0.6)),
        BossEvent(),
      ]),
      boss: BossDef(
        type: BossType.warMachine,
        baseHp: 185,
        attackInterval: 1.7,
        bulletSpeed: 235,
        sprayCount: 12,
        aimedCount: 3,
      ),
    ),
    // L6 teaches: ring spinners + the skyline squeeze.
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
            0.8,
            FormationSpec(
                shape: FormationShape.ringSpinner,
                type: EnemyType.saucer,
                count: 6,
                wipeBonus: 350),
            countsAsSection: true),
        FormationEvent(3.5,
            FormationSpec.stream(EnemyType.turret, count: 2, every: 2.4)),
        FormationEvent(
            1.2,
            FormationSpec(
                shape: FormationShape.snakeChain,
                type: EnemyType.kamikaze,
                count: 6),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(
            3.0,
            FormationSpec(
                shape: FormationShape.ringSpinner,
                type: EnemyType.chevron,
                count: 8,
                y01: 0.45)),
        SetPieceEvent(1.5,
            duration: 10,
            banner: 'SKYLINE SQUEEZE',
            floorScale: 3.2,
            scrollScale: 1.5,
            mineRainPerSecond: 0.5),
        DropEvent(3.0, PowerUpKind.shield),
        FormationEvent(
            8.0,
            FormationSpec(
                shape: FormationShape.ringSpinner,
                type: EnemyType.drone,
                count: 8),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(
            2.5,
            FormationSpec(
                shape: FormationShape.escortConvoy,
                type: EnemyType.wasp,
                secondaryType: EnemyType.gunship,
                count: 5,
                wipeBonus: 400)),
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

    // ===================== HIVE NEBULA (7-9) =====================
    // L7 teaches: ceiling turrets + the hive tunnel squeeze.
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
            0.8,
            FormationSpec(
                shape: FormationShape.snakeChain,
                type: EnemyType.wasp,
                count: 7),
            countsAsSection: true),
        FormationEvent(
            3.0,
            FormationSpec.stream(EnemyType.turret,
                count: 2, every: 2.6, mountCeiling: true)),
        FormationEvent(
            1.2,
            FormationSpec(
                shape: FormationShape.pincer,
                type: EnemyType.kamikaze,
                count: 6),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(3.0,
            FormationSpec.stream(EnemyType.turret, count: 2, every: 2.6)),
        SetPieceEvent(1.5,
            duration: 10,
            banner: 'HIVE TUNNEL',
            floorScale: 3.0,
            ceilScale: 3.0,
            scrollScale: 1.3,
            mineRainPerSecond: 0.4),
        DropEvent(3.0, PowerUpKind.weapon),
        FormationEvent(
            8.0,
            FormationSpec(
                shape: FormationShape.snakeChain,
                type: EnemyType.wasp,
                count: 8,
                y01: 0.45),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(
            2.0,
            FormationSpec(
                shape: FormationShape.columnDive,
                type: EnemyType.mine,
                count: 5)),
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
    // L8 teaches: mine walls + fighting under turret crossfire.
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
            0.8,
            FormationSpec(
                shape: FormationShape.columnDive,
                type: EnemyType.wasp,
                count: 6),
            countsAsSection: true),
        FormationEvent(
            3.0,
            FormationSpec(
                shape: FormationShape.snakeChain,
                type: EnemyType.saucer,
                count: 5,
                y01: 0.6)),
        FormationEvent(
            1.2,
            FormationSpec(
                shape: FormationShape.wallWithGap,
                type: EnemyType.mine,
                count: 8,
                gap01: 0.35,
                wipeDrop: PowerUpKind.bomb),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(
            3.0,
            FormationSpec.stream(EnemyType.turret,
                count: 2, every: 2.4, mountCeiling: true)),
        FormationEvent(2.0,
            FormationSpec.stream(EnemyType.turret, count: 1, every: 1.0)),
        FormationEvent(
            2.0,
            FormationSpec(
                shape: FormationShape.pincer,
                type: EnemyType.chevron,
                count: 8),
            countsAsSection: true,
            waitForFieldClear: true),
        DropEvent(2.0, PowerUpKind.missiles),
        SetPieceEvent(1.5,
            duration: 11,
            banner: 'SPORE STORM',
            floorScale: 2.6,
            ceilScale: 2.6,
            scrollScale: 1.4,
            mineRainPerSecond: 0.8),
        FormationEvent(
            12.0,
            FormationSpec(
                shape: FormationShape.snakeChain,
                type: EnemyType.kamikaze,
                count: 7),
            countsAsSection: true),
        FormationEvent(
            2.0,
            FormationSpec(
                shape: FormationShape.escortConvoy,
                type: EnemyType.wasp,
                secondaryType: EnemyType.gunship,
                count: 5,
                wipeBonus: 400)),
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
    // L9: the formation-mastery exam — every shape, back to back.
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
            0.8,
            FormationSpec(
                shape: FormationShape.vWedge, type: EnemyType.wasp, count: 7),
            countsAsSection: true),
        FormationEvent(
            3.0,
            FormationSpec(
                shape: FormationShape.ringSpinner,
                type: EnemyType.saucer,
                count: 6,
                y01: 0.4)),
        FormationEvent(
            1.2,
            FormationSpec(
                shape: FormationShape.pincer,
                type: EnemyType.kamikaze,
                count: 8),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(
            2.5,
            FormationSpec(
                shape: FormationShape.ambushRear,
                type: EnemyType.chevron,
                count: 5,
                y01: 0.5,
                wipeDrop: PowerUpKind.x2)),
        FormationEvent(
            1.5,
            FormationSpec(
                shape: FormationShape.wallWithGap,
                type: EnemyType.mine,
                count: 9,
                gap01: 0.6),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(
            2.5,
            FormationSpec(
                shape: FormationShape.snakeChain,
                type: EnemyType.drone,
                count: 7)),
        DropEvent(1.5, PowerUpKind.shield, y01: 0.3),
        SetPieceEvent(1.5,
            duration: 12,
            banner: 'DEEP HIVE',
            floorScale: 3.2,
            ceilScale: 3.2,
            scrollScale: 1.5,
            mineRainPerSecond: 0.6),
        FormationEvent(
            13.0,
            FormationSpec(
                shape: FormationShape.columnDive,
                type: EnemyType.beetle,
                count: 4),
            countsAsSection: true),
        FormationEvent(
            2.0,
            FormationSpec(
                shape: FormationShape.snakeChain,
                type: EnemyType.wasp,
                count: 7,
                y01: 0.55)),
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

    // ===================== CRYSTAL EXPANSE (10-12) =====================
    // L10: walls everywhere — then the Leviathan, who IS the wall.
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
            0.8,
            FormationSpec(
                shape: FormationShape.wallWithGap,
                type: EnemyType.dart,
                count: 8,
                gap01: 0.5),
            countsAsSection: true),
        FormationEvent(3.0,
            FormationSpec.stream(EnemyType.saucer, count: 4, every: 0.7)),
        FormationEvent(
            1.2,
            FormationSpec(
                shape: FormationShape.ringSpinner,
                type: EnemyType.chevron,
                count: 8),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(3.0,
            FormationSpec.stream(EnemyType.turret, count: 2, every: 2.4)),
        FormationEvent(
            2.0,
            FormationSpec(
                shape: FormationShape.pincer,
                type: EnemyType.kamikaze,
                count: 8),
            countsAsSection: true,
            waitForFieldClear: true),
        DropEvent(2.0, PowerUpKind.missiles),
        SetPieceEvent(1.5,
            duration: 12,
            banner: 'CRYSTAL CANYON',
            floorScale: 3.4,
            scrollScale: 1.7,
            mineRainPerSecond: 0.7),
        FormationEvent(
            13.0,
            FormationSpec(
                shape: FormationShape.wallWithGap,
                type: EnemyType.mine,
                count: 9,
                gap01: 0.4,
                wipeDrop: PowerUpKind.bomb),
            countsAsSection: true),
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
    // L11: everything you've learned, mixed and faster.
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
            0.8,
            FormationSpec(
                shape: FormationShape.escortConvoy,
                type: EnemyType.wasp,
                secondaryType: EnemyType.gunship,
                count: 6,
                wipeBonus: 450,
                wipeDrop: PowerUpKind.missiles),
            countsAsSection: true),
        FormationEvent(
            3.5,
            FormationSpec(
                shape: FormationShape.ambushRear,
                type: EnemyType.chevron,
                count: 5,
                y01: 0.45)),
        FormationEvent(
            1.2,
            FormationSpec(
                shape: FormationShape.ringSpinner,
                type: EnemyType.saucer,
                count: 8),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(
            3.0,
            FormationSpec(
                shape: FormationShape.columnDive,
                type: EnemyType.kamikaze,
                count: 6)),
        SetPieceEvent(1.5,
            duration: 10,
            banner: 'SHARD FIELD',
            floorScale: 2.8,
            scrollScale: 1.5,
            mineRainPerSecond: 0.8),
        DropEvent(3.0, PowerUpKind.x2),
        FormationEvent(
            8.0,
            FormationSpec(
                shape: FormationShape.pincer,
                type: EnemyType.beetle,
                count: 6,
                wipeBonus: 400),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(
            2.0,
            FormationSpec(
                shape: FormationShape.snakeChain,
                type: EnemyType.drone,
                count: 7)),
        FormationEvent(
            1.5,
            FormationSpec(
                shape: FormationShape.wallWithGap,
                type: EnemyType.mine,
                count: 9,
                gap01: 0.5),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(2.5,
            FormationSpec.stream(EnemyType.turret, count: 2, every: 2.2)),
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
    // L12: the victory-lap gauntlet — every formation, then the finale.
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
            0.8,
            FormationSpec(
                shape: FormationShape.vWedge, type: EnemyType.dart, count: 7),
            countsAsSection: true),
        FormationEvent(
            3.0,
            FormationSpec(
                shape: FormationShape.snakeChain,
                type: EnemyType.wasp,
                count: 7)),
        FormationEvent(
            1.2,
            FormationSpec(
                shape: FormationShape.wallWithGap,
                type: EnemyType.chevron,
                count: 8,
                gap01: 0.45),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(
            2.5,
            FormationSpec(
                shape: FormationShape.pincer,
                type: EnemyType.kamikaze,
                count: 8)),
        FormationEvent(
            1.5,
            FormationSpec(
                shape: FormationShape.ringSpinner,
                type: EnemyType.saucer,
                count: 8),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(
            2.5,
            FormationSpec(
                shape: FormationShape.ambushRear,
                type: EnemyType.chevron,
                count: 6,
                y01: 0.5,
                wipeDrop: PowerUpKind.x2)),
        DropEvent(1.5, PowerUpKind.shield, y01: 0.4),
        SetPieceEvent(1.5,
            duration: 12,
            banner: 'FINAL APPROACH',
            floorScale: 3.2,
            scrollScale: 1.8,
            mineRainPerSecond: 1.0),
        FormationEvent(
            13.0,
            FormationSpec(
                shape: FormationShape.escortConvoy,
                type: EnemyType.beetle,
                secondaryType: EnemyType.gunship,
                count: 6,
                wipeBonus: 500,
                wipeDrop: PowerUpKind.missiles),
            countsAsSection: true),
        FormationEvent(
            2.0,
            FormationSpec(
                shape: FormationShape.columnDive,
                type: EnemyType.drone,
                count: 7)),
        FormationEvent(
            1.5,
            FormationSpec(
                shape: FormationShape.pincer,
                type: EnemyType.wasp,
                count: 8),
            countsAsSection: true,
            waitForFieldClear: true),
        FormationEvent(
            2.0,
            FormationSpec(
                shape: FormationShape.wallWithGap,
                type: EnemyType.mine,
                count: 9,
                gap01: 0.55)),
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
