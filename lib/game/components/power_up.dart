import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/painting.dart';

import '../cosmo_strike_game.dart';
import '../game_assets.dart';
import 'player_ship.dart';

/// The ten pickup orbs, mapped 1:1 onto the powerup_* sprites.
enum PowerUpKind {
  /// Tiers the primary weapon up: single → rapid → spread → laser.
  weapon,

  /// One-hit energy bubble.
  shield,

  /// +1 life.
  life,

  /// Screen-clear blast (also chunks the boss).
  bomb,

  /// Score x2 for a while.
  x2,

  /// +3 missile ammo for the special weapon.
  missiles,

  /// Faster movement + slightly faster fire for a while.
  speed,

  /// Slows enemies / enemy bullets / obstacles for a while.
  slowmo,

  /// Nearby orbs home toward the ship for a while.
  magnet,

  /// Phase out: enemies and their bullets pass through for a while.
  ghost;

  /// Weighted random drop — combat upgrades common, life/bomb rare.
  static PowerUpKind random(math.Random rng) {
    const weighted = [
      weapon, weapon, weapon,
      missiles, missiles,
      speed, speed,
      shield, shield,
      x2, x2,
      slowmo,
      magnet,
      ghost,
      bomb,
      life,
    ];
    return weighted[rng.nextInt(weighted.length)];
  }

  String get asset => switch (this) {
        PowerUpKind.weapon => GameAssets.powerupWeapon,
        PowerUpKind.shield => GameAssets.powerupShield,
        PowerUpKind.life => GameAssets.powerupLife,
        PowerUpKind.bomb => GameAssets.powerupBomb,
        PowerUpKind.x2 => GameAssets.powerupX2,
        PowerUpKind.missiles => GameAssets.powerupMissiles,
        PowerUpKind.speed => GameAssets.powerupSpeed,
        PowerUpKind.slowmo => GameAssets.powerupSlowmo,
        PowerUpKind.magnet => GameAssets.powerupMagnet,
        PowerUpKind.ghost => GameAssets.powerupGhost,
      };
}

class PowerUp extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  PowerUp({required this.kind, required Vector2 spawn})
      : super(
          position: spawn,
          size: Vector2(28, 28),
          anchor: Anchor.center,
          priority: 8,
        );

  final PowerUpKind kind;
  double _age = 0;

  late final Sprite _sprite = Sprite(Flame.images.fromCache(kind.asset));

  @override
  Future<void> onLoad() async {
    add(CircleHitbox(collisionType: CollisionType.passive));
  }

  @override
  void update(double dt) {
    _age += dt;

    // Magnet effect: home toward the ship when it's close enough.
    if (game.player.magnetActive &&
        position.distanceTo(game.player.position) < 260) {
      final dir = (game.player.position - position)..normalize();
      position += dir * 240 * dt;
    } else {
      position.x -= 90 * dt;
      position.y += math.sin(_age * 3) * 18 * dt;
    }
    if (position.x < -30) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    // Gentle pulse so orbs read as pickups, not projectiles.
    final pulse = 1.0 + math.sin(_age * 5) * 0.08;
    final drawSize = size * pulse;
    _sprite.render(
      canvas,
      position: (size - drawSize) / 2,
      size: drawSize,
    );
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is PlayerShip) {
      game.applyPowerUp(kind);
      removeFromParent();
    }
  }
}
