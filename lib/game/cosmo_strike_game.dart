import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'components/boss.dart';
import 'components/bullets.dart';
import 'components/enemy.dart';
import 'components/explosion.dart';
import 'components/player_ship.dart';
import 'components/power_up.dart';
import 'components/starfield.dart';

enum GamePhase { ready, playing, paused, stageClear, gameOver }

/// Immutable summary of a finished run, handed to the gameplay screen so it can
/// submit the score / progression to the backend (see wiring in ApiService).
class GameResult {
  const GameResult({
    required this.score,
    required this.stageReached,
    required this.waveReached,
    required this.enemiesKilled,
    required this.bossesKilled,
    required this.durationSeconds,
    required this.cleared,
  });

  final int score;
  final int stageReached;
  final int waveReached;
  final int enemiesKilled;
  final int bossesKilled;
  final int durationSeconds;
  final bool cleared;
}

/// The Space-Impact-style shoot-'em-up. Self-contained Flame world embedded in
/// the gameplay screen only; everything else in the app stays on the existing
/// Flutter + state-management stack.
class CosmoStrikeGame extends FlameGame with HasCollisionDetection {
  CosmoStrikeGame({
    this.onGameOver,
    this.onStageClear,
    this.autoFire = true,
  });

  /// Called once when the run ends (player out of lives). The screen submits
  /// the [GameResult] to the backend and shows the game-over overlay.
  final void Function(GameResult result)? onGameOver;

  /// Called when a stage boss is defeated, before the next stage begins.
  final void Function(int stage)? onStageClear;

  bool autoFire;

  final math.Random rng = math.Random();

  late PlayerShip player;

  // HUD-facing reactive state.
  final ValueNotifier<int> scoreNotifier = ValueNotifier(0);
  final ValueNotifier<int> livesNotifier = ValueNotifier(3);
  final ValueNotifier<double> healthNotifier = ValueNotifier(1.0);
  final ValueNotifier<int> stageNotifier = ValueNotifier(1);
  final ValueNotifier<int> waveNotifier = ValueNotifier(1);
  final ValueNotifier<GamePhase> phaseNotifier = ValueNotifier(GamePhase.ready);
  // Boss health in [0,1]; -1 means no boss on screen.
  final ValueNotifier<double> bossHealthNotifier = ValueNotifier(-1);

  // Run tallies.
  int stage = 1;
  int wave = 1;
  int enemiesKilled = 0;
  int bossesKilled = 0;
  double _elapsed = 0;

  static const int wavesPerStage = 4;

  // Score multiplier power-up state.
  double scoreMultiplier = 1;
  double _multTimer = 0;

  GamePhase get phase => phaseNotifier.value;

  @override
  Color backgroundColor() => const Color(0xFF0a0501);

  @override
  Future<void> onLoad() async {
    await add(Starfield());
    player = PlayerShip();
    await add(player);
    _startRun();
  }

  void _startRun() {
    phaseNotifier.value = GamePhase.playing;
    _spawnWave();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (phase == GamePhase.playing) {
      _elapsed += dt;
      if (_multTimer > 0) {
        _multTimer -= dt;
        if (_multTimer <= 0) scoreMultiplier = 1;
      }
    }
  }

  // ---- Input from the gameplay screen ----

  /// Move the ship toward [target] (screen coordinates). The ship clamps itself
  /// to the left portion of the screen.
  void steerTo(Vector2 target) {
    if (phase == GamePhase.playing) {
      player.steerTo(target);
    }
  }

  void setAutoFire(bool value) => autoFire = value;

  /// Manual fire (tap/hold option when auto-fire is off).
  void firePrimary() {
    if (phase == GamePhase.playing) player.fire();
  }

  // ---- Wave / stage flow ----

