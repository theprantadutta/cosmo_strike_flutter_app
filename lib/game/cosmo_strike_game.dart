import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/level_run_result.dart';
import '../utils/campaign_catalog.dart';
import '../utils/constants.dart' show GameMode;
import 'components/boss.dart';
import 'components/bullets.dart';
import 'components/enemy.dart';
import 'components/fx.dart';
import 'components/player_ship.dart';
import 'components/power_up.dart';
import 'components/starfield.dart';
import 'components/terrain.dart';
import 'game_assets.dart';
import 'game_audio.dart';
import 'levels/level_catalog.dart';
import 'levels/level_def.dart';
import 'levels/wave_runner.dart';
import 'run_effects.dart';

enum GamePhase {
  ready,
  levelIntro,
  playing,
  paused,
  levelClear,
  reviveOffer,
  gameOver,
}

/// Immutable summary of a finished run, handed to the gameplay screen so it
/// can persist campaign progress + submit the score to the backend.
class GameResult {
  const GameResult({
    required this.score,
    required this.stageReached,
    required this.waveReached,
    required this.enemiesKilled,
    required this.bossesKilled,
    required this.durationSeconds,
    required this.cleared,
    required this.startLevel,
    required this.levelsCleared,
    required this.missilesFired,
    required this.revivesUsed,
    required this.levelResults,
  });

  final int score;

  /// Furthest campaign level reached this run (kept as `stageReached` so
  /// the legacy /scores wire field stays meaningful).
  final int stageReached;
  final int waveReached;
  final int enemiesKilled;
  final int bossesKilled;
  final int durationSeconds;

  /// True only when the FINAL campaign level's boss fell (VICTORY).
  final bool cleared;

  /// Campaign extensions.
  final int startLevel;
  final int levelsCleared;
  final int missilesFired;
  final int revivesUsed;

  /// Per-level outcomes for every level this run touched, in play order
  /// (cleared levels + the level the run ended on).
  final List<LevelRunResult> levelResults;
}

/// One active timed effect for the HUD chip row.
class ActiveEffectHud {
  const ActiveEffectHud({required this.id, required this.remaining01});

  /// 'weapon' | 'x2' | 'speed' | 'slowmo' | 'magnet' | 'ghost'
  final String id;

  /// Remaining duration as a 0..1 fraction of the effect's full length.
  final double remaining01;
}

/// The Space-Impact-style shoot-'em-up: a checkpoint campaign of scripted
/// levels (biomes, terrain, waves, bosses) with game modes layered on top
/// as modifiers. Self-contained Flame world embedded in the gameplay
/// screen only.
class CosmoStrikeGame extends FlameGame with HasCollisionDetection {
  CosmoStrikeGame({
    this.onGameOver,
    this.onLevelCleared,
    this.autoFire = true,
    this.mode = GameMode.classic,
    this.startLevel = 1,
    this.armedLoadoutKey,
  });

  /// Called once when the run ends (out of lives / time / VICTORY). The
  /// screen persists campaign progress + submits the score.
  final void Function(GameResult result)? onGameOver;

  /// Called the moment a level's boss falls, with that level's result —
  /// the screen persists it immediately (crash-safe incremental save).
  final void Function(LevelRunResult result)? onLevelCleared;

  bool autoFire;

  /// The selected game mode — a MODIFIER on top of the campaign level:
  /// lives, pacing, enemy fire, extra spawns, drop rate, one-hit rule,
  /// and the Time Attack clock (see the SHOOTER rules on [GameMode]).
  final GameMode mode;

  /// 1-based campaign level the run begins at (from level select).
  final int startLevel;

  /// PowerUpCubit inventory key armed for this run (already consumed by
  /// the screen); applied when the first level goes live.
  final String? armedLoadoutKey;

  final math.Random rng = math.Random();

  late PlayerShip player;
  late Starfield _starfield;
  final WaveRunner _waveRunner = WaveRunner();

