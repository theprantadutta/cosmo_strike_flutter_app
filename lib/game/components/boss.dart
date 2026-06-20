import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/painting.dart';

import '../cosmo_strike_game.dart';
import '../game_audio.dart';
import '../levels/level_def.dart';
import 'bosses/boss_brain.dart';
import 'bosses/boss_pod.dart';
import 'formation_unit.dart';
import 'player_ship.dart';

/// End-of-level boss: a thin shell (hp, hitbox, render, HUD, contact
/// damage) running its type's [BossBrain] through a readable state
/// machine — entering → idle → TELEGRAPHING (hull pulses red, aim is
/// frozen, markers show exactly what's coming) → executing. Phases flip
/// at hp thresholds with a flash + hit-stop + bullet clear so pattern
/// switches never cheap-shot the player.
class Boss extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  Boss({
    required this.def,
    double hpScale = 1,
    required Vector2 spawn,
  })  : maxHp = (def.baseHp * hpScale).round(),
        super(
          position: spawn,
          size: Vector2(140, 105),
          anchor: Anchor.center,
          priority: 9,
        );

  final BossDef def;
  final int maxHp;
  late int hp = maxHp;
  late final BossBrain brain = BossBrain.forType(def.type);

  // ---- state machine ----
  bool _entered = false;
  int _phaseIndex = 0;
  int _attackCursor = 0;
  double _idleTimer = 1.5;
  double _telegraphLeft = 0;
  bool _executing = false;
  BossAttack? _current;
  // The attack fired last — lets later-level randomisation avoid picking
  // the same attack twice in a row.
  BossAttack? _lastAttack;
  double _age = 0;
  double _phaseFlash = 0;
  double _shieldPopupCd = 0;

  /// Weave/sweep oscillator phase. Advances ONLY while the boss is free
  /// to move — never while telegraph-frozen — so resuming never jumps.
  double _weavePhase = 0;

  /// Hard cap on vertical travel: the boss GLIDES to wherever its
  /// movement pattern wants it, so it can never teleport (after
  /// telegraph freezes, dash returns, or phase movement switches).
  static const double _maxVerticalSpeed = 160;

  // ---- attack scratchpad (attacks are const + shared; their transient
  // state lives here) ----
  final Vector2 capturedAim = Vector2(-1, 0);
  double capturedY = 0;
  final List<Vector2> capturedPoints = [];
  double execClock = 0;
  double scratchAngle = 0;
  int scratchCount = 0;

  final List<BossPod> pods = [];

  late final double _stationX = game.size.x * 0.78;
  // The centre of the vertical weave. Mutable: later levels relocate it
  // between attacks (see _scheduleNext) so the boss doesn't fire from a
  // predictable height.
  late double _baseY = game.size.y / 2;
  late final Sprite _sprite = Sprite(Flame.images.fromCache(def.type.asset));

  BossPhase get phase => brain.phases[_phaseIndex];
  bool get shieldedByPods => phase.invulnerableWhilePods && pods.isNotEmpty;

  /// The boss's firing point — the front-centre of the hull (it faces and
  /// fires LEFT). Projectile attacks originate here so volleys read as
  /// leaving the boss's mouth instead of its geometric centre. Returns a
  /// fresh vector each call, safe to hand straight to the bullet pool.
  Vector2 get muzzle => position + Vector2(-size.x * 0.4, 0);

  @override
  Future<void> onLoad() async {
    add(CircleHitbox(
      collisionType: CollisionType.passive,
      radius: size.x * 0.32,
      position: Vector2(size.x * 0.18, size.y / 2 - size.x * 0.32),
    ));
  }

  @override
  void update(double dt) {
    // Slow-mo power-up stretches enemy time.
    dt *= game.enemyTimeScale;
    _age += dt;
    if (_phaseFlash > 0) _phaseFlash -= dt;
    if (_shieldPopupCd > 0) _shieldPopupCd -= dt;

    if (!_entered) {
      position.x -= 120 * dt;
      if (position.x <= _stationX) {
        _entered = true;
        _enterPhase(0, initial: true);
      }
      return;
    }

    final movementOwned =
        _executing && (_current?.controlsMovement ?? false);
    // A sustained attack that doesn't drive its own movement (turret rake,
    // beam) must hold the hull still while it fires — otherwise the boss
    // weaves away from where the volley/beam originates (the "layout shift"
    // where the special appears to fire from a different place than the
    // boss). Attacks like the dash own their movement and are unaffected.
    final firingSustained =
        _executing && !(_current?.controlsMovement ?? false);
    final frozen =
        _telegraphLeft > 0 || firingSustained; // hold still: winding up OR firing
    if (!movementOwned && !frozen) _updateMovement(dt);

    // Zen mode: the boss doesn't attack — it's a moving obstacle.
    if (!game.mode.enemiesFire) return;

    if (_executing) {
      execClock += dt;
      final busy = _current!.updateExecution(this, game, dt);
      if (!busy) {
        _executing = false;
        _current = null;
        _scheduleNext();
      }
      return;
    }

    if (_telegraphLeft > 0) {
      _telegraphLeft -= dt;
      if (_telegraphLeft <= 0) {
        final attack = _current!;
        execClock = 0;
        attack.execute(this, game);
        if (attack.sustained) {
          _executing = true;
        } else {
          _current = null;
          _scheduleNext();
        }
      }
      return;
    }

    _idleTimer -= dt;
    if (_idleTimer <= 0) _startNextAttack();
  }

  void _updateMovement(double dt) {
    final halfH = size.y / 2;
    final top = game.playfieldTop + halfH;
    final bottom = game.playfieldBottom - halfH;
    final amplitude = math.max(20.0, (bottom - top) / 2);
    final double targetY;
    switch (phase.movement) {
      case BossMovement.weave:
        _weavePhase += dt * 1.2;
        targetY =
            (_baseY + math.sin(_weavePhase) * amplitude).clamp(top, bottom);
      case BossMovement.station:
        targetY = _baseY.clamp(top, bottom);
      case BossMovement.sweepVertical:
        _weavePhase += dt * 2.1;
        targetY =
            (_baseY + math.sin(_weavePhase) * amplitude).clamp(top, bottom);
    }
    // Glide, never snap: cap the vertical step so the hull always
    // travels through space the player can read.
    final maxStep = _maxVerticalSpeed * dt;
    position.y +=
        (targetY - position.y).clamp(-maxStep, maxStep).toDouble();
    // Drift back to station after dashes.
    if ((position.x - _stationX).abs() > 2) {
      position.x += (_stationX - position.x) * math.min(1, dt * 2);
    }
  }

  void _startNextAttack() {
    final attacks = phase.attacks;
    final BossAttack attack;
    if (attacks.length > 1 && game.rng.nextDouble() < _chaos * 0.7) {
      // Later levels: break the fixed rotation so the player can't memorise
      // the order. Avoid an immediate repeat so it still feels varied.
      var idx = game.rng.nextInt(attacks.length);
      if (identical(attacks[idx], _lastAttack)) {
        idx = (idx + 1) % attacks.length;
      }
      attack = attacks[idx];
      _attackCursor = idx + 1;
    } else {
      attack = attacks[_attackCursor % attacks.length];
      _attackCursor++;
    }
    _lastAttack = attack;
    _current = attack;
    _telegraphLeft = attack.telegraphSeconds;
    GameAudio.telegraph();
    attack.telegraph(this, game);
  }

  /// 0 in the first biome (levels 1–3) → ramps to 1 by the final levels.
  /// Drives how unpredictable the boss's cadence, attack order, and firing
  /// height get — early bosses stay readable; late bosses keep you guessing.
  double get _chaos => ((game.levelIndex - 3) / 7).clamp(0.0, 1.0).toDouble();

  /// Gap before the next attack. Later levels tighten it slightly AND
  /// jitter it so the rhythm isn't a metronome you can count down.
  double _nextInterval() {
    final base = def.attackInterval * phase.intervalScale;
    final c = _chaos;
    final tighten = 1 - 0.18 * c;
    final jitter = 1 + (game.rng.nextDouble() * 2 - 1) * 0.4 * c;
    return base * tighten * jitter;
  }

  /// Schedule the idle gap and, in later levels, relocate the weave centre
  /// so the next volley — and the beam, which rakes the boss's own row —
  /// originates from an unpredictable height instead of the same band.
  void _scheduleNext() {
    _idleTimer = _nextInterval();
    if (game.rng.nextDouble() < _chaos * 0.6) {
      final halfH = size.y / 2;
      final top = game.playfieldTop + halfH;
      final bottom = game.playfieldBottom - halfH;
      _baseY = top + game.rng.nextDouble() * math.max(1, bottom - top);
    }
  }

  void _enterPhase(int index, {bool initial = false}) {
    _phaseIndex = index;
    _attackCursor = 0;
    _telegraphLeft = 0;
    _executing = false;
    _current = null;
    _idleTimer = initial ? 1.2 : 1.0; // post-flip grace

    if (!initial) {
      // Pattern switches never cheap-shot: clear in-flight boss bullets,
      // punctuate with flash + freeze + shake.
      game.pools.clearBossBullets();
      game.hitStop(0.05);
      game.shake(intensity: 8, duration: 0.35);
      GameAudio.bossPhase();
      _phaseFlash = 0.4;
    }

    final addWave = phase.addWave;
    if (addWave != null) game.add(Formation(spec: addWave));

    for (var i = 0; i < phase.podCount; i++) {
      final pod = BossPod(
        boss: this,
        orbitIndex: i,
        orbitCount: phase.podCount,
        hp: (maxHp * 0.1).clamp(6, 40).round(),
        isShieldGenerator: def.type == BossType.warMachine,
      );
      pods.add(pod);
      game.add(pod);
    }
  }

  void onPodGone(BossPod pod) {
    pods.remove(pod);
  }

  void takeDamage(int dmg) {
    if (!_entered) return;
    if (shieldedByPods) {
      // Core is gated behind the pods — make the plink readable.
      if (_shieldPopupCd <= 0) {
        _shieldPopupCd = 0.9;
        game.pools.scorePopup(
          position + Vector2(-size.x * 0.3, -size.y * 0.4),
          'SHIELDED',
          color: const Color(0xFF9DB4FF),
        );
      }
      game.pools.hitSpark(position + Vector2(-size.x * 0.3, 0));
      return;
    }
    hp -= dmg;
    game.bossHealthNotifier.value = (hp / maxHp).clamp(0, 1).toDouble();
    if (hp <= 0) {
      for (final pod in pods.toList()) {
        pod.removeFromParent();
      }
      game.onBossDefeated();
      removeFromParent();
      return;
    }
    _maybeAdvancePhase();
  }

  void _maybeAdvancePhase() {
    final frac = hp / maxHp;
    var target = _phaseIndex;
    while (target < brain.phases.length - 1 &&
        frac <= brain.phases[target].untilHpFrac) {
      target++;
    }
    if (target != _phaseIndex) _enterPhase(target);
  }

  @override
  void render(Canvas canvas) {
    Paint? paint;
    if (_telegraphLeft > 0) {
      // Windup: the hull pulses hot — an attack is coming.
      final pulse = 0.3 + 0.3 * (0.5 + 0.5 * math.sin(_age * 16));
      paint = Paint()
        ..colorFilter = ColorFilter.mode(
          Color.fromRGBO(255, 64, 110, pulse),
          BlendMode.srcATop,
        );
    } else if (_phaseFlash > 0) {
      paint = Paint()
        ..colorFilter = ColorFilter.mode(
          Color.fromRGBO(255, 255, 255, (_phaseFlash / 0.4) * 0.8),
          BlendMode.srcATop,
        );
    }
    _sprite.render(canvas, size: size, overridePaint: paint);
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is PlayerShip) {
      game.onPlayerHit(0.5);
    }
  }
}
