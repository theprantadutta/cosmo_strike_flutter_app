import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/painting.dart';

import '../cosmo_strike_game.dart';
import '../levels/level_def.dart';
import 'bullets.dart';
import 'enemy.dart';
import 'player_ship.dart';

/// End-of-level boss. Enters from the right, holds station near the right
/// edge while weaving vertically, and runs the attack signature of its
/// [BossType] with [BossDef]-scaled pacing. Reports health to the HUD via
/// the game notifier.
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

  bool _entered = false;
  double _age = 0;
  double _attackTimer = 1.5;
  int _attackIndex = 0;

  // Adds spawn once per threshold (66% / 33%).
  final List<double> _addThresholds = [0.66, 0.33];

  late final double _stationX = game.size.x * 0.78;
  late final double _baseY = game.size.y / 2;
  late final Sprite _sprite = Sprite(Flame.images.fromCache(def.type.asset));

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
    if (!_entered) {
      position.x -= 120 * dt;
      if (position.x <= _stationX) _entered = true;
      return;
    }
    // Weave inside the open band between ceiling and floor.
    final amplitude = math.max(
        20.0, (game.playfieldBottom - game.playfieldTop) / 2 - size.y / 2);
    position.y = (_baseY + math.sin(_age * 1.2) * amplitude)
        .clamp(game.playfieldTop + size.y / 2, game.playfieldBottom - size.y / 2);

    _attackTimer -= dt;
    // Zen mode: the boss doesn't fire either — it's a moving obstacle.
    if (_attackTimer <= 0 && game.mode.enemiesFire) {
      _attackTimer = def.attackInterval;
      _attackIndex++;
      _attack();
    }
  }

  void _attack() {
    switch (def.type) {
      case BossType.leviathan:
        // Signature: a vertical bullet wall with a random safe gap,
        // alternating with aimed bursts.
        if (_attackIndex.isEven) {
          _bulletWall();
        } else {
          _aimedBurst();
        }
        break;
      case BossType.dreadnought:
      case BossType.warMachine:
      case BossType.hiveQueen:
      case BossType.mothership:
        if (_attackIndex.isEven) {
          _radialSpray();
        } else {
          _aimedBurst();
        }
        break;
    }
  }

  void _radialSpray() {
    final count = def.sprayCount;
    for (int i = 0; i < count; i++) {
      // Left-facing half-circle.
      final angle = math.pi * 0.5 + (i / (count - 1)) * math.pi;
      final v = Vector2(math.cos(angle), math.sin(angle)) * def.bulletSpeed;
      game.add(EnemyBullet(
        spawn: position.clone(),
        velocity: v,
        damage: 0.25,
        fromBoss: true,
      ));
    }
  }

  void _aimedBurst() {
    final half = def.aimedCount ~/ 2;
    for (int i = -half; i <= def.aimedCount - half - 1; i++) {
      final dir = (game.player.position - position)..normalize();
      final spread = Vector2(0, i * 60.0);
      game.add(EnemyBullet(
        spawn: position.clone(),
        velocity: dir * (def.bulletSpeed + 80) + spread,
        damage: 0.3,
        fromBoss: true,
      ));
    }
  }

  /// Leviathan: a wall of bullets spanning the playfield height with one
  /// ship-sized gap to thread.
  void _bulletWall() {
    final top = game.playfieldTop + 10;
    final bottom = game.playfieldBottom - 10;
    const step = 46.0;
    final gapCenter =
        top + game.rng.nextDouble() * math.max(1, (bottom - top - 90)) + 45;
    for (double y = top; y <= bottom; y += step) {
      if ((y - gapCenter).abs() < 55) continue; // the safe gap
      game.add(EnemyBullet(
        spawn: Vector2(position.x - size.x * 0.3, y),
        velocity: Vector2(-def.bulletSpeed, 0),
        damage: 0.3,
        fromBoss: true,
      ));
    }
  }

  void _maybeSpawnAdds() {
    if (!def.spawnsAdds || _addThresholds.isEmpty) return;
    final frac = hp / maxHp;
    if (frac <= _addThresholds.first) {
      _addThresholds.removeAt(0);
      // Two escort minions matching the boss's biome flavor.
      final addType = def.type == BossType.hiveQueen
          ? EnemyType.wasp
          : EnemyType.drone;
      for (final dy in const [-90.0, 90.0]) {
        game.add(EnemyShip(
          type: addType,
          spawn: Vector2(game.size.x + 40,
              (position.y + dy).clamp(game.playfieldTop + 30, game.playfieldBottom - 30)),
          hpScale: game.level.hpScale,
          speedScale: game.level.speedScale,
          fireRateScale: game.level.fireRateScale,
          scoreScale: game.level.scoreScale,
        ));
      }
    }
  }

  void takeDamage(int dmg) {
    hp -= dmg;
    game.bossHealthNotifier.value = (hp / maxHp).clamp(0, 1).toDouble();
    if (hp <= 0) {
      game.onBossDefeated();
      removeFromParent();
    } else {
      _maybeSpawnAdds();
    }
  }

  @override
  void render(Canvas canvas) {
    _sprite.render(canvas, size: size);
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is PlayerShip) {
      game.onPlayerHit(0.5);
    }
  }
}