  TerrainStrip? _floor;
  TerrainStrip? _ceiling;
  ObstacleSpawner? _obstacleSpawner;

  // HUD-facing reactive state.
  final ValueNotifier<int> scoreNotifier = ValueNotifier(0);
  final ValueNotifier<int> livesNotifier = ValueNotifier(3);
  final ValueNotifier<double> healthNotifier = ValueNotifier(1.0);
  final ValueNotifier<int> levelNotifier = ValueNotifier(1);
  final ValueNotifier<String> levelNameNotifier = ValueNotifier('');
  final ValueNotifier<int> waveNotifier = ValueNotifier(1);
  final ValueNotifier<GamePhase> phaseNotifier = ValueNotifier(GamePhase.ready);
  // Boss health in [0,1]; -1 means no boss on screen.
  final ValueNotifier<double> bossHealthNotifier = ValueNotifier(-1);
  // Time Attack: seconds remaining; -1 means the mode has no clock.
  final ValueNotifier<int> timeRemainingNotifier = ValueNotifier(-1);
  // Special-weapon ammo for the HUD missile button.
  final ValueNotifier<int> missileAmmoNotifier = ValueNotifier(0);
  // Active timed effects for the HUD chip row (published at ~4 Hz).
  final ValueNotifier<List<ActiveEffectHud>> effectsNotifier =
      ValueNotifier(const []);

  // Run state.
  int levelIndex = 1;
  int wave = 1;
  int enemiesKilled = 0;
  int bossesKilled = 0;
  int missilesFired = 0;
  int levelsClearedCount = 0;
  bool _reviveUsed = false;
  double _elapsed = 0;

  // Per-level tracking for LevelRunResult.
  int _levelStartScore = 0;
  double _levelClock = 0;
  bool _levelTookHit = false;
  final List<LevelRunResult> _levelResults = [];

  // Score multiplier power-up state.
  double scoreMultiplier = 1;
  double _multTimer = 0;
  double _multDuration = 10;

  // Slow-mo power-up state: enemies / enemy bullets / terrain multiply
  // their dt by this.
  double enemyTimeScale = 1;
  double _slowmoTimer = 0;
  double _slowmoDuration = 6;

  // Missiles.
  double _missileCooldown = 0;

  // Effects HUD publish throttle.
  double _effectsAccumulator = 0;

  bool _armedApplied = false;
  bool _runEnded = false;

  GamePhase get phase => phaseNotifier.value;

  LevelDef get level => LevelCatalog.byIndex(levelIndex);
  BiomeDef get biome => BiomeCatalog.byId(level.biomeId);

  /// Top of the open playfield (below the ceiling strip's solid band).
  double get playfieldTop =>
      biome.hasCeiling ? biome.ceilingHeight * 0.65 : 0;

  /// Bottom of the open playfield (above the floor strip's solid band).
  double get playfieldBottom => size.y - biome.floorHeight * 0.65;

  /// Visual floor surface line — ground units / hazards stand here.
  double get floorSurfaceY => size.y - biome.floorHeight * 0.5;

  @override
  Color backgroundColor() => const Color(0xFF05060F);

  @override
  Future<void> onLoad() async {
    // Safety net for direct /game entry (RETRY path skips the loader):
    // the memoized future is an instant cache hit when already warm.
    await GameAssets.preload();

    _starfield = Starfield();
    await add(_starfield);
    player = PlayerShip();
    await add(player);
    await add(_waveRunner);

    // Mode rules: ships per run + start the Time Attack clock when set.
    livesNotifier.value = mode.runLives;
    final limit = mode.timeLimit;
    if (limit != null) timeRemainingNotifier.value = limit.inSeconds;

    levelIndex = startLevel.clamp(1, LevelCatalog.count);
    GameAudio.gameStart();
    _startLevel(levelIndex);
  }

  // ---- Level flow ----