  void _spawnWave() {
    waveNotifier.value = wave;
    final int count = 3 + wave + stage; // ramps with progress
    final pattern = EnemyPattern.values[(wave + stage) % EnemyPattern.values.length];
    for (int i = 0; i < count; i++) {
      final delay = i * 0.55;
      Future<void>.delayed(Duration(milliseconds: (delay * 1000).round()), () {
        if (isMounted && phase == GamePhase.playing) {
          final y = (size.y * 0.15) + rng.nextDouble() * (size.y * 0.6);
          add(EnemyShip(
            pattern: pattern,
            spawn: Vector2(size.x + 40, y),
            hp: 1 + (stage ~/ 2),
            speed: 70 + stage * 12 + rng.nextDouble() * 30,
            pointValue: 100 + stage * 20,
          ));
        }
      });
    }
    // After the spawn window, schedule the next wave / boss check.
    final windowSeconds = count * 0.55 + 6.0;
    add(TimerComponent(
        period: windowSeconds, removeOnFinish: true, onTick: _advanceWave));
  }

  void _advanceWave() {
    if (phase != GamePhase.playing) return;
    // Don't advance while enemies are still alive on screen.
    final remaining = children.whereType<EnemyShip>().length;
    if (remaining > 0) {
      add(TimerComponent(period: 1.5, removeOnFinish: true, onTick: _advanceWave));
      return;
    }
    if (wave >= wavesPerStage) {
      _spawnBoss();
    } else {
      wave++;
      _spawnWave();
    }
  }

  void _spawnBoss() {
    final boss = Boss(
      maxHp: 40 + stage * 25,
      spawn: Vector2(size.x + 80, size.y / 2),
    );
    add(boss);
    bossHealthNotifier.value = 1.0;
  }

  void onBossDefeated() {
    bossesKilled++;
    bossHealthNotifier.value = -1;
    addScore(1000 + stage * 250);
    phaseNotifier.value = GamePhase.stageClear;
    onStageClear?.call(stage);
  }

  /// Begin the next stage (called by the screen after the stage-clear overlay).
  void advanceToNextStage() {
    stage++;
    wave = 1;
    stageNotifier.value = stage;
    phaseNotifier.value = GamePhase.playing;
    _spawnWave();
  }

  // ---- Scoring / lives / damage ----

  void addScore(int points) {
    scoreNotifier.value += (points * scoreMultiplier).round();
  }

  void onEnemyKilled(EnemyShip enemy) {
    enemiesKilled++;
    addScore(enemy.pointValue);
    spawnExplosion(enemy.position, CosmoExplosionKind.enemy);
    // 12% chance to drop a power-up.
    if (rng.nextDouble() < 0.12) {
      add(PowerUp(kind: PowerUpKind.random(rng), spawn: enemy.position.clone()));
    }
  }

  void spawnExplosion(Vector2 at, CosmoExplosionKind kind) {
    add(buildExplosion(at, kind));
  }

  /// Player took a hit. Returns true if the player survived.
  void onPlayerHit(double damage) {
    if (phase != GamePhase.playing) return;
    if (player.shielded) {
      player.popShield();
      return;
    }
    player.health -= damage;
    healthNotifier.value = player.health.clamp(0, 1).toDouble();
    if (player.health <= 0) {
      _loseLife();
    }
  }

  void _loseLife() {
    spawnExplosion(player.position, CosmoExplosionKind.player);
    final lives = livesNotifier.value - 1;
    livesNotifier.value = lives;
    if (lives <= 0) {
      _endRun(cleared: false);
    } else {
      player.health = 1.0;
      healthNotifier.value = 1.0;
      player.respawn();
    }
  }

  void applyPowerUp(PowerUpKind kind) {
    player.applyPowerUp(kind);
    addScore(50);
    if (kind == PowerUpKind.extraLife) {
      livesNotifier.value += 1;
    } else if (kind == PowerUpKind.bomb) {
      _screenClearBomb();
    } else if (kind == PowerUpKind.scoreMultiplier) {
      scoreMultiplier = 2;
      _multTimer = 10;
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

  void _endRun({required bool cleared}) {
    phaseNotifier.value = GamePhase.gameOver;
    onGameOver?.call(GameResult(
      score: scoreNotifier.value,
      stageReached: stage,
      waveReached: wave,
      enemiesKilled: enemiesKilled,
      bossesKilled: bossesKilled,
      durationSeconds: _elapsed.round(),
      cleared: cleared,
    ));
  }

}
