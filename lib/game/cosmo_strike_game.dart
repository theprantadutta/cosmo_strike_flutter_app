import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/level_run_result.dart';
import '../models/premium_cosmetics.dart' show TrailEffectType;
import '../services/haptic_service.dart';
import '../utils/campaign_catalog.dart';
import '../utils/constants.dart' show GameMode;
import 'combo_graze.dart';
import 'components/boss.dart';
import 'components/bosses/boss_pod.dart';
import 'components/bullets.dart';
import 'components/enemy.dart';
import 'components/fx.dart';
import 'components/player_ship.dart';
import 'components/power_up.dart';
import 'components/ship_trail.dart';
import 'components/starfield.dart';
import 'components/terrain.dart';
import 'game_assets.dart';
import 'game_audio.dart';
import 'levels/level_catalog.dart';
import 'levels/level_def.dart';
import 'levels/script_runner.dart';
import 'pools.dart';
import 'run_effects.dart';
import 'tutorial_director.dart';

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
    this.maxCombo = 0,
    this.grazeCount = 0,
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

  /// Longest kill chain of the run.
  final int maxCombo;

  /// Total bullet grazes of the run.
  final int grazeCount;
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
    this.screenShake = false,
    this.tutorial = false,
    this.dPadControls = false,
    this.onTutorialOutcome,
    this.selectedSkinId = 'classic',
    this.selectedTrailId = 'none',
    this.trailEffectsEnabled = false,
  }) : _tutorialPending = tutorial;

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

  /// Settings toggle: jolt the view on hits / deaths / boss kills.
  final bool screenShake;

  /// First-run interactive tutorial: when true the guided beats run
  /// BEFORE Level 1's script (see [TutorialDirector]); the real level
  /// choreography starts only when the tutorial certifies or is skipped.
  final bool tutorial;

  /// Whether the player chose D-pad controls — the tutorial's steer
  /// prompt demos whichever input they actually have.
  final bool dPadControls;

  /// Fired once when the tutorial resolves: `true` = all beats done
  /// (PILOT CERTIFIED — the screen awards the completion bonus),
  /// `false` = skipped. Never fired when [tutorial] is false.
  final void Function(bool completed)? onTutorialOutcome;

  /// Equipped cosmetic skin id ([ShipSkinType.id]); 'classic' = the
  /// stock, untinted render.
  final String selectedSkinId;

  /// Equipped trail id ([TrailEffectType.id]); 'none' = no trail.
  final String selectedTrailId;

  /// Master gate for the cosmetic trail stream (the 'Engine Trail
  /// Effects' setting, ThemeCubit.trailSystemEnabled).
  final bool trailEffectsEnabled;

  final math.Random rng = math.Random();

  late PlayerShip player;
  late Starfield _starfield;
  late final GamePools pools = GamePools(this);
  final ComboGrazeController combo = ComboGrazeController();
  final ScriptRunner _scriptRunner = ScriptRunner();

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

  /// Total enemies destroyed this run, published for the HUD kill tally.
  final ValueNotifier<int> killsNotifier = ValueNotifier(0);
  // Active timed effects for the HUD chip row (published at ~4 Hz).
  final ValueNotifier<List<ActiveEffectHud>> effectsNotifier =
      ValueNotifier(const []);
  // Set-piece banner callout ("CANYON RUN!"); null = hidden.
  final ValueNotifier<String?> calloutNotifier = ValueNotifier(null);
  // Bumped on every LANDED hit — the HUD flashes a red edge vignette.
  final ValueNotifier<int> hitPulseNotifier = ValueNotifier(0);
  // Active first-run tutorial prompt; null = no banner. Only ever set
  // while [tutorial] is running.
  final ValueNotifier<TutorialPrompt?> tutorialNotifier = ValueNotifier(null);

  // Run state.
  int levelIndex = 1;
  int wave = 1;
  int enemiesKilled = 0;
  int bossesKilled = 0;
  int missilesFired = 0;
  // Lifetime power-ups collected this run — a monotonic baseline the
  // tutorial reads to detect a pickup (mirrors enemiesKilled/missilesFired).
  int powerUpsCollected = 0;
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

  // Screen shake (settings-gated): decaying random canvas jitter.
  double _shakeTime = 0;
  double _shakeDuration = 0;
  double _shakeIntensity = 0;
  final Vector2 _shakeOffset = Vector2.zero();

  // Hit-stop: a micro freeze (sim time crawls at 5%) that gives heavy
  // kills / boss beats physical weight. Ticked down with REAL dt.
  double _hitStopTime = 0;
  static const double _hitStopScale = 0.05;

  bool _armedApplied = false;
  bool _runEnded = false;

  // Tutorial run state: pending until certified/skipped; the director
  // is kept so the HUD skip button can reach it.
  bool _tutorialPending;
  TutorialDirector? _tutorialDirector;

  GamePhase get phase => phaseNotifier.value;

  LevelDef get level => LevelCatalog.byIndex(levelIndex);
  BiomeDef get biome => BiomeCatalog.byId(level.biomeId);

  /// Seconds of PLAYING time into the active level (drives the terrain
  /// profile and the level script timeline).
  double get levelClock => _levelClock;

  /// Top of the open playfield (below the ceiling strip's solid band).
  /// Reads the LIVE animated strip, so tunnel squeezes move every
  /// consumer (spawn bands, boss clamps, obstacle spawner) with them.
  double get playfieldTop =>
      _ceiling?.solidEdgeY ?? (biome.hasCeiling ? biome.ceilingHeight * 0.65 : 0);

  /// Bottom of the open playfield (above the floor strip's solid band).
  double get playfieldBottom =>
      _floor?.solidEdgeY ?? (size.y - biome.floorHeight * 0.65);

  /// Visual floor surface line — ground units / hazards stand here.
  double get floorSurfaceY =>
      _floor?.surfaceY ?? (size.y - biome.floorHeight * 0.5);

  /// Visual ceiling surface line — ceiling-mounted turrets hang here.
  double get ceilingSurfaceY => _ceiling?.surfaceY ?? playfieldTop;

  /// Live terrain scroll speed (canyon set-pieces crank the profile).
  double get terrainScrollSpeed => _floor?.currentScrollSpeed ?? 140;

  /// The profile's current scroll multiplier (drifting obstacles ride it).
  double get terrainScrollScale => terrainScrollSpeed / 140;

  /// Script-driven set-piece corridor state (multiplies the biome's base
  /// band heights / scroll for the window — see SetPieceEvent).
  double setPieceFloorScale = 1;
  double setPieceCeilScale = 1;
  double setPieceScrollScale = 1;

  void beginSetPieceTerrain(
      {double floor = 1, double ceil = 1, double scroll = 1}) {
    setPieceFloorScale = floor;
    setPieceCeilScale = ceil;
    setPieceScrollScale = scroll;
  }

  void endSetPieceTerrain() {
    setPieceFloorScale = 1;
    setPieceCeilScale = 1;
    setPieceScrollScale = 1;
  }

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
    // Cosmetic trail stream — only when the equipped trail exists AND
    // the 'Engine Trail Effects' setting allows it.
    if (trailEffectsEnabled && selectedTrailId != 'none') {
      final trailType = TrailEffectType.values
          .where((t) => t.id == selectedTrailId)
          .firstOrNull;
      if (trailType != null && trailType != TrailEffectType.none) {
        await add(ShipTrail(trailType));
      }
    }
    await add(BoundaryGlow());
    await add(_scriptRunner);
    await pools.mount();

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
      tallAsset: b.floorAssetTall,
      isCeiling: false,
      bandHeight: b.floorHeight,
      profile: level.terrainProfile,
    );
    add(_floor!);

    final ceilingAsset = b.ceilingAsset;
    if (ceilingAsset != null) {
      _ceiling = TerrainStrip(
        asset: ceilingAsset,
        tallAsset: b.ceilingAssetTall,
        isCeiling: true,
        bandHeight: b.ceilingHeight,
        profile: level.terrainProfile,
      );
      add(_ceiling!);
    } else {
      _ceiling = null;
    }

    _obstacleSpawner = ObstacleSpawner(
      biome: b,
      perTenSeconds: level.obstaclesPerTenSeconds,
    );
    // During the first-run tutorial the sky belongs to the guided beats —
    // the spawner mounts when the tutorial hands off (endTutorial).
    if (!_tutorialPending) add(_obstacleSpawner!);

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

    // First run: the tutorial owns the field; the level script starts
    // from endTutorial() once the player is certified (or skips).
    if (_tutorialPending) {
      _tutorialDirector = TutorialDirector();
      add(_tutorialDirector!);
      return;
    }

    _scriptRunner.startLevel(level.script);
  }

  /// HUD skip button (visible from the tutorial's second beat).
  void skipTutorial() => _tutorialDirector?.skip();

  /// Tutorial handoff: called by the [TutorialDirector] after the player
  /// is certified (or skips). Mounts the held obstacle spawner, resets
  /// the level clock so the terrain profile and timings play level 1 as
  /// designed, and starts the real script.
  void endTutorial() {
    if (!_tutorialPending) return;
    _tutorialPending = false;
    _tutorialDirector = null;
    tutorialNotifier.value = null;
    final spawner = _obstacleSpawner;
    if (spawner != null && spawner.parent == null) add(spawner);
    _levelClock = 0;
    if (phase == GamePhase.playing) {
      _scriptRunner.startLevel(level.script);
    }
  }

  /// Called by the ScriptRunner when a section-opening formation fires —
  /// keeps the HUD wave counter (and LevelRunResult.waveReached) meaningful.
  void onScriptSection(int section) {
    wave = section;
    waveNotifier.value = section;
  }

  /// Show a set-piece banner callout on the HUD.
  void showCallout(String text) => calloutNotifier.value = text;

  void clearCallout() => calloutNotifier.value = null;

  /// Called by the ScriptRunner's BossEvent (field already clear).
  void spawnBoss() {
    GameAudio.bossWarn();
    add(Boss(
      def: level.boss,
      // BossDef.baseHp is per-level, but it grows far slower than the enemy
      // hpScale curve — so late bosses used to melt before their kit played
      // out. Track the difficulty curve at HALF rate so later fights last
      // long enough to reach phase 3 without dragging.
      hpScale: 1 + (level.hpScale - 1) * 0.5,
      spawn: Vector2(size.x + 100, size.y / 2),
    ));
    bossHealthNotifier.value = 1.0;
  }

  void onBossDefeated() {
    bossesKilled++;
    bossHealthNotifier.value = -1;
    combo.onKill();
    final awarded = addKillScore((1000 * level.scoreScale).round());
    final bossAt = Vector2(size.x * 0.78, size.y / 2);
    pools.scorePopup(bossAt + Vector2(0, -60), '+$awarded', scale: 1.4);
    hitStop(0.1);
    spawnBossExplosion(bossAt);
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
    shake(intensity: 12, duration: 0.6);
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

  /// Kick a decaying view jolt (no-op unless the setting is on).
  void shake({double intensity = 6, double duration = 0.25}) {
    if (!screenShake) return;
    _shakeIntensity = math.max(_shakeIntensity, intensity);
    _shakeDuration = math.max(_shakeDuration, duration);
    _shakeTime = _shakeDuration;
  }

  /// Freeze the sim for [seconds] of real time (heavy kills, boss beats).
  void hitStop(double seconds) {
    _hitStopTime = math.max(_hitStopTime, seconds);
  }

  @override
  void render(Canvas canvas) {
    // Whole-scene jitter: children are added directly to the game (no
    // camera/world indirection), so the shake is a canvas translate.
    if (_shakeOffset.x != 0 || _shakeOffset.y != 0) {
      canvas.save();
      canvas.translate(_shakeOffset.x, _shakeOffset.y);
      super.render(canvas);
      canvas.restore();
    } else {
      super.render(canvas);
    }
  }

  @override
  void update(double dt) {
    // Hit-stop: the whole sim crawls while the freeze lasts; the freeze
    // itself, the shake, and the run clocks tick on REAL time so Time
    // Attack stays honest.
    final realDt = dt;
    var simDt = dt;
    if (_hitStopTime > 0) {
      _hitStopTime -= realDt;
      simDt = realDt * _hitStopScale;
    }
    super.update(simDt);
    if (_shakeTime > 0) {
      _shakeTime -= realDt;
      if (_shakeTime <= 0) {
        _shakeOffset.setZero();
        _shakeIntensity = 0;
        _shakeDuration = 0;
      } else {
        final falloff = _shakeTime / _shakeDuration;
        _shakeOffset.setValues(
          (rng.nextDouble() * 2 - 1) * _shakeIntensity * falloff,
          (rng.nextDouble() * 2 - 1) * _shakeIntensity * falloff,
        );
      }
    }
    if (phase == GamePhase.playing) {
      _elapsed += realDt;
      _levelClock += realDt;

      // Gameplay-effect timers follow sim time (frozen world = frozen
      // effects).
      final dt = simDt;
      if (_multTimer > 0) {
        _multTimer -= dt;
        if (_multTimer <= 0) scoreMultiplier = 1;
      }
      if (_slowmoTimer > 0) {
        _slowmoTimer -= dt;
        if (_slowmoTimer <= 0) enemyTimeScale = 1;
      }
      if (_missileCooldown > 0) _missileCooldown -= dt;
      combo.update(dt);

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
      // Post-revive protection — first so the grace window is the most
      // prominent chip while it's counting down.
      if (player.protected)
        ActiveEffectHud(
            id: 'shield',
            remaining01: (player.protectTimeLeft / _reviveProtectSeconds)
                .clamp(0, 1)
                .toDouble()),
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

  /// Relative-drag steering: shift the steer destination by [delta] —
  /// the ship mirrors finger movement so the thumb never covers it.
  void steerBy(Vector2 delta) {
    if (phase == GamePhase.playing) {
      player.nudgeTarget(delta);
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

  /// Adds [points] (scaled by the x2 orb) and returns what was actually
  /// awarded, so callers can show the real number in a popup.
  int addScore(int points) {
    final awarded = (points * scoreMultiplier).round();
    scoreNotifier.value += awarded;
    return awarded;
  }

  /// Kill-path scoring: the combo multiplier applies on top of the x2
  /// orb. Use for enemy/boss kills and formation bonuses — never for
  /// pickups or grazes.
  int addKillScore(int basePoints) => addScore(basePoints * combo.multiplier);

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
    killsNotifier.value = enemiesKilled;
    enemy.formation?.onMemberKilled(enemy);
    final tierUp = combo.onKill();
    final awarded = addKillScore(enemy.pointValue);
    pools.scorePopup(enemy.position + Vector2(0, -16), '+$awarded');
    if (tierUp) {
      pools.scorePopup(
        enemy.position + Vector2(0, -42),
        '×${combo.multiplier} CHAIN',
        color: const Color(0xFFFF7BD5),
        scale: 1.3,
        duration: 0.9,
      );
      add(oneShotFx(
          GameAssets.comboBurstSheet, 4, enemy.position, Vector2.all(54),
          fps: 18));
      GameAudio.comboUp();
    }
    // Heavy kills (tanky hulls) land with a micro hit-stop + bigger blast.
    final heavy = enemy.type.baseHp >= 4;
    if (heavy) hitStop(0.045);
    spawnExplosion(
      enemy.position,
      CosmoExplosionKind.enemy,
      scale: heavy ? 1.5 : (enemy.size.x / 40).clamp(0.9, 1.3).toDouble(),
    );
    // Power-up drop — 12% normally, cranked way up in Power-Up Madness.
    if (rng.nextDouble() < mode.powerUpDropChance) {
      add(PowerUp(kind: PowerUpKind.random(rng), spawn: enemy.position.clone()));
    }
  }

  void spawnExplosion(Vector2 at, CosmoExplosionKind kind, {double scale = 1}) {
    switch (kind) {
      case CosmoExplosionKind.enemy:
        add(explosionSmall(at, scale: scale));
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
      // The save must still READ as an impact, or it feels like a bug.
      pools.scorePopup(
        player.position + Vector2(0, -30),
        'SHIELD DOWN',
        color: const Color(0xFF7DE8FF),
        duration: 0.8,
      );
      GameAudio.playerHit();
      unawaited(HapticService().lightImpact());
      return;
    }
    // Armed teleport: negate the hit by warping home.
    if (player.consumeTeleportCharge()) return;

    _levelTookHit = true;
    // A landed hit breaks the kill chain (shield pops / ghost passes
    // returned above — power-ups doing their job don't).
    if (combo.chain >= 5) {
      pools.scorePopup(
        player.position + Vector2(0, -30),
        'COMBO BREAK',
        color: const Color(0xFFFF8A8A),
        scale: 1.15,
        duration: 0.8,
      );
      GameAudio.comboBreak();
    }
    combo.onPlayerDamaged();
    GameAudio.playerHit();
    shake(intensity: 5, duration: 0.22);
    // Layered hit feedback that does NOT depend on the shake setting:
    // red hull flash + HUD vignette pulse + haptic thud.
    player.flashDamage();
    hitPulseNotifier.value++;
    unawaited(HapticService().mediumImpact());

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
    } else {
      // Mercy invulnerability: one hit is one hit — a second bullet a
      // frame later can't silently melt the rest of the bar.
      player.grantInvuln(0.6);
    }
  }

  /// An enemy bullet slipped past the hull without connecting. Risk pays:
  /// points + graze-meter charge; a full meter converts to +1 missile.
  void onGraze(Vector2 at) {
    if (phase != GamePhase.playing) return;
    addScore(15);
    pools.hitSpark(at);
    GameAudio.graze();
    if (combo.onGraze()) {
      missileAmmoNotifier.value += 1;
      pools.scorePopup(
        player.position + Vector2(0, -30),
        'MISSILE +1',
        color: const Color(0xFFFFD37B),
        scale: 1.2,
        duration: 0.9,
      );
      GameAudio.meterFull();
    }
  }

  /// Player clipped a terrain band or obstacle. Fixed damage through the
  /// normal hit path (shield pops first; Perfect Game still one-hits),
  /// then a positional bounce + 1 s anti-grind invulnerability so terrain
  /// can never grind out a life faster than one hit per second.
  void onTerrainCrash(PositionComponent surface) {
    if (phase != GamePhase.playing) return;
    if (player.isInvulnerable) return;

    pools.hitSpark(player.position);
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
    shake(intensity: 10, duration: 0.4);
    // Losing a ship is the heaviest beat outside a boss kill — freeze,
    // thud, and let the lives panel play its SHIP DOWN sequence.
    hitStop(0.08);
    unawaited(HapticService().heavyImpact());
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

  /// Seconds of protective shield granted on revive — the comeback can't die
  /// for this long, and the shield bubble + HUD chip make the grace window
  /// obvious. Longer than the default respawn invuln (3.0s) since the player
  /// just paid to continue.
  static const double _reviveProtectSeconds = 4.5;

  /// Resume the SAME level + wave after the player paid for a continue
  /// (rewarded ad / coins). The ScriptRunner is game-time, so the paused
  /// spawn timeline resumes exactly where it froze.
  void revive() {
    if (phase != GamePhase.reviveOffer) return;
    _reviveUsed = true;
    livesNotifier.value = 1;
    player.health = 1.0;
    healthNotifier.value = 1.0;
    // Clear the immediate threats so the comeback isn't instant death,
    // and hold the spawn timeline briefly so the choreography doesn't
    // dogpile the comeback.
    pools.clearEnemyBullets();
    _scriptRunner.notifyRevived();
    player.respawn(withWarpFx: true);
    // Visible, timed protection so the player can't be cheap-shotted the
    // instant they're back — a shield bubble + HUD countdown chip.
    player.grantProtection(_reviveProtectSeconds);
    _publishEffects();
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
    powerUpsCollected++;
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
    killsNotifier.value = enemiesKilled;
    pools.clearEnemyBullets();
    // Chunk the boss (and its pods) too, if one is on screen.
    for (final pod in children.whereType<BossPod>().toList()) {
      pod.takeDamage(8);
    }
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
      maxCombo: combo.maxCombo,
      grazeCount: combo.grazeCount,
    );
  }

  void _endRun({required bool cleared}) {
    if (_runEnded) return;
    _runEnded = true;
    _scriptRunner.stop();
    phaseNotifier.value = GamePhase.gameOver;
    GameAudio.gameOver();
    onGameOver?.call(_buildResult(cleared: cleared));
  }
}