  void _startLevel(int index) {
    levelIndex = index;
    wave = 1;
    levelNotifier.value = index;
    waveNotifier.value = 1;
    levelNameNotifier.value = CampaignCatalog.levelNameFor(index);
    _levelStartScore = scoreNotifier.value;
    _levelClock = 0;
    _levelTookHit = false;

    _setupBiome();

    phaseNotifier.value = GamePhase.levelIntro;
    add(TimerComponent(
      period: 2.2,
      removeOnFinish: true,
      onTick: _beginLevelPlay,
    ));
  }

  /// Swap terrain strips, obstacle spawner, starfield tint for the
  /// active level's biome.
  void _setupBiome() {
    _floor?.removeFromParent();
    _ceiling?.removeFromParent();
    _obstacleSpawner?.removeFromParent();

    final b = biome;
    _floor = TerrainStrip(
      asset: b.floorAsset,
      isCeiling: false,
      bandHeight: b.floorHeight,
    );
    add(_floor!);

    final ceilingAsset = b.ceilingAsset;
    if (ceilingAsset != null) {
      _ceiling = TerrainStrip(
        asset: ceilingAsset,
        isCeiling: true,
        bandHeight: b.ceilingHeight,
      );
      add(_ceiling!);
    } else {
      _ceiling = null;
    }

    _obstacleSpawner = ObstacleSpawner(
      biome: b,
      perTenSeconds: level.obstaclesPerTenSeconds,
    );
    add(_obstacleSpawner!);

    _starfield.setTint(b.starTint);
  }

  void _beginLevelPlay() {
    if (phase != GamePhase.levelIntro) return;
    phaseNotifier.value = GamePhase.playing;

    // Armed store loadout: inject exactly once, when the action starts.
    final key = armedLoadoutKey;
    if (!_armedApplied && key != null) {
      _armedApplied = true;
      ArmedLoadout.apply(this, key);
    }

    _waveRunner.startWave(level, 0);
  }

  /// Called by the WaveRunner when a wave's ships are all spawned + dead.
  void onWaveComplete() {
    if (phase != GamePhase.playing) return;
    if (wave >= level.waves.length) {
      _spawnBoss();
    } else {
      wave++;
      waveNotifier.value = wave;
      _waveRunner.startWave(level, wave - 1);
    }
  }

  void _spawnBoss() {
    GameAudio.bossWarn();
    add(Boss(
      def: level.boss,
      hpScale: 1, // BossDef.baseHp is already per-level data
      spawn: Vector2(size.x + 100, size.y / 2),
    ));
    bossHealthNotifier.value = 1.0;
  }

  void onBossDefeated() {
    bossesKilled++;
    bossHealthNotifier.value = -1;
    addScore((1000 * level.scoreScale).round());
    spawnBossExplosion(Vector2(size.x * 0.78, size.y / 2));
    GameAudio.bossDown();
    GameAudio.levelClear();
    levelsClearedCount++;

    final result = LevelRunResult(
      stageId: levelIndex,
      cleared: true,
      score: scoreNotifier.value - _levelStartScore,
      timeSeconds: _levelClock.round(),
      waveReached: wave,
      noHit: !_levelTookHit,
    );
    _levelResults.add(result);
    onLevelCleared?.call(result);

    if (levelIndex >= LevelCatalog.count) {
      // Final boss down → VICTORY.
      _endRun(cleared: true);
    } else {
      phaseNotifier.value = GamePhase.levelClear;
    }
  }

  /// Begin the next level (called by the screen after the LEVEL CLEAR
  /// overlay — button tap or auto-continue).
  void advanceToNextLevel() {
    if (phase != GamePhase.levelClear) return;
    _startLevel(levelIndex + 1);
  }

