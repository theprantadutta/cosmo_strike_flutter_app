import 'package:flame/flame.dart';

/// Central registry of every gameplay sprite under `assets/game/`.
///
/// All paths are relative to [prefix]; [preload] points the global
/// [Flame.images] cache at that prefix and bulk-loads everything, so
/// components can synchronously `Flame.images.fromCache(GameAssets.x)`
/// inside `onLoad`. Called fire-and-forget from the pre-game loading
/// screen and awaited again (idempotent — same memoized future) from
/// `CosmoStrikeGame.onLoad` as the safety net for direct entry.
abstract final class GameAssets {
  static const String prefix = 'assets/game/';

  // ---- player ----
  static const String playerShip = 'player/player_ship.png'; // 192x128
  static const String playerShipUp = 'player/player_ship_up.png'; // 192x128
  static const String playerShipDown =
      'player/player_ship_down.png'; // 192x128
  /// 3 frames @ 64x64, horizontal strip.
  static const String playerExhaustSheet = 'player/player_exhaust_sheet.png';

  // ---- enemies ----
  static const String enemyDart = 'enemies/enemy_dart.png'; // 128x128
  static const String enemyWasp = 'enemies/enemy_wasp.png'; // 128x128
  static const String enemyDrone = 'enemies/enemy_drone.png'; // 128x128
  /// 4 frames @ 128x128, horizontal strip (rotation loop).
  static const String enemyMineSheet = 'enemies/enemy_mine_sheet.png';
  static const String enemyBeetle = 'enemies/enemy_beetle.png'; // 160x160
  static const String enemyChevron = 'enemies/enemy_chevron.png'; // 96x96
  static const String enemyKamikaze = 'enemies/enemy_kamikaze.png'; // 128x128
  static const String enemyGunship = 'enemies/enemy_gunship.png'; // 160x160
  static const String enemyCrawler = 'enemies/enemy_crawler.png'; // 160x128
  static const String enemySaucer = 'enemies/enemy_saucer.png'; // 144x144

  // ---- bosses (512x384) ----
  static const String bossDreadnought = 'bosses/boss_dreadnought.png';
  static const String bossHiveQueen = 'bosses/boss_hive_queen.png';
  static const String bossWarMachine = 'bosses/boss_war_machine.png';
  static const String bossLeviathan = 'bosses/boss_leviathan.png';
  static const String bossMothership = 'bosses/boss_mothership.png';

  // ---- projectiles ----
  static const String bulletPlayer = 'projectiles/bullet_player.png'; // 64x24
  static const String bulletPlayerHeavy =
      'projectiles/bullet_player_heavy.png'; // 80x32
  static const String missilePlayer =
      'projectiles/missile_player.png'; // 96x40
  static const String beamSegment = 'projectiles/beam_segment.png'; // 128x32
  static const String bulletEnemy = 'projectiles/bullet_enemy.png'; // 48x48
  static const String bulletBoss = 'projectiles/bullet_boss.png'; // 64x64

  // ---- power-up orbs (96x96) ----
  static const String powerupShield = 'powerups/powerup_shield.png';
  static const String powerupLife = 'powerups/powerup_life.png';
  static const String powerupBomb = 'powerups/powerup_bomb.png';
  static const String powerupX2 = 'powerups/powerup_x2.png';
  static const String powerupWeapon = 'powerups/powerup_weapon.png';
  static const String powerupSpeed = 'powerups/powerup_speed.png';
  static const String powerupSlowmo = 'powerups/powerup_slowmo.png';
  static const String powerupMagnet = 'powerups/powerup_magnet.png';
  static const String powerupGhost = 'powerups/powerup_ghost.png';
  static const String powerupMissiles = 'powerups/powerup_missiles.png';

  // ---- fx (horizontal strips unless noted) ----
  /// 6 frames @ 96x96.
  static const String explosionSmallSheet = 'fx/explosion_small_sheet.png';

  /// 8 frames @ 160x160.
  static const String explosionBigSheet = 'fx/explosion_big_sheet.png';

  /// 4 frames @ 64x64.
  static const String hitSparkSheet = 'fx/hit_spark_sheet.png';

  /// 3 frames @ 48x48.
  static const String muzzleFlashSheet = 'fx/muzzle_flash_sheet.png';

  /// Single image, 192x160.
  static const String shieldBubble = 'fx/shield_bubble.png';

  /// 5 frames @ 128x128.
  static const String warpFlashSheet = 'fx/warp_flash_sheet.png';

  // ---- terrain (strips 1024x192, tileable horizontally) ----
  static const String terrainAsteroidFloor =
      'terrain/terrain_asteroid_floor.png';
  static const String terrainAsteroidCeiling =
      'terrain/terrain_asteroid_ceiling.png';
  static const String terrainCityFloor = 'terrain/terrain_city_floor.png';
  static const String terrainHiveFloor = 'terrain/terrain_hive_floor.png';
  static const String terrainHiveCeiling = 'terrain/terrain_hive_ceiling.png';
  static const String terrainCrystalFloor =
      'terrain/terrain_crystal_floor.png';
  static const String obstacleAsteroidBig =
      'terrain/obstacle_asteroid_big.png'; // 256x256
  static const String obstacleAsteroidSmall =
      'terrain/obstacle_asteroid_small.png'; // 128x128
  static const String obstacleSpikePlant =
      'terrain/obstacle_spike_plant.png'; // 160x224
  static const String obstacleCrystal =
      'terrain/obstacle_crystal.png'; // 160x224

  static const List<String> all = [
    playerShip,
    playerShipUp,
    playerShipDown,
    playerExhaustSheet,
    enemyDart,
    enemyWasp,
    enemyDrone,
    enemyMineSheet,
    enemyBeetle,
    enemyChevron,
    enemyKamikaze,
    enemyGunship,
    enemyCrawler,
    enemySaucer,
    bossDreadnought,
    bossHiveQueen,
    bossWarMachine,
    bossLeviathan,
    bossMothership,
    bulletPlayer,
    bulletPlayerHeavy,
    missilePlayer,
    beamSegment,
    bulletEnemy,
    bulletBoss,
    powerupShield,
    powerupLife,
    powerupBomb,
    powerupX2,
    powerupWeapon,
    powerupSpeed,
    powerupSlowmo,
    powerupMagnet,
    powerupGhost,
    powerupMissiles,
    explosionSmallSheet,
    explosionBigSheet,
    hitSparkSheet,
    muzzleFlashSheet,
    shieldBubble,
    warpFlashSheet,
    terrainAsteroidFloor,
    terrainAsteroidCeiling,
    terrainCityFloor,
    terrainHiveFloor,
    terrainHiveCeiling,
    terrainCrystalFloor,
    obstacleAsteroidBig,
    obstacleAsteroidSmall,
    obstacleSpikePlant,
    obstacleCrystal,
  ];

  static Future<void>? _preloadFuture;

  /// Bulk-decode every gameplay sprite into the global [Flame.images]
  /// cache. Memoized — concurrent / repeated calls share one future.
  /// Total decoded size ≈ 14 MB RGBA, fine to keep resident for the
  /// whole session.
  static Future<void> preload() {
    return _preloadFuture ??= () async {
      Flame.images.prefix = prefix;
      await Flame.images.loadAll(all);
    }();
  }
}
