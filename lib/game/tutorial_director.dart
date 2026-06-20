import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Color, IconData, Icons;

import 'components/bullets.dart';
import 'components/enemy.dart';
import 'components/fx.dart';
import 'components/power_up.dart';
import 'cosmo_strike_game.dart';
import 'game_audio.dart';
import 'levels/level_def.dart';

/// One HUD prompt of the first-run tutorial. The gameplay screen renders
/// it as a non-blocking banner above the playfield; [showSkip] gates the
/// skip affordance (hidden on the very first beat so every new pilot at
/// least learns to steer).
class TutorialPrompt {
  const TutorialPrompt({
    required this.title,
    required this.body,
    required this.icon,
    this.showSkip = true,
  });

  final String title;
  final String body;
  final IconData icon;
  final bool showSkip;
}

enum _TutorialBeat {
  steer,
  destroy,
  missile,
  dodge,
  combo,
  powerUp,
  counterFire,
  certified,
}

/// Drives the one-time interactive first run: a sequence of guided beats
/// (steer → destroy → missile → dodge → combo → power-up → counter-fire)
/// that each WAIT for the player to actually perform the action before
/// advancing. Mounted by the game instead of the level script on a fresh
/// install; when the last beat lands it hands the run off to the real
/// Level 1 choreography.
///
/// Pure game-time component (no wall clocks), so pause / revive / app
/// backgrounding freeze it exactly like the rest of the sim.
class TutorialDirector extends Component
    with HasGameReference<CosmoStrikeGame> {
  _TutorialBeat _beat = _TutorialBeat.steer;

  /// Game-seconds left before the current beat's prompt appears /
  /// the next beat starts (breathing room between beats).
  double _interlude = 0.6;

  // Beat 1 — steer: accumulated ship displacement.
  Vector2? _lastShipPos;
  double _steerDistance = 0;
  static const double _steerGoal = 150;

  // Beat 2/3 — kill/missile baselines + the hostiles this director owns.
  int _killBaseline = 0;
  int _missileBaseline = 0;
  final List<EnemyShip> _spawned = [];
  static const int _droneGoal = 3;

  // Beat 4 — dodge: graze baseline + volley clock + survival fallback.
  int _grazeBaseline = 0;
  double _volleyTimer = 0;
  double _dodgeClock = 0;
  static const double _dodgeWindow = 8;

  // Beat 5 — combo: keep a cluster of drones alive until the kill chain
  // tiers the score multiplier up to ×2 (chain ≥ 5).
  static const int _comboClusterSize = 6;
  static const int _comboTargetMultiplier = 2;

  // Beat 6 — power-up: collected baseline + the live drop on screen.
  int _powerUpBaseline = 0;
  PowerUp? _drop;

  // Beat 7 — counter-fire: the boss bolt the player must shoot down
  // (3 hits) + a small cooldown before re-firing a fresh one.
  EnemyBullet? _bossBolt;
  double _boltCooldown = 0;

  bool _ending = false;

  @override
  void update(double dt) {
    // The tutorial only advances while the sim is live (pause, revive
    // offer and game over all freeze it in place).
    if (game.phase != GamePhase.playing) return;
    if (_ending) return;

    if (_interlude > 0) {
      _interlude -= dt;
      if (_interlude > 0) return;
      _showPrompt();
    }

    switch (_beat) {
      case _TutorialBeat.steer:
        _updateSteer();
        break;
      case _TutorialBeat.destroy:
        _updateDestroy();
        break;
      case _TutorialBeat.missile:
        _updateMissile();
        break;
      case _TutorialBeat.dodge:
        _updateDodge(dt);
        break;
      case _TutorialBeat.combo:
        _updateCombo();
        break;
      case _TutorialBeat.powerUp:
        _updatePowerUp();
        break;
      case _TutorialBeat.counterFire:
        _updateCounterFire(dt);
        break;
      case _TutorialBeat.certified:
        break;
    }
  }

  // ---- Beat flow ----

  void _showPrompt() {
    switch (_beat) {
      case _TutorialBeat.steer:
        game.tutorialNotifier.value = TutorialPrompt(
          title: 'FLIGHT CONTROLS',
          body: game.dPadControls
              ? 'Hold the D-PAD to fly your ship around.'
              : 'DRAG anywhere on screen to steer — your ship '
                  'mirrors your finger.',
          icon: game.dPadControls ? Icons.gamepad : Icons.swipe,
          showSkip: false,
        );
        _lastShipPos = game.player.position.clone();
        break;
      case _TutorialBeat.destroy:
        game.tutorialNotifier.value = TutorialPrompt(
          title: 'WEAPONS HOT',
          body: game.autoFire
              ? 'Your cannon fires automatically — line up with the '
                  'scout drones and destroy all $_droneGoal!'
              : 'TAP to fire your cannon — destroy all '
                  '$_droneGoal scout drones!',
          icon: Icons.gps_fixed,
        );
        _killBaseline = game.enemiesKilled;
        _spawnDrones();
        break;
      case _TutorialBeat.missile:
        game.tutorialNotifier.value = const TutorialPrompt(
          title: 'MISSILE ARMED',
          body: 'DOUBLE-TAP (or hit the missile button) to launch it '
              'at the heavy hull!',
          icon: Icons.rocket,
        );
        _missileBaseline = game.missilesFired;
        game.missileAmmoNotifier.value += 1;
        _spawnHeavy();
        break;
      case _TutorialBeat.dodge:
        game.tutorialNotifier.value = const TutorialPrompt(
          title: 'INCOMING FIRE',
          body: 'DODGE the bolts! A near miss earns GRAZE points and '
              'charges your missile meter.',
          icon: Icons.flash_on,
        );
        _grazeBaseline = game.combo.grazeCount;
        _volleyTimer = 0.4;
        _dodgeClock = 0;
        break;
      case _TutorialBeat.combo:
        game.tutorialNotifier.value = const TutorialPrompt(
          title: 'BUILD A COMBO',
          body: 'Chain kills FAST to raise your ×2–×4 score multiplier — '
              'wipe a whole group quickly for a bonus drop!',
          icon: Icons.bolt,
        );
        _spawnComboCluster();
        break;
      case _TutorialBeat.powerUp:
        game.tutorialNotifier.value = const TutorialPrompt(
          title: 'GRAB THE POWER-UP',
          body: 'Fly into the glowing orb to collect it — power-ups upgrade '
              'your ship, shields, missiles and more.',
          icon: Icons.auto_awesome,
        );
        _powerUpBaseline = game.powerUpsCollected;
        _spawnDrop();
        break;
      case _TutorialBeat.counterFire:
        game.tutorialNotifier.value = const TutorialPrompt(
          title: 'RETURN FIRE',
          body: 'Boss bolts can be SHOT DOWN — but they are tough. Pour fire '
              'into the incoming bolt until it breaks!',
          icon: Icons.shield_moon,
        );
        _boltCooldown = 0;
        _fireBossBolt();
        break;
      case _TutorialBeat.certified:
        break;
    }
  }

  void _advance(_TutorialBeat next, {required String cheer}) {
    game.tutorialNotifier.value = null;
    game.pools.scorePopup(
      game.player.position + Vector2(0, -42),
      cheer,
      color: const Color(0xFF7DE8FF),
      scale: 1.25,
      duration: 1.0,
    );
    GameAudio.comboUp();
    _beat = next;
    _interlude = 1.0;
  }

  // ---- Beat 1: steer ----

  void _updateSteer() {
    final pos = game.player.position;
    final last = _lastShipPos;
    if (last != null) _steerDistance += pos.distanceTo(last);
    _lastShipPos = pos.clone();
    if (_steerDistance >= _steerGoal) {
      _advance(_TutorialBeat.destroy, cheer: 'NICE FLYING!');
    }
  }

  // ---- Beat 2: destroy drones ----

  void _spawnDrones() {
    for (var i = 0; i < _droneGoal; i++) {
      _addHostile(EnemyType.drone, offsetX: i * 90.0, lane: i);
    }
  }

  /// Spawns a tutorial hostile with its guns effectively disabled
  /// (fireRateScale → an hours-long fire interval) so the early beats
  /// stay about aiming, not surviving.
  void _addHostile(EnemyType type, {double offsetX = 0, int lane = 0}) {
    final top = game.playfieldTop + 60;
    final bottom = game.playfieldBottom - 60;
    final y = top + (bottom - top) * ((lane % 3) + 0.5) / 3;
    final enemy = EnemyShip(
      type: type,
      pattern: EnemyPattern.sine,
      spawn: Vector2(game.size.x + 60 + offsetX, y),
      speedScale: 0.62,
      fireRateScale: 0.0001,
    );
    _spawned.add(enemy);
    game.add(enemy);
  }

  void _updateDestroy() {
    final kills = game.enemiesKilled - _killBaseline;
    if (kills >= _droneGoal) {
      _sweepSpawned();
      _advance(_TutorialBeat.missile, cheer: 'TARGETS DOWN!');
      return;
    }
    // Refill escapees so the beat can never strand the player waiting
    // on an empty sky.
    _spawned.removeWhere((e) => e.parent == null);
    final needed = _droneGoal - kills;
    var lane = 0;
    while (_spawned.length < needed) {
      _addHostile(EnemyType.drone, offsetX: lane * 70.0, lane: lane + 1);
      lane++;
    }
  }

  // ---- Beat 3: missile ----

  void _spawnHeavy() {
    _addHostile(EnemyType.beetle, lane: 1);
  }

  void _updateMissile() {
    if (game.missilesFired - _missileBaseline >= 1) {
      _advance(_TutorialBeat.dodge, cheer: 'DIRECT HIT!');
      return;
    }
    // Keep a target on screen (and the tube loaded) for as long as the
    // beat waits.
    _spawned.removeWhere((e) => e.parent == null);
    if (_spawned.isEmpty) _spawnHeavy();
    if (game.missileAmmoNotifier.value <= 0) {
      game.missileAmmoNotifier.value = 1;
    }
  }

  // ---- Beat 4: dodge / graze ----

  void _updateDodge(double dt) {
    _dodgeClock += dt;
    _volleyTimer -= dt;
    if (_volleyTimer <= 0) {
      _volleyTimer = 1.2;
      _fireVolley();
    }
    final grazed = game.combo.grazeCount - _grazeBaseline >= 1;
    if (grazed || _dodgeClock >= _dodgeWindow) {
      game.pools.clearEnemyBullets();
      _advance(_TutorialBeat.combo, cheer: 'NICE DODGE!');
    }
  }

  /// A slow 2-bolt fan aimed just around the hull — survivable at half
  /// attention, and deliberately tight enough that dodging one bolt
  /// often grazes the other (teaching the reward, not just the threat).
  void _fireVolley() {
    final from = Vector2(game.size.x + 10, game.player.position.y);
    for (final spread in const [-30.0, 30.0]) {
      final target = game.player.position + Vector2(0, spread);
      final velocity = (target - from).normalized()..scale(170);
      game.pools.enemyBullet(spawn: from.clone(), velocity: velocity);
    }
    GameAudio.telegraph();
  }

  // ---- Beat 5: combo ----

  void _spawnComboCluster() {
    for (var i = 0; i < _comboClusterSize; i++) {
      _addHostile(EnemyType.drone, offsetX: i * 60.0, lane: i);
    }
  }

  void _updateCombo() {
    if (game.combo.multiplier >= _comboTargetMultiplier) {
      _sweepSpawned();
      _advance(_TutorialBeat.powerUp, cheer: 'COMBO ×${game.combo.multiplier}!');
      return;
    }
    // Keep the sky busy so the kill chain never starves between the 3s
    // chain windows — a thin field would let the multiplier decay.
    _spawned.removeWhere((e) => e.parent == null);
    var lane = 0;
    while (_spawned.length < _comboClusterSize) {
      _addHostile(EnemyType.drone, offsetX: lane * 56.0, lane: lane);
      lane++;
    }
  }

  // ---- Beat 6: power-up ----

  void _spawnDrop() {
    final drop = PowerUp(
      kind: PowerUpKind.weapon,
      spawn: Vector2(game.size.x + 40, game.player.position.y),
    );
    _drop = drop;
    game.add(drop);
  }

  void _updatePowerUp() {
    if (game.powerUpsCollected - _powerUpBaseline >= 1) {
      _drop = null;
      _advance(_TutorialBeat.counterFire, cheer: 'POWERED UP!');
      return;
    }
    // The orb drifts left and self-removes once it leaves the screen —
    // keep dropping a fresh one until the player flies into it.
    if (_drop?.parent == null) _spawnDrop();
  }

  // ---- Beat 7: counter-fire ----

  void _fireBossBolt() {
    GameAudio.telegraph();
    _bossBolt = game.pools.enemyBullet(
      spawn: Vector2(game.size.x + 10, game.player.position.y),
      velocity: Vector2(-150, 0),
      fromBoss: true,
    );
  }

  void _updateCounterFire(double dt) {
    if (_boltCooldown > 0) _boltCooldown -= dt;
    final bolt = _bossBolt;
    if (bolt != null && !bolt.active) {
      // hitsTaken survives deactivate(), so it tells "shot down" (reached
      // hitsRequired) apart from "expired off-screen / clipped the hull".
      if (bolt.hitsTaken >= bolt.hitsRequired) {
        _bossBolt = null;
        _certify();
        return;
      }
      _bossBolt = null;
      _boltCooldown = 0.6; // missed — send a fresh bolt after a short beat
    }
    if (_bossBolt == null && _boltCooldown <= 0) _fireBossBolt();
  }

  // ---- Wrap-up ----

  void _certify() {
    _beat = _TutorialBeat.certified;
    _ending = true;
    game.tutorialNotifier.value = null;
    _sweepSpawned();
    game.pools.scorePopup(
      game.player.position + Vector2(0, -52),
      'PILOT CERTIFIED!',
      color: const Color(0xFFFFD37B),
      scale: 1.5,
      duration: 1.6,
    );
    GameAudio.levelClear();
    game.onTutorialOutcome?.call(true);
    // Let the celebration breathe, then hand off to the real Level 1.
    add(TimerComponent(
      period: 2.2,
      removeOnFinish: true,
      onTick: () {
        game.endTutorial();
        removeFromParent();
      },
    ));
  }

  /// Skip (HUD button): clean up everything the tutorial put on screen
  /// and start the real level immediately. No completion reward.
  void skip() {
    if (_ending) return;
    _ending = true;
    game.tutorialNotifier.value = null;
    _sweepSpawned();
    _drop?.removeFromParent();
    _drop = null;
    game.pools.clearEnemyBullets();
    game.onTutorialOutcome?.call(false);
    game.endTutorial();
    removeFromParent();
  }

  /// Removes any still-alive tutorial hostiles with a pop (no score —
  /// they're set dressing, not kills).
  void _sweepSpawned() {
    for (final e in _spawned) {
      if (e.parent != null) {
        game.spawnExplosion(e.position, CosmoExplosionKind.enemy);
        e.removeFromParent();
      }
    }
    _spawned.clear();
  }
}