  void spawnBossExplosion(Vector2 at) {
    // Three staggered big blasts for weight.
    add(explosionBig(at));
    add(TimerComponent(
      period: 0.18,
      removeOnFinish: true,
      onTick: () => add(explosionBig(at + Vector2(-30, -24))),
    ));
    add(TimerComponent(
      period: 0.36,
      removeOnFinish: true,
      onTick: () => add(explosionBig(at + Vector2(20, 30))),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (phase == GamePhase.playing) {
      _elapsed += dt;
      _levelClock += dt;

      if (_multTimer > 0) {
        _multTimer -= dt;
        if (_multTimer <= 0) scoreMultiplier = 1;
      }
      if (_slowmoTimer > 0) {
        _slowmoTimer -= dt;
        if (_slowmoTimer <= 0) enemyTimeScale = 1;
      }
      if (_missileCooldown > 0) _missileCooldown -= dt;

      // Publish the active-effects chip row at ~4 Hz.
      _effectsAccumulator += dt;
      if (_effectsAccumulator >= 0.25) {
        _effectsAccumulator = 0;
        _publishEffects();
      }

      // Time Attack: the clock spans the whole campaign run.
      final limit = mode.timeLimit;
      if (limit != null) {
        final remaining = limit.inSeconds - _elapsed.floor();
        if (remaining != timeRemainingNotifier.value) {
          timeRemainingNotifier.value = remaining.clamp(0, limit.inSeconds);
        }
        if (remaining <= 0) {
          // Time-out is final — no revive offer.
          _endRun(cleared: false);
        }
      }
    }
  }

  void _publishEffects() {
    final effects = <ActiveEffectHud>[
      if (player.weapon != WeaponMode.single)
        ActiveEffectHud(
            id: 'weapon',
            remaining01: (player.weaponTimeLeft / 10).clamp(0, 1).toDouble()),
      if (scoreMultiplier > 1)
        ActiveEffectHud(
            id: 'x2',
            remaining01: (_multTimer / _multDuration).clamp(0, 1).toDouble()),
      if (player.speedBoosted)
        ActiveEffectHud(
            id: 'speed',
            remaining01: (player.speedTimeLeft / 15).clamp(0, 1).toDouble()),
      if (enemyTimeScale < 1)
        ActiveEffectHud(
            id: 'slowmo',
            remaining01:
                (_slowmoTimer / _slowmoDuration).clamp(0, 1).toDouble()),
      if (player.magnetActive)
        ActiveEffectHud(
            id: 'magnet',
            remaining01: (player.magnetTimeLeft / 60).clamp(0, 1).toDouble()),
      if (player.ghosted)
        ActiveEffectHud(
            id: 'ghost',
            remaining01: (player.ghostTimeLeft / 12).clamp(0, 1).toDouble()),
    ];
    effectsNotifier.value = effects;
  }

  // ---- Input from the gameplay screen ----

  /// Move the ship toward [target] (screen coordinates). The ship clamps
  /// itself to the left portion of the screen.
  void steerTo(Vector2 target) {
    if (phase == GamePhase.playing) {
      player.steerTo(target);
    }
  }

  /// D-pad analog direction (normalized; zero = released).
  void setMoveDirection(Vector2 dir) {
    if (phase == GamePhase.playing || dir.isZero()) {
      player.setMoveDirection(dir);
    }
  }

  void setAutoFire(bool value) => autoFire = value;

  /// Manual fire (tap/hold option when auto-fire is off).
  void firePrimary() {
    if (phase == GamePhase.playing) player.fire();
  }

  /// Fire the special weapon (HUD button / double tap). Ammo persists
  /// across levels within the run.
  void fireMissile() {
    if (phase != GamePhase.playing) return;
    if (missileAmmoNotifier.value <= 0 || _missileCooldown > 0) return;
    missileAmmoNotifier.value -= 1;
    missilesFired++;
    _missileCooldown = 0.6;
    add(PlayerMissile(spawn: player.nose + Vector2(8, 0)));
    GameAudio.missile();
  }

  // ---- Scoring / lives / damage ----

  void addScore(int points) {
    scoreNotifier.value += (points * scoreMultiplier).round();
  }

  void setScoreMultiplier(double mult, double seconds) {
    scoreMultiplier = mult;
    _multTimer = seconds;
    _multDuration = seconds;
  }

  void applySlowmo(double seconds) {
    enemyTimeScale = 0.5;
    _slowmoTimer = seconds;
    _slowmoDuration = seconds;
  }

  void onEnemyKilled(EnemyShip enemy) {
    enemiesKilled++;
    addScore(enemy.pointValue);
    spawnExplosion(enemy.position, CosmoExplosionKind.enemy);
    // Power-up drop — 12% normally, cranked way up in Power-Up Madness.
    if (rng.nextDouble() < mode.powerUpDropChance) {
      add(PowerUp(kind: PowerUpKind.random(rng), spawn: enemy.position.clone()));
    }
  }

  void spawnExplosion(Vector2 at, CosmoExplosionKind kind) {
    switch (kind) {
      case CosmoExplosionKind.enemy:
        add(explosionSmall(at));
        break;
      case CosmoExplosionKind.player:
        add(explosionBig(at));
        break;
      case CosmoExplosionKind.boss:
        spawnBossExplosion(at);
        break;
    }
  }

  /// Player took a hit (bullet / contact damage in health units).
  void onPlayerHit(double damage) {
    if (phase != GamePhase.playing) return;
    if (player.isInvulnerable || player.ghosted) return;
    if (player.shielded) {
      player.popShield();
      return;
    }
    // Armed teleport: negate the hit by warping home.
    if (player.consumeTeleportCharge()) return;

    _levelTookHit = true;
    GameAudio.playerHit();

    // Perfect Game: flawless flying only — any hit that lands ends the
    // run, regardless of remaining health or lives. (A shield pop still
    // saves you; it's a power-up doing its job.)
    if (mode.oneHitRun) {
      player.health = 0;
      healthNotifier.value = 0;
      _loseLife();
      return;
    }
    player.health -= damage;
    if (player.health <= 0 && player.consumeScoreShieldCharge()) {
      // Armed score shield: absorb the lethal hit instead of dying.
      player.health = 0.5;
    }
    healthNotifier.value = player.health.clamp(0, 1).toDouble();
    if (player.health <= 0) {
      _loseLife();
    }
  }

  /// Player clipped a terrain band or obstacle. Fixed damage through the
  /// normal hit path (shield pops first; Perfect Game still one-hits),
  /// then a positional bounce + 1 s anti-grind invulnerability so terrain
  /// can never grind out a life faster than one hit per second.
  void onTerrainCrash(PositionComponent surface) {
    if (phase != GamePhase.playing) return;
    if (player.isInvulnerable) return;

    add(hitSpark(player.position));
    onPlayerHit(0.34);
    if (phase != GamePhase.playing) return; // the hit ended the run

    // Bounce away from the surface.
    final Vector2 push;
    if (surface is TerrainStrip) {
      push = Vector2(0, surface.isCeiling ? 28 : -28);
    } else {
      final delta = player.position - surface.position;
      push = (delta.isZero() ? Vector2(-1, 0) : delta.normalized()) * 28;
    }
    player.bounce(push);
    player.grantInvuln(1.0);
  }

  void _loseLife() {
    spawnExplosion(player.position, CosmoExplosionKind.player);
    final lives = livesNotifier.value - 1;
    livesNotifier.value = lives;
    if (lives <= 0) {
      // One revive per run — except Perfect Game, where a continue would
      // contradict the mode's whole premise.
      if (!_reviveUsed && !mode.oneHitRun) {
        phaseNotifier.value = GamePhase.reviveOffer;
        pauseEngine();
      } else {
        _endRun(cleared: false);
      }
    } else {
      player.health = 1.0;
      healthNotifier.value = 1.0;
      player.respawn();
    }
  }

  // ---- Revive ----

  /// Resume the SAME level + wave after the player paid for a continue
  /// (rewarded ad / coins). The WaveRunner is game-time, so the paused
  /// spawn timeline resumes exactly where it froze.
  void revive() {
    if (phase != GamePhase.reviveOffer) return;
    _reviveUsed = true;
    livesNotifier.value = 1;
    player.health = 1.0;
    healthNotifier.value = 1.0;
    // Clear the immediate threats so the comeback isn't instant death.
    for (final b in children.whereType<EnemyBullet>().toList()) {
      b.removeFromParent();
    }
    player.respawn(withWarpFx: true);
    GameAudio.revive();
    phaseNotifier.value = GamePhase.playing;
    resumeEngine();
  }

  /// Player declined the continue offer → the run is over.
  void declineRevive() {
    if (phase != GamePhase.reviveOffer) return;
    resumeEngine();
    _endRun(cleared: false);
  }

  void applyPowerUp(PowerUpKind kind) {
    player.applyPowerUp(kind);
    addScore(50);
    GameAudio.pickup();
    switch (kind) {
      case PowerUpKind.life:
        livesNotifier.value += 1;
        break;
      case PowerUpKind.bomb:
        _screenClearBomb();
        break;
      case PowerUpKind.x2:
        setScoreMultiplier(2, 10);
        break;
      case PowerUpKind.missiles:
        missileAmmoNotifier.value += 3;
        break;
      case PowerUpKind.slowmo:
        applySlowmo(6);
        break;
      default:
        // weapon/shield/speed/magnet/ghost handled inside PlayerShip.
        break;
    }
  }

  void _screenClearBomb() {
    for (final e in children.whereType<EnemyShip>().toList()) {
      spawnExplosion(e.position, CosmoExplosionKind.enemy);
      addScore(e.pointValue ~/ 2);
      enemiesKilled++;
      e.removeFromParent();
    }
    for (final b in children.whereType<EnemyBullet>().toList()) {
      b.removeFromParent();
    }
    // Chunk the boss too, if one is on screen.
    for (final boss in children.whereType<Boss>().toList()) {
      boss.takeDamage(8);
    }
  }

  // ---- Pause / resume / end ----

  void pauseGame() {
    if (phase == GamePhase.playing) {
      phaseNotifier.value = GamePhase.paused;
      pauseEngine();
    }
  }

  void resumeGame() {
    if (phase == GamePhase.paused) {
      phaseNotifier.value = GamePhase.playing;
      resumeEngine();
    }
  }

  /// Snapshot of the run *as it stands* — used by the quit-from-pause
  /// path so an abandoned run still persists its campaign progress.
  GameResult buildPartialResult() => _buildResult(cleared: false);

  GameResult _buildResult({required bool cleared}) {
    // Include the in-progress level (not cleared) so its bestWaveReached
    // merges into stage progress. Cleared levels were appended on the
    // spot in onBossDefeated.
    final results = List<LevelRunResult>.of(_levelResults);
    final lastClearedHere = results.isNotEmpty &&
        results.last.stageId == levelIndex &&
        results.last.cleared;
    if (!lastClearedHere) {
      results.add(LevelRunResult(
        stageId: levelIndex,
        cleared: false,
        score: scoreNotifier.value - _levelStartScore,
        timeSeconds: _levelClock.round(),
        waveReached: wave,
        noHit: false,
      ));
    }
    return GameResult(
      score: scoreNotifier.value,
      stageReached: levelIndex,
      waveReached: wave,
      enemiesKilled: enemiesKilled,
      bossesKilled: bossesKilled,
      durationSeconds: _elapsed.round(),
      cleared: cleared,
      startLevel: startLevel,
      levelsCleared: levelsClearedCount,
      missilesFired: missilesFired,
      revivesUsed: _reviveUsed ? 1 : 0,
      levelResults: results,
    );
  }

  void _endRun({required bool cleared}) {
    if (_runEnded) return;
    _runEnded = true;
    _waveRunner.stop();
    phaseNotifier.value = GamePhase.gameOver;
    GameAudio.gameOver();
    onGameOver?.call(_buildResult(cleared: cleared));
  }
}
